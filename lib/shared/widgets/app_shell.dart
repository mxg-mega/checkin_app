// lib/shared/widgets/app_shell.dart
//
// Wraps employee and admin screens with a consistent app bar action
// (logout) and a simple drawer for navigating between the screens
// available to that role. Each screen can still use its own Scaffold/
// AppBar for the main content — this shell is intentionally lightweight,
// added via a wrapping widget rather than forcing every screen through
// go_router's ShellRoute, so it's easy to opt in/out per screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/repository/auth_repository.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(currentUserRoleProvider);

    return Drawer(
      child: SafeArea(
        child: roleAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('Failed to load menu')),
          data: (role) {
            final isAdmin = role == AppUserRole.admin || role == AppUserRole.superAdmin;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      isAdmin ? 'Admin' : 'Employee',
                      style: const TextStyle(color: Colors.white, fontSize: 20),
                    ),
                  ),
                ),
                if (!isAdmin) ...[
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Clock In / Out'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.clock);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('My Attendance'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.myAttendance);
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.dashboard_outlined),
                    title: const Text('Dashboard'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.adminDashboard);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_calendar_outlined),
                    title: const Text('Waive / Backfill Hours'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.adminWaiveBackfill);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Reports'),
                    onTap: () {
                      Navigator.pop(context);
                      context.go(AppRoutes.adminReports);
                    },
                  ),
                ],
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(context);
                    final repository = ref.read(authRepositoryProvider);
                    await repository.signOut();
                    // go_router's redirect callback picks up the auth state
                    // change automatically and sends the user to /login.
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
