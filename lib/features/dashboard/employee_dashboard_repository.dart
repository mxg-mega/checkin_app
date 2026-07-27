import '../../core/api/supabase_client.dart';

class EmployeeDashboardRepository {
  /// Fetches the current user's net minutes from daily_hours_summary
  /// positive = overtime, negative = owed hours
  Future<int> fetchMyNetMinutesThisPeriod(DateTime startDate, DateTime endDate) async {
    final start = _dateOnly(startDate);
    final end = _dateOnly(endDate);
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return 0;

    try {
      final rows = await SupabaseService.client
          .from('daily_hours_summary')
          .select('net_minutes')
          .eq('user_id', userId)
          .gte('work_date', start)
          .lte('work_date', end);

      int totalNetMinutes = 0;
      for (final row in rows as List) {
        totalNetMinutes += ((row as Map<String, dynamic>)['net_minutes'] as num).toInt();
      }
      return totalNetMinutes;
    } catch (e) {
      // If RLS prevents reading this table, return 0 or handle accordingly
      // (The user requested this dashboard, so they should allow RLS on this)
      return 0;
    }
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
