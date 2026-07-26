// lib/core/router/app_router.dart
//
// Central routing config. Redirect logic:
//   - Not signed in -> /login
//   - Signed in + role still loading -> splash screen (avoid flashing wrong UI)
//   - Signed in + employee -> /clock (employee home)
//   - Signed in + admin/super_admin -> /admin (admin dashboard)
//
// Employees never see /admin/* routes even if they navigate there directly —
// the redirect callback re-checks role on every navigation, and RLS is the
// actual security backstop regardless of what the client-side router allows.

import 'package:checkin_app/features/admin/admin_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api/supabase_client.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/repository/auth_repository.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/clock/clock_screen.dart';
import '../../features/attendance/attendance_history_screen.dart';
import '../../features/admin/screens/waive_backfill_screen.dart';
import '../../features/admin/reports/reports_screen.dart';
import '../../features/admin/office_locations/office_locations_screen.dart';

class AppRoutes {
  static const login = '/login';
  static const clock = '/clock';
  static const myAttendance = '/my-attendance';
  static const adminDashboard = '/admin';
  static const adminWaiveBackfill = '/admin/waive-backfill';
  static const adminReports = '/admin/reports';
  static const adminOfficeLocations = '/admin/office-locations';
  static const splash = '/splash';
}

/// Rebuild the router's redirect whenever auth state or role changes.
final _routerRefreshProvider = Provider<GoRouterRefreshStream>((ref) {
  return GoRouterRefreshStream(ref);
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
    ref.listen(currentUserRoleProvider, (_, __) => notifyListeners());
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refreshStream = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final isSignedIn = SupabaseService.isAuthenticated;
      final goingToLogin = state.matchedLocation == AppRoutes.login;

      if (!isSignedIn) {
        return goingToLogin ? null : AppRoutes.login;
      }

      // Signed in: resolve role via the provider's current state.
      final roleAsync = ref.read(currentUserRoleProvider);

      return roleAsync.when(
        loading: () => AppRoutes.splash,
        error: (_, __) =>
            AppRoutes.login, // role lookup failed — treat as unauthenticated
        data: (role) {
          if (role == null) return AppRoutes.login;

          final isAdmin =
              role == AppUserRole.admin || role == AppUserRole.superAdmin;
          final onAdminRoute = state.matchedLocation.startsWith('/admin');
          final onSplashOrLogin =
              state.matchedLocation == AppRoutes.splash || goingToLogin;

          // Employees must never land on admin routes — they have no
          // dashboard access. Admins, however, are also employees who
          // clock in/out themselves, so they're free to use /clock and
          // /my-attendance too; only non-admins are restricted here.
          if (!isAdmin && onAdminRoute) return AppRoutes.clock;

          // Redirect away from splash/login once we know where they belong.
          // Admins land on the dashboard by default after signing in, but
          // can navigate to /clock afterward via the drawer.
          if (onSplashOrLogin) {
            return isAdmin ? AppRoutes.adminDashboard : AppRoutes.clock;
          }

          return null; // already on a valid route for this role
        },
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),

      // --- Employee routes ---
      GoRoute(
        path: AppRoutes.clock,
        builder: (context, state) => const ClockScreen(),
      ),
      GoRoute(
        path: AppRoutes.myAttendance,
        builder: (context, state) => const AttendanceHistoryScreen(),
      ),

      // --- Admin routes ---
      GoRoute(
        path: AppRoutes.adminDashboard,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminWaiveBackfill,
        builder: (context, state) => const WaiveBackfillScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminReports,
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminOfficeLocations,
        builder: (context, state) => const OfficeLocationsScreen(),
      ),
    ],
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Icon(Icons.fingerprint, size: 64),
      ),
    );
  }
}
