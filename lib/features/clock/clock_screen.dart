// lib/features/clock/clock_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'clock_providers.dart';
import 'clock_repository.dart';
import '../../shared/widgets/app_shell.dart';

class ClockScreen extends ConsumerWidget {
  const ClockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialState = ref.watch(initialClockStateProvider);
    final clockState = ref.watch(currentClockStateProvider);
    final inProgress = ref.watch(clockInProgressProvider);

    // Seed currentClockStateProvider from the startup fetch, once, the
    // first time it resolves. After that, local updates (post clock-action)
    // take over, so we don't re-fetch on every rebuild.
    ref.listen(initialClockStateProvider, (previous, next) {
      next.whenData((result) {
        if (clockState != ClockState.unknown) return;
        switch (result) {
          case LastClockStateLoaded(:final status):
            ref.read(currentClockStateProvider.notifier).state =
                status == LastClockStatus.clockedIn ? ClockState.clockedIn : ClockState.clockedOut;
          case LastClockStateError():
            break; // leave as unknown; UI below handles this gracefully
        }
      });
    });

    // Show a loading spinner only while we have no local state yet AND
    // the startup fetch is still in flight — avoids flashing a wrong guess.
    if (clockState == ClockState.unknown && initialState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isClockedIn = clockState == ClockState.clockedIn;

    final danglingWarning = initialState.maybeWhen(
      data: (result) => switch (result) {
        LastClockStateLoaded(isDanglingOvernight: true, :final lastEventAt) =>
          'You clocked in ${lastEventAt != null ? DateFormat('MMM d, h:mm a').format(lastEventAt) : 'a while ago'} '
              'and never clocked out. If this was a mistake, contact your admin to correct it.',
        _ => null,
      },
      orElse: () => null,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Check In')),
      drawer: const AppDrawer(),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (danglingWarning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          danglingWarning,
                          style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Icon(
                isClockedIn ? Icons.timer : Icons.timer_off_outlined,
                size: 72,
                color: isClockedIn ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                isClockedIn ? 'You are clocked in' : 'You are clocked out',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: inProgress ? null : () => _handleClock(context, ref, isClockedIn),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isClockedIn ? Colors.redAccent : Colors.green,
                  ),
                  child: inProgress
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isClockedIn ? 'Clock Out' : 'Clock In',
                          style: const TextStyle(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You must be within range of the office to clock in or out.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleClock(BuildContext context, WidgetRef ref, bool isClockedIn) async {
    final progressNotifier = ref.read(clockInProgressProvider.notifier);
    progressNotifier.state = true;

    final repository = ref.read(clockRepositoryProvider);
    final type = isClockedIn ? ClockEventType.clockOut : ClockEventType.clockIn;
    final result = await repository.performClock(type);

    progressNotifier.state = false;
    if (!context.mounted) return;

    switch (result) {
      case ClockSuccess(:final distanceMeters):
        ref.read(currentClockStateProvider.notifier).state =
            isClockedIn ? ClockState.clockedOut : ClockState.clockedIn;
        _showSnack(
          context,
          '${isClockedIn ? "Clocked out" : "Clocked in"} successfully '
          '(${distanceMeters.round()}m from office)',
          isError: false,
        );

      case ClockOutsideGeofence(:final message):
        _showSnack(context, message, isError: true);

      case ClockInvalidState(:final message):
        _showSnack(context, message, isError: true);

      case ClockLocationUnavailable(:final message):
        _showSnack(context, message, isError: true);

      case ClockError(:final message):
        _showSnack(context, message, isError: true);
    }
  }

  void _showSnack(BuildContext context, String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
