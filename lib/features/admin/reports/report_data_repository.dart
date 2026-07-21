// lib/features/admin/reports/report_data_repository.dart
//
// Pulls the raw data needed for exports: per-employee daily summaries
// (worked/expected/adjustment/net minutes) plus the underlying attendance
// records for the same range, for a detailed report.

import '../../../../../../core/api/supabase_client.dart';

class ReportRow {
  final String userId;
  final String fullName;
  final DateTime workDate;
  final int workedMinutes;
  final int expectedMinutes;
  final int adjustmentMinutes;
  final int netMinutes;
  final bool hasDanglingPunch;

  const ReportRow({
    required this.userId,
    required this.fullName,
    required this.workDate,
    required this.workedMinutes,
    required this.expectedMinutes,
    required this.adjustmentMinutes,
    required this.netMinutes,
    required this.hasDanglingPunch,
  });

  double get workedHours => workedMinutes / 60.0;
  double get expectedHours => expectedMinutes / 60.0;
  double get adjustmentHours => adjustmentMinutes / 60.0;
  double get netHours => netMinutes / 60.0;

  factory ReportRow.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return ReportRow(
      userId: map['user_id'] as String,
      fullName: profile['full_name'] as String,
      workDate: DateTime.parse(map['work_date'] as String),
      workedMinutes: (map['worked_minutes'] as num).toInt(),
      expectedMinutes: (map['expected_minutes'] as num).toInt(),
      adjustmentMinutes: (map['adjustment_minutes'] as num).toInt(),
      netMinutes: (map['net_minutes'] as num).toInt(),
      hasDanglingPunch: map['has_dangling_punch'] as bool,
    );
  }
}

class ReportDataRepository {
  /// Fetches daily_hours_summary rows for a date range, optionally scoped
  /// to a single employee. Ordered by employee then date for clean report
  /// grouping.
  Future<List<ReportRow>> fetchSummaryReport({
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    var query = SupabaseService.client
        .from('daily_hours_summary')
        .select('user_id, work_date, worked_minutes, expected_minutes, '
            'adjustment_minutes, net_minutes, has_dangling_punch, profiles!inner(full_name)')
        .gte('work_date', _dateOnly(startDate))
        .lte('work_date', _dateOnly(endDate));

    if (userId != null) {
      query = query.eq('user_id', userId);
    }

    final rows = await query.order('work_date', ascending: true);

    final result = (rows as List)
        .map((row) => ReportRow.fromMap(row as Map<String, dynamic>))
        .toList();

    result.sort((a, b) {
      final nameCompare = a.fullName.compareTo(b.fullName);
      if (nameCompare != 0) return nameCompare;
      return a.workDate.compareTo(b.workDate);
    });

    return result;
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
