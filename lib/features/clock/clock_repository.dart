// lib/features/clock/clock_repository.dart
//
// Talks to the `clock-event` Supabase Edge Function — never inserts
// into attendance_records directly from the client. The Edge Function
// is the single source of truth for the geofence hard-lock.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api/supabase_client.dart';
import '../../core/location/location_service.dart';

enum ClockEventType { clockIn, clockOut }

extension on ClockEventType {
  String get apiValue => this == ClockEventType.clockIn ? 'clock_in' : 'clock_out';
}

sealed class ClockResult {
  const ClockResult();
}

class ClockSuccess extends ClockResult {
  final Map<String, dynamic> record;
  final double distanceMeters;

  const ClockSuccess({required this.record, required this.distanceMeters});
}

class ClockOutsideGeofence extends ClockResult {
  final double distanceMeters;
  final double allowedRadiusMeters;
  final String message;

  const ClockOutsideGeofence({
    required this.distanceMeters,
    required this.allowedRadiusMeters,
    required this.message,
  });
}

class ClockInvalidState extends ClockResult {
  final String message;
  const ClockInvalidState(this.message);
}

class ClockLocationUnavailable extends ClockResult {
  final LocationFailureReason reason;
  final String message;
  const ClockLocationUnavailable(this.reason, this.message);
}

class ClockError extends ClockResult {
  final String message;
  const ClockError(this.message);
}

/// Represents whether the signed-in user is currently clocked in or out,
/// derived from their most recent non-voided attendance_records row.
enum LastClockStatus { clockedIn, clockedOut }

sealed class LastClockStateResult {
  const LastClockStateResult();
}

class LastClockStateLoaded extends LastClockStateResult {
  final LastClockStatus status;
  final DateTime? lastEventAt;
  final bool isDanglingOvernight; // clocked in > 16h ago with no clock_out — likely forgotten

  const LastClockStateLoaded({
    required this.status,
    required this.lastEventAt,
    required this.isDanglingOvernight,
  });
}

class LastClockStateError extends LastClockStateResult {
  final String message;
  const LastClockStateError(this.message);
}

class ClockRepository {
  final LocationService _locationService;

  ClockRepository({LocationService? locationService})
      : _locationService = locationService ?? LocationService();

  /// Fetches the user's most recent attendance record (clock_in or clock_out)
  /// to determine their current clock state. Call this on app startup / resume
  /// so the UI shows the correct "Clock In" vs "Clock Out" button immediately,
  /// rather than defaulting to an assumed state.
  ///
  /// Reads directly from attendance_records via the authenticated client —
  /// this is a read-only query and RLS already restricts it to the caller's
  /// own rows, so no Edge Function round-trip is needed here.
  Future<LastClockStateResult> fetchLastClockState() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) {
      return const LastClockStateError('No authenticated user.');
    }

    try {
      final rows = await SupabaseService.client
          .from('attendance_records')
          .select('type, recorded_at')
          .eq('user_id', userId)
          .eq('is_voided', false)
          .order('recorded_at', ascending: false)
          .limit(1);

      if (rows.isEmpty) {
        // No attendance history at all yet — treat as clocked out.
        return const LastClockStateLoaded(
          status: LastClockStatus.clockedOut,
          lastEventAt: null,
          isDanglingOvernight: false,
        );
      }

      final latest = rows.first as Map<String, dynamic>;
      final type = latest['type'] as String;
      final recordedAt = DateTime.parse(latest['recorded_at'] as String);

      final status = type == 'clock_in' ? LastClockStatus.clockedIn : LastClockStatus.clockedOut;

      final hoursSinceEvent = DateTime.now().toUtc().difference(recordedAt.toUtc()).inHours;
      final isDangling = status == LastClockStatus.clockedIn && hoursSinceEvent >= 16;

      return LastClockStateLoaded(
        status: status,
        lastEventAt: recordedAt,
        isDanglingOvernight: isDangling,
      );
    } on PostgrestException catch (e) {
      return LastClockStateError('Could not load attendance status: ${e.message}');
    } catch (e) {
      return LastClockStateError('Unexpected error loading attendance status: $e');
    }
  }

  Future<ClockResult> performClock(ClockEventType type) async {
    // 1. Get a fresh, high-accuracy GPS fix.
    final locationResult = await _locationService.getCurrentPosition();

    if (locationResult is LocationFailure) {
      return ClockLocationUnavailable(locationResult.reason, locationResult.message);
    }

    final position = locationResult as LocationSuccess;

    // 2. Call the Edge Function — it does the authoritative geofence check.
    try {
      final response = await SupabaseService.client.functions.invoke(
        'clock-event',
        body: {
          'type': type.apiValue,
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
      );

      final data = response.data as Map<String, dynamic>;

      if (response.status == 200) {
        return ClockSuccess(
          record: data['record'] as Map<String, dynamic>,
          distanceMeters: (data['distance_meters'] as num).toDouble(),
        );
      }

      if (response.status == 403 && data['error'] == 'OUTSIDE_GEOFENCE') {
        return ClockOutsideGeofence(
          distanceMeters: (data['distance_meters'] as num).toDouble(),
          allowedRadiusMeters: (data['allowed_radius_meters'] as num).toDouble(),
          message: data['message'] as String,
        );
      }

      if (response.status == 409 && data['error'] == 'INVALID_STATE') {
        return ClockInvalidState(data['message'] as String);
      }

      return ClockError(data['message'] as String? ?? 'Unknown error occurred.');
    } on FunctionException catch (e) {
      return ClockError('Server error: ${e.details ?? e.reasonPhrase ?? 'unknown'}');
    } catch (e) {
      return ClockError('Network error: $e');
    }
  }
}