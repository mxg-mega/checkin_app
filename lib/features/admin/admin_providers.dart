// lib/features/admin/admin_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository/admin_adjustments_repository.dart';
import 'repository/employee_directory_repository.dart';
import 'repository/team_overview_repository.dart';

final adminAdjustmentsRepositoryProvider = Provider<AdminAdjustmentsRepository>((ref) {
  return AdminAdjustmentsRepository();
});

final employeeDirectoryRepositoryProvider = Provider<EmployeeDirectoryRepository>((ref) {
  return EmployeeDirectoryRepository();
});

final teamOverviewRepositoryProvider = Provider<TeamOverviewRepository>((ref) {
  return TeamOverviewRepository();
});

/// List of active employees, for admin pickers. autoDispose + refresh
/// pattern: call ref.invalidate(activeEmployeesProvider) after any
/// profile change to force a re-fetch.
final activeEmployeesProvider = FutureProvider.autoDispose<List<EmployeeSummary>>((ref) async {
  final repository = ref.watch(employeeDirectoryRepositoryProvider);
  return repository.fetchActiveEmployees();
});

/// True while a waive/backfill/void submission is in flight.
final adminActionInProgressProvider = StateProvider.autoDispose<bool>((ref) => false);

/// Dangling (likely-forgotten) shifts across the whole team. autoDispose
/// so it re-fetches fresh each time the admin opens the dashboard.
final danglingShiftsProvider = FutureProvider.autoDispose<List<DanglingShift>>((ref) async {
  final repository = ref.watch(teamOverviewRepositoryProvider);
  return repository.fetchDanglingShifts();
});

/// Current pay-period date range used by the team overview and reports.
/// Defaults to the current calendar month; swap for a pay_periods table
/// lookup once that's wired into the UI.
final currentPeriodRangeProvider = Provider<(DateTime, DateTime)>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, 1);
  final end = DateTime(now.year, now.month + 1, 0);
  return (start, end);
});

final teamHoursStandingProvider = FutureProvider.autoDispose<List<EmployeeHoursStanding>>((ref) async {
  final repository = ref.watch(teamOverviewRepositoryProvider);
  final (start, end) = ref.watch(currentPeriodRangeProvider);
  return repository.fetchHoursStanding(startDate: start, endDate: end);
});
