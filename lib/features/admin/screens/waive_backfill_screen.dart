// lib/features/admin/screens/waive_backfill_screen.dart
//
// Single screen covering both admin override flows:
//   - Waive hours: correct a shortfall (positive) or an over-credit (negative)
//   - Backfill hours: credit hours from a period with no attendance record
//
// Both funnel into hours_adjustments; the distinction is adjustment_type,
// selected via the toggle at the top.

import 'package:checkin_app/shared/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../admin_providers.dart';
import '../repository/admin_adjustments_repository.dart';
import '../repository/employee_directory_repository.dart';

enum _Mode { waive, backfill }

class WaiveBackfillScreen extends ConsumerStatefulWidget {
  const WaiveBackfillScreen({super.key});

  @override
  ConsumerState<WaiveBackfillScreen> createState() => _WaiveBackfillScreenState();
}

class _WaiveBackfillScreenState extends ConsumerState<WaiveBackfillScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hoursController = TextEditingController();
  final _reasonController = TextEditingController();

  _Mode _mode = _Mode.waive;
  EmployeeSummary? _selectedEmployee;
  DateTime _appliesToDate = DateTime.now();

  @override
  void dispose() {
    _hoursController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(activeEmployeesProvider);
    final inProgress = ref.watch(adminActionInProgressProvider);

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(title: const Text('Waive / Backfill Hours')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(value: _Mode.waive, label: Text('Waive Hours'), icon: Icon(Icons.remove_circle_outline)),
                  ButtonSegment(value: _Mode.backfill, label: Text('Backfill Hours'), icon: Icon(Icons.add_circle_outline)),
                ],
                selected: {_mode},
                onSelectionChanged: (selected) => setState(() => _mode = selected.first),
              ),
              const SizedBox(height: 8),
              Text(
                _mode == _Mode.waive
                    ? 'Adjust hours for a shortfall (e.g. approved early leave). '
                      'Use a positive number to credit the employee, negative to debit.'
                    : 'Credit hours for a period with no attendance record at all '
                      '(e.g. system outage, pre-launch backpay). Must be positive.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),

              employeesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Text('Failed to load employees: $err'),
                data: (employees) => DropdownButtonFormField<EmployeeSummary>(
                  initialValue: _selectedEmployee,
                  decoration: const InputDecoration(labelText: 'Employee', border: OutlineInputBorder()),
                  items: employees
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.fullName)))
                      .toList(),
                  onChanged: (value) => setState(() => _selectedEmployee = value),
                  validator: (value) => value == null ? 'Select an employee' : null,
                ),
              ),
              const SizedBox(height: 16),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Applies to date'),
                subtitle: Text('${_appliesToDate.year}-${_appliesToDate.month.toString().padLeft(2, '0')}-${_appliesToDate.day.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const Divider(),
              const SizedBox(height: 8),

              TextFormField(
                controller: _hoursController,
                decoration: InputDecoration(
                  labelText: _mode == _Mode.waive ? 'Hours (+/-)' : 'Hours to backfill',
                  border: const OutlineInputBorder(),
                  helperText: _mode == _Mode.waive
                      ? 'Positive credits the employee, negative debits'
                      : 'Must be a positive number',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Enter hours';
                  final parsed = double.tryParse(value.trim());
                  if (parsed == null) return 'Enter a valid number';
                  if (_mode == _Mode.backfill && parsed <= 0) return 'Backfill hours must be positive';
                  if (parsed == 0) return 'Hours cannot be zero';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason (required)',
                  border: OutlineInputBorder(),
                  helperText: 'This is stored permanently in the audit trail',
                ),
                maxLines: 3,
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'A reason is required' : null,
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: inProgress ? null : _submit,
                  child: inProgress
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_mode == _Mode.waive ? 'Submit Waiver' : 'Submit Backfill'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _appliesToDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _appliesToDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final progressNotifier = ref.read(adminActionInProgressProvider.notifier);
    progressNotifier.state = true;

    final repository = ref.read(adminAdjustmentsRepositoryProvider);
    final hours = double.parse(_hoursController.text.trim());

    final result = _mode == _Mode.waive
        ? await repository.waiveHours(
            userId: _selectedEmployee!.id,
            hours: hours,
            appliesToDate: _appliesToDate,
            reason: _reasonController.text,
          )
        : await repository.backfillHours(
            userId: _selectedEmployee!.id,
            hours: hours,
            appliesToDate: _appliesToDate,
            reason: _reasonController.text,
          );

    progressNotifier.state = false;
    if (!mounted) return;

    switch (result) {
      case AdminActionSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mode == _Mode.waive ? 'Hours waived successfully.' : 'Hours backfilled successfully.'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        _hoursController.clear();
        _reasonController.clear();
        setState(() => _selectedEmployee = null);

      case AdminActionError(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
        );
    }
  }
}
