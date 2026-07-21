// lib/features/admin/repository/employee_directory_repository.dart
//
// Read-only lookup of employees for admin screens (picking who to
// waive/backfill hours for, viewing team overview, etc).

import '../../../../../../core/api/supabase_client.dart';

class EmployeeSummary {
  final String id;
  final String fullName;
  final String? employeeCode;
  final String role;
  final bool isActive;

  const EmployeeSummary({
    required this.id,
    required this.fullName,
    required this.employeeCode,
    required this.role,
    required this.isActive,
  });

  factory EmployeeSummary.fromMap(Map<String, dynamic> map) => EmployeeSummary(
        id: map['id'] as String,
        fullName: map['full_name'] as String,
        employeeCode: map['employee_code'] as String?,
        role: map['role'] as String,
        isActive: map['is_active'] as bool,
      );
}

class EmployeeDirectoryRepository {
  Future<List<EmployeeSummary>> fetchActiveEmployees() async {
    final rows = await SupabaseService.client
        .from('profiles')
        .select('id, full_name, employee_code, role, is_active')
        .eq('is_active', true)
        .order('full_name', ascending: true);

    return (rows as List)
        .map((row) => EmployeeSummary.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
