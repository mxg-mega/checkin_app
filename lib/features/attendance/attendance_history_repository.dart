// lib/features/attendance/attendance_history_repository.dart
//
// Employee-facing: shows the signed-in user's own raw clock in/out
// records so they can verify their punches were captured correctly.
// Deliberately does NOT expose net hours / overtime / repay — that's
// admin-only and requested at month-end (see daily_hours_summary RLS).

import '../../core/api/supabase_client.dart';

class AttendanceRecordView {
  final String id;
  final String type; // 'clock_in' or 'clock_out'
  final String source; // 'gps_clock' or 'admin_manual'
  final DateTime recordedAt;
  final double? distanceFromOfficeMeters;

  const AttendanceRecordView({
    required this.id,
    required this.type,
    required this.source,
    required this.recordedAt,
    required this.distanceFromOfficeMeters,
  });

  factory AttendanceRecordView.fromMap(Map<String, dynamic> map) => AttendanceRecordView(
        id: map['id'] as String,
        type: map['type'] as String,
        source: map['source'] as String,
        recordedAt: DateTime.parse(map['recorded_at'] as String),
        distanceFromOfficeMeters: (map['distance_from_office_meters'] as num?)?.toDouble(),
      );
}

class AttendanceHistoryRepository {
  Future<List<AttendanceRecordView>> fetchMyRecent({int limit = 50}) async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return [];

    final rows = await SupabaseService.client
        .from('attendance_records')
        .select('id, type, source, recorded_at, distance_from_office_meters')
        .eq('user_id', userId)
        .eq('is_voided', false)
        .order('recorded_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((row) => AttendanceRecordView.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
