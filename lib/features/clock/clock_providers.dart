// lib/features/clock/clock_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clock_repository.dart';

final clockRepositoryProvider = Provider<ClockRepository>((ref) {
  return ClockRepository();
});

/// Tracks whether the user is currently clocked in, so the UI knows
/// whether to show "Clock In" or "Clock Out". This should be refreshed
/// from the latest attendance_records row on app start / after each clock event.
enum ClockState { clockedIn, clockedOut, unknown }

final currentClockStateProvider =
    StateProvider<ClockState>((ref) => ClockState.unknown);

/// True while a clock attempt (GPS fetch + Edge Function call) is in progress.
final clockInProgressProvider = StateProvider<bool>((ref) => false);

/// Represents the last-known state from the server at startup.
enum LastClockStatus { clockedIn, clockedOut }

sealed class LastClockState {
  const LastClockState();
}

class LastClockStateLoaded extends LastClockState {
  final LastClockStatus status;
  final bool isDanglingOvernight;
  final DateTime? lastEventAt;

  const LastClockStateLoaded({
    required this.status,
    this.isDanglingOvernight = false,
    this.lastEventAt,
  });
}

class LastClockStateError extends LastClockState {
  const LastClockStateError();
}

/// Initial provider that fetches the last-known clock state on startup.
/// For now this returns a default (clockedOut) value so the UI compiles
/// and runs; replace with a real fetch when available.
final initialClockStateProvider = FutureProvider<LastClockState>((ref) async {
  // TODO: call the backend / repository to determine the real last state.
  return const LastClockStateLoaded(
      status: LastClockStatus.clockedOut,
      isDanglingOvernight: false,
      lastEventAt: null);
});
