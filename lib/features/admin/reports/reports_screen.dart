// lib/features/admin/reports/reports_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../admin_providers.dart';
import 'report_data_repository.dart';
import 'report_exporter.dart';

final reportDataRepositoryProvider = Provider<ReportDataRepository>((ref) => ReportDataRepository());
final reportExporterProvider = Provider<ReportExporter>((ref) => ReportExporter());

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  String? _selectedEmployeeId; // null = all employees
  bool _generating = false;
  List<ReportRow>? _previewRows;

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(activeEmployeesProvider);
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Start date'),
                    subtitle: Text(dateFormat.format(_startDate)),
                    onTap: () => _pickDate(isStart: true),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('End date'),
                    subtitle: Text(dateFormat.format(_endDate)),
                    onTap: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            const Divider(),
            employeesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (err, _) => Text('Failed to load employees: $err'),
              data: (employees) => DropdownButtonFormField<String?>(
                initialValue: _selectedEmployeeId,
                decoration: const InputDecoration(labelText: 'Employee (leave blank for all)', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Employees')),
                  ...employees.map((e) => DropdownMenuItem(value: e.id, child: Text(e.fullName))),
                ],
                onChanged: (value) => setState(() => _selectedEmployeeId = value),
              ),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _generating ? null : _loadPreview,
                    icon: const Icon(Icons.preview),
                    label: const Text('Preview'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _generating ? null : () => _export(asPdf: false),
                    icon: const Icon(Icons.table_chart),
                    label: const Text('Export CSV'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _generating ? null : () => _export(asPdf: true),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Export PDF'),
              ),
            ),

            if (_generating) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],

            if (_previewRows != null) ...[
              const SizedBox(height: 24),
              Text('Preview (${_previewRows!.length} rows)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (_previewRows!.isEmpty)
                const Text('No data for this range.')
              else
                ..._previewRows!.take(20).map((row) => ListTile(
                      dense: true,
                      title: Text(row.fullName),
                      subtitle: Text(DateFormat('MMM d').format(row.workDate)),
                      trailing: Text(
                        row.netHours >= 0
                            ? '+${row.netHours.toStringAsFixed(1)}h'
                            : '${row.netHours.toStringAsFixed(1)}h',
                        style: TextStyle(
                          color: row.netHours >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )),
              if (_previewRows!.length > 20)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('...and ${_previewRows!.length - 20} more rows in the full export.'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 730)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<List<ReportRow>> _fetchRows() async {
    final repository = ref.read(reportDataRepositoryProvider);
    return repository.fetchSummaryReport(
      startDate: _startDate,
      endDate: _endDate,
      userId: _selectedEmployeeId,
    );
  }

  Future<void> _loadPreview() async {
    setState(() => _generating = true);
    try {
      final rows = await _fetchRows();
      if (!mounted) return;
      setState(() => _previewRows = rows);
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to load preview: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _export({required bool asPdf}) async {
    setState(() => _generating = true);
    try {
      final rows = await _fetchRows();
      if (rows.isEmpty) {
        if (!mounted) return;
        _showError('No data found for the selected range.');
        return;
      }

      final exporter = ref.read(reportExporterProvider);
      final prefix = 'attendance_report_${DateFormat('yyyyMMdd').format(_startDate)}'
          '_${DateFormat('yyyyMMdd').format(_endDate)}';

      if (asPdf) {
        await exporter.exportPdf(rows, filenamePrefix: prefix, startDate: _startDate, endDate: _endDate);
      } else {
        await exporter.exportCsv(rows, filenamePrefix: prefix);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${asPdf ? "PDF" : "CSV"} exported successfully.'), backgroundColor: Colors.green.shade700),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }
}
