// lib/core/location/location_service.dart
//
// Wraps geolocator to provide a single, testable entry point for
// getting the user's current position before a clock-in/out attempt.
//
// Design notes:
// - We request HIGH accuracy since the geofence radius is only 250-500m;
//   a low-accuracy fix could wrongly reject/accept someone near the edge.
// - We never trust this position as the final authority — it's sent to
//   the clock-event Edge Function, which re-validates server-side.
// - Errors are modeled explicitly (not thrown as generic exceptions) so
//   the UI can show specific, actionable messages ("enable GPS", "permission
//   denied", "timed out") rather than a generic failure.

import 'package:geolocator/geolocator.dart';

sealed class LocationResult {
  const LocationResult();
}

class LocationSuccess extends LocationResult {
  final double latitude;
  final double longitude;
  final double accuracyMeters;

  const LocationSuccess({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });
}

enum LocationFailureReason {
  serviceDisabled,   // device GPS/location services turned off entirely
  permissionDenied,  // user denied the permission prompt
  permissionDeniedForever, // user denied + checked "don't ask again"
  timeout,           // took too long to get a fix
  lowAccuracy,       // got a fix, but accuracy is too poor to trust near geofence edge
  unknown,
}

class LocationFailure extends LocationResult {
  final LocationFailureReason reason;
  final String message;

  const LocationFailure(this.reason, this.message);
}

class LocationService {
  /// Maximum acceptable GPS accuracy (in meters) for a clock attempt.
  /// If the device reports worse than this, we reject the reading rather
  /// than risk a false accept/reject near the geofence boundary.
  static const double maxAcceptableAccuracyMeters = 30.0;

  static const Duration _timeout = Duration(seconds: 15);

  Future<LocationResult> getCurrentPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationFailure(
          LocationFailureReason.serviceDisabled,
          'Location services are turned off. Please enable GPS to clock in/out.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const LocationFailure(
            LocationFailureReason.permissionDenied,
            'Location permission is required to clock in/out.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationFailure(
          LocationFailureReason.permissionDeniedForever,
          'Location permission was permanently denied. Please enable it in Settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: _timeout,
      );

      if (position.accuracy > maxAcceptableAccuracyMeters) {
        return LocationFailure(
          LocationFailureReason.lowAccuracy,
          'GPS signal is too weak (±${position.accuracy.round()}m). '
          'Move to an open area and try again.',
        );
      }

      return LocationSuccess(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
      );
    } on LocationServiceDisabledException {
      return const LocationFailure(
        LocationFailureReason.serviceDisabled,
        'Location services are turned off. Please enable GPS to clock in/out.',
      );
    } catch (e) {
      final isTimeout = e.toString().toLowerCase().contains('timeout');
      if (isTimeout) {
        return const LocationFailure(
          LocationFailureReason.timeout,
          'Could not get a GPS fix in time. Try moving outdoors and retry.',
        );
      }
      return LocationFailure(LocationFailureReason.unknown, 'Unexpected location error: $e');
    }
  }
}
