import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../shared/widgets/app_shell.dart';
import '../attendance/attendance_history_repository.dart';
import 'employee_dashboard_repository.dart';
import 'package:intl/intl.dart';

final employeeDashboardRepositoryProvider = Provider<EmployeeDashboardRepository>((ref) {
  return EmployeeDashboardRepository();
});

final employeeNetMinutesProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(employeeDashboardRepositoryProvider);
  final now = DateTime.now();
  // Using the current month as the period for this dashboard
  final startDate = DateTime(now.year, now.month, 1);
  final endDate = DateTime(now.year, now.month + 1, 0);
  return repo.fetchMyNetMinutesThisPeriod(startDate, endDate);
});

final dashboardRecentAttendanceProvider = FutureProvider.autoDispose<List<AttendanceRecordView>>((ref) async {
  final repo = AttendanceHistoryRepository();
  return repo.fetchMyRecent(limit: 5); // Show only the latest 5
});

class EmployeeDashboardScreen extends ConsumerWidget {
  const EmployeeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netMinutesAsync = ref.watch(employeeNetMinutesProvider);
    final recentAttendanceAsync = ref.watch(dashboardRecentAttendanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Dashboard'),
      ),
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(employeeNetMinutesProvider);
          ref.invalidate(dashboardRecentAttendanceProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildOwedOvertimeCard(context, netMinutesAsync),
            const SizedBox(height: 24),
            _buildActionButtons(context),
            const SizedBox(height: 24),
            Text('Recent Attendance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _buildRecentAttendanceList(context, recentAttendanceAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildOwedOvertimeCard(BuildContext context, AsyncValue<int> netMinutesAsync) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'Current Period Standing',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            netMinutesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => const Center(child: Text('Failed to load data')),
              data: (netMinutes) {
                final isNeutral = netMinutes == 0;
                final isOvertime = netMinutes > 0;
                final color = isNeutral ? Colors.grey : (isOvertime ? Colors.green : Colors.red);
                final hours = (netMinutes.abs() / 60.0).toStringAsFixed(1);
                
                String label = isNeutral ? 'Balanced' : (isOvertime ? 'Overtime' : 'Owed');

                return Column(
                  children: [
                    Icon(
                      isNeutral ? Icons.check_circle : (isOvertime ? Icons.trending_up : Icons.trending_down),
                      size: 48,
                      color: color,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isNeutral ? '0.0h' : '$hours h',
                      style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color),
                    ),
                    Text(
                      label,
                      style: TextStyle(fontSize: 18, color: color),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => context.push(AppRoutes.clock),
            icon: const Icon(Icons.timer),
            label: const Text('Clock In / Out'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => context.push(AppRoutes.myAttendance),
            icon: const Icon(Icons.history),
            label: const Text('Full History'),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAttendanceList(BuildContext context, AsyncValue<List<AttendanceRecordView>> recentAttendanceAsync) {
    return recentAttendanceAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Failed to load: $err')),
      data: (records) {
        if (records.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No recent attendance records.'),
          );
        }
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = records[index];
              final isClockIn = record.type == 'clock_in';
              
              return ListTile(
                leading: Icon(
                  isClockIn ? Icons.login : Icons.logout,
                  color: isClockIn ? Colors.green : Colors.redAccent,
                ),
                title: Text(isClockIn ? 'Clocked In' : 'Clocked Out'),
                subtitle: Text(DateFormat('EEE, MMM d · h:mm a').format(record.recordedAt)),
              );
            },
          ),
        );
      },
    );
  }
}
