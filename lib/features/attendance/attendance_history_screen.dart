// lib/features/attendance/attendance_history_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'attendance_history_repository.dart';

final attendanceHistoryRepositoryProvider =
    Provider<AttendanceHistoryRepository>((ref) => AttendanceHistoryRepository());

final myAttendanceHistoryProvider =
    FutureProvider.autoDispose<List<AttendanceRecordView>>((ref) async {
  final repository = ref.watch(attendanceHistoryRepositoryProvider);
  return repository.fetchMyRecent();
});

class AttendanceHistoryScreen extends ConsumerWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(myAttendanceHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Attendance')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myAttendanceHistoryProvider),
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Failed to load: $err')),
          data: (records) {
            if (records.isEmpty) {
              return const Center(child: Text('No attendance records yet.'));
            }
            return ListView.builder(
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                final isClockIn = record.type == 'clock_in';
                final isManual = record.source == 'admin_manual';

                return ListTile(
                  leading: Icon(
                    isClockIn ? Icons.login : Icons.logout,
                    color: isClockIn ? Colors.green : Colors.redAccent,
                  ),
                  title: Text(isClockIn ? 'Clocked In' : 'Clocked Out'),
                  subtitle: Text(DateFormat('EEE, MMM d · h:mm a').format(record.recordedAt)),
                  trailing: isManual
                      ? Chip(
                          label: const Text('Admin entry', style: TextStyle(fontSize: 11)),
                          backgroundColor: Colors.blue.shade50,
                          visualDensity: VisualDensity.compact,
                        )
                      : record.distanceFromOfficeMeters != null
                          ? Text('${record.distanceFromOfficeMeters!.round()}m',
                              style: Theme.of(context).textTheme.bodySmall)
                          : null,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
