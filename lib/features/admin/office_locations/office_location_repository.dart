// lib/features/admin/office_locations/office_location_repository.dart
//
// Admin-only CRUD for office_locations. RLS already restricts writes to
// admins (see "Admins manage office locations" policy in schema.sql);
// this repository is the client-side counterpart.

import '../../../core/api/supabase_client.dart';

class OfficeLocation {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final bool isActive;

  const OfficeLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.isActive,
  });

  factory OfficeLocation.fromMap(Map<String, dynamic> map) => OfficeLocation(
        id: map['id'] as String,
        name: map['name'] as String,
        latitude: (map['latitude'] as num).toDouble(),
        longitude: (map['longitude'] as num).toDouble(),
        radiusMeters: (map['radius_meters'] as num).toInt(),
        isActive: map['is_active'] as bool,
      );
}

sealed class OfficeLocationResult {
  const OfficeLocationResult();
}

class OfficeLocationSuccess extends OfficeLocationResult {
  final OfficeLocation location;
  const OfficeLocationSuccess(this.location);
}

class OfficeLocationError extends OfficeLocationResult {
  final String message;
  const OfficeLocationError(this.message);
}

class OfficeLocationRepository {
  Future<List<OfficeLocation>> fetchAll() async {
    final rows = await SupabaseService.client
        .from('office_locations')
        .select()
        .order('is_active', ascending: false)
        .order('name', ascending: true);

    return (rows as List)
        .map((row) => OfficeLocation.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<OfficeLocationResult> create({
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    if (radiusMeters < 100 || radiusMeters > 2000) {
      return const OfficeLocationError('Radius must be between 100 and 2000 meters.');
    }
    try {
      final row = await SupabaseService.client
          .from('office_locations')
          .insert({
            'name': name.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'radius_meters': radiusMeters,
            'is_active': true,
          })
          .select()
          .single();
      return OfficeLocationSuccess(OfficeLocation.fromMap(row));
    } catch (e) {
      return OfficeLocationError(_friendlyMessage(e));
    }
  }

  Future<OfficeLocationResult> update({
    required String id,
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) async {
    if (radiusMeters < 100 || radiusMeters > 2000) {
      return const OfficeLocationError('Radius must be between 100 and 2000 meters.');
    }
    try {
      final row = await SupabaseService.client
          .from('office_locations')
          .update({
            'name': name.trim(),
            'latitude': latitude,
            'longitude': longitude,
            'radius_meters': radiusMeters,
          })
          .eq('id', id)
          .select()
          .single();
      return OfficeLocationSuccess(OfficeLocation.fromMap(row));
    } catch (e) {
      return OfficeLocationError(_friendlyMessage(e));
    }
  }

  /// Soft-deactivate rather than delete — preserves the historical link
  /// from past attendance_records.office_id, and clock-event only looks
  /// at is_active = true offices when finding the nearest match.
  Future<OfficeLocationResult> setActive({required String id, required bool isActive}) async {
    try {
      final row = await SupabaseService.client
          .from('office_locations')
          .update({'is_active': isActive})
          .eq('id', id)
          .select()
          .single();
      return OfficeLocationSuccess(OfficeLocation.fromMap(row));
    } catch (e) {
      return OfficeLocationError(_friendlyMessage(e));
    }
  }

  String _friendlyMessage(Object e) {
    final msg = e.toString();
    if (msg.contains('row-level security')) {
      return 'You do not have permission to manage office locations.';
    }
    if (msg.contains('radius_meters_check')) {
      return 'Radius must be between 100 and 2000 meters.';
    }
    return msg;
  }
}
