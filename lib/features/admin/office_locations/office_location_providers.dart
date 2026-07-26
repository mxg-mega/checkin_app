// lib/features/admin/office_locations/office_location_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'office_location_repository.dart';

final officeLocationRepositoryProvider = Provider<OfficeLocationRepository>((ref) {
  return OfficeLocationRepository();
});

final officeLocationsProvider = FutureProvider.autoDispose<List<OfficeLocation>>((ref) async {
  final repository = ref.watch(officeLocationRepositoryProvider);
  return repository.fetchAll();
});

final officeLocationActionInProgressProvider = StateProvider.autoDispose<bool>((ref) => false);
