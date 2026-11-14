// supabase/functions/compute-daily-hours/index.ts
//
// Purpose: for a given user + date range, pair up clock_in/clock_out
// attendance_records, fold in hours_adjustments, and upsert the result
// into daily_hours_summary.
//
// Expected hours per day are 7h flat, but ONLY on days that fall within
// the employee's team schedule:
//   - team_a:    Mon, Tue, Wed, Thu, Fri
//   - team_b:    Wed, Thu, Fri, Sat, Sun
//   - full_week: every day
// Wed/Thu/Fri are shared "everyone works" days. Non-scheduled days always
// get expected_minutes = 0, so they never count against the employee.
//
// This data is admin-only (see RLS on daily_hours_summary) — employees
// don't see net hours day-to-day; it's requested from admin at month-end.
//
// Trigger this:
//   1. On a schedule (e.g. nightly cron via pg_cron or Supabase Scheduled Functions)
//   2. On-demand right after a clock_out or an admin adjustment, scoped to that user+date
//
// This runs with the service role key — it bypasses RLS deliberately,
// since it needs to read/write across all users. Never expose this
// function's URL to the client without your own auth check (see below).

import { serve } from "https://deno.land/std@0.192.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface RequestBody {
  user_id?: string;       // if omitted, recompute for all active users
  start_date: string;     // 'YYYY-MM-DD'
  end_date: string;       // 'YYYY-MM-DD'
}

interface AttendanceRow {
  id: string;
  user_id: string;
  type: "clock_in" | "clock_out";
  recorded_at: string;
  is_voided: boolean;
}

interface AdjustmentRow {
  user_id: string;
  hours: number;
  applies_to_date: string;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // --- Auth check: only allow service-role or admin-invoked calls ---
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.includes(serviceRoleKey)) {
      // In production, also allow calls where the caller's JWT role = admin.
      // Kept simple here; wire up your own admin check if calling from client.
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body: RequestBody = await req.json();
    const { user_id, start_date, end_date } = body;

    if (!start_date || !end_date) {
      return jsonResponse({ error: "start_date and end_date are required" }, 400);
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // --- 1. Get the list of users to process ---
    let userIds: string[];
    if (user_id) {
      userIds = [user_id];
    } else {
      const { data: users, error } = await supabase
        .from("profiles")
        .select("id")
        .eq("is_active", true);
      if (error) throw error;
      userIds = (users ?? []).map((u) => u.id);
    }

    const results: Record<string, unknown> = {};

    for (const uid of userIds) {
      const summary = await computeUserRange(supabase, uid, start_date, end_date);
      results[uid] = summary;
    }

    return jsonResponse({ success: true, processed: userIds.length, results });
  } catch (err) {
    console.error(err);
    return jsonResponse({ error: (err as Error).message }, 500);
  }
});

async function computeUserRange(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  userId: string,
  startDate: string,
  endDate: string,
) {
  // --- 2. Fetch profile for schedule + daily hours target ---
  const { data: profile, error: profileErr } = await supabase
    .from("profiles")
    .select("schedule, expected_hours_per_day")
    .eq("id", userId)
    .single();
  if (profileErr) throw profileErr;

  const schedule = profile.schedule as "team_a" | "team_b" | "full_week";
  const expectedMinutesPerScheduledDay = Math.round(Number(profile.expected_hours_per_day) * 60);

  // --- 3. Fetch attendance records in range (with 1-day padding to catch overnight shifts) ---
  const paddedStart = shiftDate(startDate, -1);
  const paddedEnd = shiftDate(endDate, 1);

  const { data: records, error: recErr } = await supabase
    .from("attendance_records")
    .select("id, user_id, type, recorded_at, is_voided")
    .eq("user_id", userId)
    .eq("is_voided", false)
    .gte("recorded_at", `${paddedStart}T00:00:00Z`)
    .lte("recorded_at", `${paddedEnd}T23:59:59Z`)
    .order("recorded_at", { ascending: true });
  if (recErr) throw recErr;

  // --- 4. Fetch adjustments in range ---
  const { data: adjustments, error: adjErr } = await supabase
    .from("hours_adjustments")
    .select("user_id, hours, applies_to_date")
    .eq("user_id", userId)
    .eq("is_voided", false)
    .gte("applies_to_date", startDate)
    .lte("applies_to_date", endDate);
  if (adjErr) throw adjErr;

  // --- 5. Pair clock_in/clock_out chronologically ---
  const dailyWorkedMinutes = new Map<string, number>();
  const danglingDates = new Set<string>();

  let openClockIn: AttendanceRow | null = null;
  for (const rec of (records ?? []) as AttendanceRow[]) {
    if (rec.type === "clock_in") {
      if (openClockIn) {
        // Two clock-ins in a row with no clock-out between them: mark the first as dangling.
        danglingDates.add(openClockIn.recorded_at.slice(0, 10));
      }
      openClockIn = rec;
    } else if (rec.type === "clock_out" && openClockIn) {
      const inTime = new Date(openClockIn.recorded_at).getTime();
      const outTime = new Date(rec.recorded_at).getTime();
      const minutes = Math.max(0, Math.round((outTime - inTime) / 60000));

      // Attribute worked minutes to the clock_in's calendar date.
      const workDate = openClockIn.recorded_at.slice(0, 10);
      dailyWorkedMinutes.set(workDate, (dailyWorkedMinutes.get(workDate) ?? 0) + minutes);

      openClockIn = null;
    }
  }
  if (openClockIn) {
    danglingDates.add(openClockIn.recorded_at.slice(0, 10));
  }

  // --- 6. Fold in adjustments per date ---
  const dailyAdjustmentMinutes = new Map<string, number>();
  for (const adj of (adjustments ?? []) as AdjustmentRow[]) {
    const d = adj.applies_to_date;
    const mins = Math.round(Number(adj.hours) * 60);
    dailyAdjustmentMinutes.set(d, (dailyAdjustmentMinutes.get(d) ?? 0) + mins);
  }

  // --- 7. Build the set of dates actually in [startDate, endDate] and upsert ---
  const dates = enumerateDates(startDate, endDate);
  const upserts = dates.map((workDate) => {
    const workedMinutes = dailyWorkedMinutes.get(workDate) ?? 0;
    const adjustmentMinutes = dailyAdjustmentMinutes.get(workDate) ?? 0;
    const isScheduled = isScheduledWorkday(schedule, workDate);
    const expectedMinutes = isScheduled ? expectedMinutesPerScheduledDay : 0;

    return {
      user_id: userId,
      work_date: workDate,
      worked_minutes: workedMinutes,
      expected_minutes: expectedMinutes,
      adjustment_minutes: adjustmentMinutes,
      has_dangling_punch: danglingDates.has(workDate),
      computed_at: new Date().toISOString(),
    };
  });

  const { error: upsertErr } = await supabase
    .from("daily_hours_summary")
    .upsert(upserts, { onConflict: "user_id,work_date" });
  if (upsertErr) throw upsertErr;

  return {
    days_processed: upserts.length,
    dangling_dates: Array.from(danglingDates),
  };
}

function shiftDate(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function enumerateDates(start: string, end: string): string[] {
  const dates: string[] = [];
  let cur = new Date(`${start}T00:00:00Z`);
  const last = new Date(`${end}T00:00:00Z`);
  while (cur <= last) {
    dates.push(cur.toISOString().slice(0, 10));
    cur.setUTCDate(cur.getUTCDate() + 1);
  }
  return dates;
}

// Mirrors the Postgres is_scheduled_workday() function — keep both in sync.
// Wed(3)/Thu(4)/Fri(5): everyone works. Mon(1)/Tue(2): team_a only.
// Sat(6)/Sun(0): team_b only. full_week: every day.
function isScheduledWorkday(schedule: "team_a" | "team_b" | "full_week", dateStr: string): boolean {
  const day = new Date(`${dateStr}T00:00:00Z`).getUTCDay(); // 0=Sun ... 6=Sat
  if (day === 3 || day === 4 || day === 5) return true; // Wed/Thu/Fri — full team
  if (schedule === "full_week") return true;
  if (schedule === "team_a") return day === 1 || day === 2; // Mon/Tue
  if (schedule === "team_b") return day === 0 || day === 6; // Sun/Sat
  return false;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
