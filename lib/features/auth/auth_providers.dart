// lib/features/auth/auth_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/api/supabase_client.dart';
import 'repository/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository());

/// Streams Supabase auth state changes (sign-in, sign-out, token refresh)
/// so the router can react immediately without polling.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return SupabaseService.client.auth.onAuthStateChange;
});

/// Resolves to the current user's role, re-fetched whenever auth state
/// changes. Returns null if signed out or profile lookup fails.
final currentUserRoleProvider = FutureProvider.autoDispose<AppUserRole?>((ref) async {
  // Re-run whenever auth state changes.
  ref.watch(authStateChangesProvider);
  final repository = ref.watch(authRepositoryProvider);
  if (!SupabaseService.isAuthenticated) return null;
  return repository.fetchCurrentUserRole();
});

final authInProgressProvider = StateProvider.autoDispose<bool>((ref) => false);
