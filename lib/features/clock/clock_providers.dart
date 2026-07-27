// lib/features/clock/clock_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clock_repository.dart';

final clockRepositoryProvider = Provider<ClockRepository>((ref) {
  return ClockRepository();
});

/// Tracks whether the user is currently clocked in, so the UI knows
/// whether to show "Clock In" or "Clock Out". Seeded from
/// [initialClockStateProvider] on load, then updated locally after
/// each successful clock action (no need to re-fetch from the server).
enum ClockState { clockedIn, clockedOut, unknown }

final currentClockStateProvider = StateProvider<ClockState>((ref) => ClockState.unknown);

/// True while a clock attempt (GPS fetch + Edge Function call) is in progress.
final clockInProgressProvider = StateProvider<bool>((ref) => false);

/// Fetches the user's last attendance record once on startup/resume, via
/// ClockRepository.fetchLastClockState() — a real query against
/// attendance_records, not a stub. The screen listens to this to seed
/// [currentClockStateProvider] and to warn the user if they have a
/// dangling (likely-forgotten) overnight shift.
///
/// autoDispose means this re-fetches fresh each time the screen mounts
/// (e.g. app resumed from background), which is what fixes the "clocked
/// in state not retained after leaving and returning" issue — the
/// previous stub always returned clockedOut regardless of real state.
final initialClockStateProvider = FutureProvider.autoDispose<LastClockStateResult>((ref) async {
  final repository = ref.watch(clockRepositoryProvider);
  return repository.fetchLastClockState();
});