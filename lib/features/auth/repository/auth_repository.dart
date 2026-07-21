// lib/features/auth/repository/auth_repository.dart
//
// Wraps Supabase Auth for sign-in/sign-up/sign-out, plus a helper to
// fetch the current user's role from `profiles` (needed for role-based
// routing — admins land on the dashboard, employees land on the clock screen).
//
// Employee accounts are expected to be created by an admin (via Supabase
// dashboard or an future "invite employee" admin flow), so this repository's
// signUp() is included for completeness but your primary flow is likely
// admin-provisioned credentials + employee sign-in only.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/api/supabase_client.dart';

sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  final User user;
  const AuthSuccess(this.user);
}

class AuthFailure extends AuthResult {
  final String message;
  const AuthFailure(this.message);
}

enum AppUserRole { employee, admin, superAdmin }

class AuthRepository {
  Future<AuthResult> signIn({required String email, required String password}) async {
    try {
      final response = await SupabaseService.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) {
        return const AuthFailure('Sign in failed. Please check your credentials.');
      }
      return AuthSuccess(user);
    } on AuthException catch (e) {
      return AuthFailure(_friendlyAuthError(e));
    } catch (e) {
      return AuthFailure('Unexpected error: $e');
    }
  }

  /// For admin-driven employee provisioning flows later. Not exposed in the
  /// current UI (no public "create account" screen) — admins create
  /// employee credentials via Supabase directly or a future admin screen.
  Future<AuthResult> signUp({required String email, required String password, required String fullName}) async {
    try {
      final response = await SupabaseService.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
      final user = response.user;
      if (user == null) {
        return const AuthFailure('Sign up failed. Please try again.');
      }
      return AuthSuccess(user);
    } on AuthException catch (e) {
      return AuthFailure(_friendlyAuthError(e));
    } catch (e) {
      return AuthFailure('Unexpected error: $e');
    }
  }

  Future<void> signOut() => SupabaseService.client.auth.signOut();

  Future<AuthResult> requestPasswordReset({required String email}) async {
    try {
      await SupabaseService.client.auth.resetPasswordForEmail(email.trim());
      return AuthSuccess(SupabaseService.client.auth.currentUser ?? User(
        id: '', appMetadata: const {}, userMetadata: const {}, aud: '', createdAt: '',
      ));
    } on AuthException catch (e) {
      return AuthFailure(_friendlyAuthError(e));
    } catch (e) {
      return AuthFailure('Unexpected error: $e');
    }
  }

  /// Fetches the signed-in user's role from `profiles`, needed to decide
  /// whether to route them to the employee clock screen or admin dashboard.
  Future<AppUserRole?> fetchCurrentUserRole() async {
    final userId = SupabaseService.currentUser?.id;
    if (userId == null) return null;

    final row = await SupabaseService.client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    if (row == null) return null;

    return switch (row['role'] as String) {
      'admin' => AppUserRole.admin,
      'super_admin' => AppUserRole.superAdmin,
      _ => AppUserRole.employee,
    };
  }

  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please confirm your email before signing in.';
    }
    if (msg.contains('user already registered')) {
      return 'An account with this email already exists.';
    }
    return e.message;
  }
}
