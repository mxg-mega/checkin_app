// lib/features/admin/repository/team_overview_repository.dart
//
// Reads from v_dangling_shifts (missed clock-outs) and daily_hours_summary
// (per-employee overtime/repay standing) to power the admin dashboard.

import '../../../../../../core/api/supabase_client.dart';

class DanglingShift {
  final String clockInId;
  final String userId;
  final String fullName;
  final DateTime clockInTime;
  final double hoursOpen;

  const DanglingShift({
    required this.clockInId,
    required this.userId,
    required this.fullName,
    required this.clockInTime,
    required this.hoursOpen,
  });

  factory DanglingShift.fromMap(Map<String, dynamic> map) => DanglingShift(
        clockInId: map['clock_in_id'] as String,
        userId: map['user_id'] as String,
        fullName: map['full_name'] as String,
        clockInTime: DateTime.parse(map['clock_in_time'] as String),
        hoursOpen: (map['hours_open'] as num).toDouble(),
      );

  /// Matches the >=16h threshold used elsewhere (client-side dangling check,
  /// admin dashboard highlighting) to flag this as very likely forgotten
  /// rather than just a long shift still in progress.
  bool get isLikelyForgotten => hoursOpen >= 16;
}

class EmployeeHoursStanding {
  final String userId;
  final String fullName;
  final int netMinutesThisPeriod; // positive = overtime owed, negative = owes hours

  const EmployeeHoursStanding({
    required this.userId,
    required this.fullName,
    required this.netMinutesThisPeriod,
  });

  double get netHours => netMinutesThisPeriod / 60.0;
}

class TeamOverviewRepository {
  Future<List<DanglingShift>> fetchDanglingShifts() async {
    final rows = await SupabaseService.client.from('v_dangling_shifts').select();
    return (rows as List)
        .map((row) => DanglingShift.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Aggregates daily_hours_summary.net_minutes per employee for the given
  /// date range (e.g. current pay period) to show who's in overtime and
  /// who owes hours at a glance.
  Future<List<EmployeeHoursStanding>> fetchHoursStanding({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);

    final rows = await SupabaseService.client
        .from('daily_hours_summary')
        .select('user_id, net_minutes, profiles!inner(full_name)')
        .gte('work_date', start)
        .lte('work_date', end);

    final totals = <String, int>{};
    final names = <String, String>{};

    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      final userId = map['user_id'] as String;
      final netMinutes = (map['net_minutes'] as num).toInt();
      final profile = map['profiles'] as Map<String, dynamic>;

      totals[userId] = (totals[userId] ?? 0) + netMinutes;
      names[userId] = profile['full_name'] as String;
    }

    final standings = totals.entries
        .map((e) => EmployeeHoursStanding(
              userId: e.key,
              fullName: names[e.key] ?? 'Unknown',
              netMinutesThisPeriod: e.value,
            ))
        .toList()
      ..sort((a, b) => a.netMinutesThisPeriod.compareTo(b.netMinutesThisPeriod));

    return standings;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
