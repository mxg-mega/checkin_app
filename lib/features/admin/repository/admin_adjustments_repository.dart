// lib/features/admin/repository/admin_adjustments_repository.dart
//
// Handles the two admin-only override flows:
//   1. Waive hours — credit/debit hours_adjustments for a date (e.g. "waive
//      2 hours short, doctor's note").
//   2. Backfill attendance — insert a missing clock_in/clock_out as an
//      admin_manual attendance_records row (e.g. employee forgot to clock out).
//
// Both write paths rely on RLS to enforce "only admins can do this" as the
// authoritative check — the Dart-side checks here are for fast UI feedback,
// not security.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../core/api/supabase_client.dart';

sealed class AdminActionResult {
  const AdminActionResult();
}

class AdminActionSuccess extends AdminActionResult {
  final Map<String, dynamic> record;
  const AdminActionSuccess(this.record);
}

class AdminActionError extends AdminActionResult {
  final String message;
  const AdminActionError(this.message);
}

class AdminAdjustmentsRepository {
  /// Waives or debits hours for a specific employee + date.
  /// [hours] should be positive to credit the employee (waive a shortfall)
  /// or negative to debit (e.g. correcting an earlier over-credit).
  Future<AdminActionResult> waiveHours({
    required String userId,
    required double hours,
    required DateTime appliesToDate,
    required String reason,
  }) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) {
      return const AdminActionError('No authenticated admin session.');
    }
    if (reason.trim().isEmpty) {
      return const AdminActionError('A reason is required to waive hours.');
    }

    try {
      final response = await SupabaseService.client
          .from('hours_adjustments')
          .insert({
            'user_id': userId,
            'adjustment_type': 'waive_hours',
            'hours': hours,
            'applies_to_date': _dateOnly(appliesToDate),
            'reason': reason.trim(),
            'created_by': adminId,
          })
          .select()
          .single();

      await _triggerRecompute(userId, appliesToDate);
      return AdminActionSuccess(response);
    } on PostgrestException catch (e) {
      return AdminActionError(_friendlyMessage(e));
    } catch (e) {
      return AdminActionError('Unexpected error: $e');
    }
  }

  /// Credits hours from a period with no attendance record at all
  /// (e.g. a system outage, or pre-app-launch backpay).
  Future<AdminActionResult> backfillHours({
    required String userId,
    required double hours,
    required DateTime appliesToDate,
    required String reason,
  }) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) {
      return const AdminActionError('No authenticated admin session.');
    }
    if (reason.trim().isEmpty) {
      return const AdminActionError('A reason is required to backfill hours.');
    }
    if (hours <= 0) {
      return const AdminActionError('Backfilled hours must be a positive number.');
    }

    try {
      final response = await SupabaseService.client
          .from('hours_adjustments')
          .insert({
            'user_id': userId,
            'adjustment_type': 'backfill_hours',
            'hours': hours,
            'applies_to_date': _dateOnly(appliesToDate),
            'reason': reason.trim(),
            'created_by': adminId,
          })
          .select()
          .single();

      await _triggerRecompute(userId, appliesToDate);
      return AdminActionSuccess(response);
    } on PostgrestException catch (e) {
      return AdminActionError(_friendlyMessage(e));
    } catch (e) {
      return AdminActionError('Unexpected error: $e');
    }
  }

  /// Inserts a missing clock_in or clock_out as an admin_manual record —
  /// used when an employee forgot to punch and the admin needs to correct
  /// the actual attendance ledger (not just the computed hours total).
  Future<AdminActionResult> backfillAttendanceRecord({
    required String userId,
    required String type, // 'clock_in' or 'clock_out'
    required DateTime recordedAt,
    required String reason,
    String? originalRecordId,
  }) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) {
      return const AdminActionError('No authenticated admin session.');
    }
    if (reason.trim().isEmpty) {
      return const AdminActionError('A reason is required for a manual attendance entry.');
    }
    if (type != 'clock_in' && type != 'clock_out') {
      return const AdminActionError('type must be clock_in or clock_out.');
    }

    try {
      final response = await SupabaseService.client
          .from('attendance_records')
          .insert({
            'user_id': userId,
            'type': type,
            'source': 'admin_manual',
            'recorded_at': recordedAt.toUtc().toIso8601String(),
            'created_by': adminId,
            'reason': reason.trim(),
            if (originalRecordId != null) 'original_record_id': originalRecordId,
          })
          .select()
          .single();

      await _triggerRecompute(userId, recordedAt);
      return AdminActionSuccess(response);
    } on PostgrestException catch (e) {
      return AdminActionError(_friendlyMessage(e));
    } catch (e) {
      return AdminActionError('Unexpected error: $e');
    }
  }

  /// Soft-voids a previous adjustment or manual record rather than deleting it,
  /// preserving the audit trail. Applies to either table via [table].
  Future<AdminActionResult> voidEntry({
    required String table, // 'hours_adjustments' or 'attendance_records'
    required String recordId,
    required String voidReason,
  }) async {
    final adminId = SupabaseService.currentUser?.id;
    if (adminId == null) {
      return const AdminActionError('No authenticated admin session.');
    }
    if (table != 'hours_adjustments' && table != 'attendance_records') {
      return const AdminActionError('Invalid table for void operation.');
    }

    try {
      final response = await SupabaseService.client
          .from(table)
          .update({
            'is_voided': true,
            'voided_by': adminId,
            'voided_at': DateTime.now().toUtc().toIso8601String(),
            'void_reason': voidReason.trim(),
          })
          .eq('id', recordId)
          .select()
          .single();

      return AdminActionSuccess(response);
    } on PostgrestException catch (e) {
      return AdminActionError(_friendlyMessage(e));
    } catch (e) {
      return AdminActionError('Unexpected error: $e');
    }
  }

  /// Fires the compute-daily-hours Edge Function for the affected user/date
  /// so the dashboard reflects the adjustment immediately rather than
  /// waiting for the next scheduled recompute.
  Future<void> _triggerRecompute(String userId, DateTime date) async {
    final dateStr = _dateOnly(date);
    try {
      await SupabaseService.client.functions.invoke(
        'compute-daily-hours',
        body: {'user_id': userId, 'start_date': dateStr, 'end_date': dateStr},
      );
    } catch (_) {
      // Non-fatal: the nightly scheduled job will still catch this up.
      // Swallow here so the admin's primary action isn't reported as failed
      // just because the recompute trigger had a hiccup.
    }
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _friendlyMessage(PostgrestException e) {
    if (e.message.contains('row-level security')) {
      return 'You do not have permission to perform this action.';
    }
    if (e.message.contains('admin_manual_requires_reason')) {
      return 'A reason is required for manual entries.';
    }
    return e.message;
  }
}
