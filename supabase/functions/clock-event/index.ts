// supabase/functions/clock-event/index.ts
//
// The client calls THIS function to clock in/out — never inserts into
// attendance_records directly. This is what actually enforces the
// "hard lock" geofence rule server-side (the DB trigger is backup defense).

// Use a more recent std version to avoid missing-module/type issues in some
// environments. Update the version if your runtime requires a different one.
import { serve } from "https://deno.land/std@0.201.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ClockRequest {
  type: "clock_in" | "clock_out";
  latitude: number;
  longitude: number;
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // --- Identify the calling user from their JWT (passed through by Supabase) ---
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return jsonResponse({ error: "Missing auth token" }, 401);

    const supabaseAsUser = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userErr } = await supabaseAsUser.auth.getUser();
    if (userErr || !userData?.user) return jsonResponse({ error: "Invalid session" }, 401);
    const userId = userData.user.id;

    const body: ClockRequest = await req.json();
    const { type, latitude, longitude } = body;

    if (!type || latitude == null || longitude == null) {
      return jsonResponse({ error: "type, latitude, longitude are required" }, 400);
    }
    if (typeof latitude !== "number" || typeof longitude !== "number") {
      return jsonResponse({ error: "latitude/longitude must be numbers" }, 400);
    }

    // Use service role from here to bypass RLS for the geofence lookup + insert,
    // since we've already authenticated the user ourselves above.
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    // --- 1. Find nearest active office ---
    const { data: offices, error: officeErr } = await supabase
      .from("office_locations")
      .select("id, name, latitude, longitude, radius_meters")
      .eq("is_active", true);
    if (officeErr) throw officeErr;
    if (!offices || offices.length === 0) {
      return jsonResponse({ error: "No active office locations configured" }, 500);
    }

    let nearest = offices[0];
    let nearestDistance = haversineMeters(latitude, longitude, nearest.latitude, nearest.longitude);
    for (const office of offices.slice(1)) {
      const d = haversineMeters(latitude, longitude, office.latitude, office.longitude);
      if (d < nearestDistance) {
        nearest = office;
        nearestDistance = d;
      }
    }

    // --- 2. Hard lock: reject if outside geofence ---
    if (nearestDistance > nearest.radius_meters) {
      return jsonResponse(
        {
          error: "OUTSIDE_GEOFENCE",
          message: `You're ${Math.round(nearestDistance)}m from ${nearest.name}. You must be within ${nearest.radius_meters}m to clock ${type === "clock_in" ? "in" : "out"}.`,
          distance_meters: Math.round(nearestDistance),
          allowed_radius_meters: nearest.radius_meters,
        },
        403,
      );
    }

    // --- 3. Prevent double clock-in / clock-out (state check) ---
    const { data: lastEvent, error: lastErr } = await supabase
      .from("attendance_records")
      .select("type, recorded_at")
      .eq("user_id", userId)
      .eq("is_voided", false)
      .order("recorded_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (lastErr) throw lastErr;

    if (lastEvent?.type === type) {
      const action = type === "clock_in" ? "clocked in" : "clocked out";
      return jsonResponse(
        { error: "INVALID_STATE", message: `You're already ${action}. Cannot ${type} twice in a row.` },
        409,
      );
    }

    // --- 4. Insert the record ---
    const { data: inserted, error: insertErr } = await supabase
      .from("attendance_records")
      .insert({
        user_id: userId,
        type,
        source: "gps_clock",
        latitude,
        longitude,
        distance_from_office_meters: nearestDistance,
        office_id: nearest.id,
        created_by: userId,
      })
      .select()
      .single();
    if (insertErr) throw insertErr;

    // --- 5. Fire-and-forget: trigger recompute of today's summary for this user ---
    // (Not awaited on purpose — don't block the clock response on this.)
    const today = new Date().toISOString().slice(0, 10);
    fetch(`${supabaseUrl}/functions/v1/compute-daily-hours`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${serviceRoleKey}`,
      },
      body: JSON.stringify({ user_id: userId, start_date: today, end_date: today }),
    }).catch((e) => console.error("Failed to trigger summary recompute:", e));

    return jsonResponse({ success: true, record: inserted, distance_meters: Math.round(nearestDistance) });
  } catch (err) {
    console.error(err);
    return jsonResponse({ error: (err as Error).message }, 500);
  }
});

function haversineMeters(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(a));
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}