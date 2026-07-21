// lib/features/admin/screens/admin_dashboard_screen.dart

import 'package:checkin_app/features/admin/screens/waive_backfill_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'admin_providers.dart';
import 'repository/team_overview_repository.dart';
import '../../../shared/widgets/app_shell.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final danglingAsync = ref.watch(danglingShiftsProvider);
    final standingAsync = ref.watch(teamHoursStandingProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_calendar),
            tooltip: 'Waive / Backfill Hours',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WaiveBackfillScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(danglingShiftsProvider);
          ref.invalidate(teamHoursStandingProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(
              title: 'Dangling Shifts',
              subtitle: 'Clock-ins with no matching clock-out',
            ),
            const SizedBox(height: 8),
            danglingAsync.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
              error: (err, _) => Text('Failed to load: $err'),
              data: (shifts) {
                if (shifts.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, color: Colors.green),
                          SizedBox(width: 12),
                          Text('No dangling shifts. Everyone is accounted for.'),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: shifts.map((shift) => _DanglingShiftCard(shift: shift)).toList(),
                );
              },
            ),

            const SizedBox(height: 32),
            _SectionHeader(
              title: 'Team Hours Standing',
              subtitle: 'This period · overtime owed vs hours to repay',
            ),
            const SizedBox(height: 8),
            standingAsync.when(
              loading: () => const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
              error: (err, _) => Text('Failed to load: $err'),
              data: (standings) {
                if (standings.isEmpty) {
                  return const Text('No attendance data for this period yet.');
                }
                return Column(
                  children: standings.map((s) => _HoursStandingTile(standing: s)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _DanglingShiftCard extends StatelessWidget {
  final DanglingShift shift;

  const _DanglingShiftCard({required this.shift});

  @override
  Widget build(BuildContext context) {
    final isSevere = shift.isLikelyForgotten;
    return Card(
      color: isSevere ? Colors.red.shade50 : Colors.orange.shade50,
      child: ListTile(
        leading: Icon(
          isSevere ? Icons.error_outline : Icons.warning_amber_rounded,
          color: isSevere ? Colors.red.shade700 : Colors.orange.shade700,
        ),
        title: Text(shift.fullName),
        subtitle: Text(
          'Clocked in ${DateFormat('MMM d, h:mm a').format(shift.clockInTime)} '
          '· open ${shift.hoursOpen.toStringAsFixed(1)}h',
        ),
        trailing: TextButton(
          onPressed: () {
            // Navigate to WaiveBackfillScreen pre-filled for this employee,
            // or a dedicated "add missing clock-out" flow — wire up as needed.
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WaiveBackfillScreen()),
            );
          },
          child: const Text('Fix'),
        ),
      ),
    );
  }
}

class _HoursStandingTile extends StatelessWidget {
  final EmployeeHoursStanding standing;

  const _HoursStandingTile({required this.standing});

  @override
  Widget build(BuildContext context) {
    final isOvertime = standing.netMinutesThisPeriod > 0;
    final isNeutral = standing.netMinutesThisPeriod == 0;
    final color = isNeutral ? Colors.grey : (isOvertime ? Colors.green : Colors.red);
    final label = isNeutral
        ? 'On track'
        : isOvertime
            ? '+${standing.netHours.toStringAsFixed(1)}h overtime'
            : '${standing.netHours.toStringAsFixed(1)}h to repay';

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.15),
        child: Icon(
          isNeutral ? Icons.remove : (isOvertime ? Icons.trending_up : Icons.trending_down),
          color: color,
        ),
      ),
      title: Text(standing.fullName),
      trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
