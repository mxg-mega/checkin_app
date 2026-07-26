// lib/main.dart

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/supabase_client.dart';
import 'core/router/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env from the project root for local dev. A missing file is fine —
  // CI / prod passes values via --dart-define=SUPABASE_URL=... etc.
  await dotenv.load(fileName: '.env', isOptional: true);

  await SupabaseService.initialize(
    supabaseUrl: _supabaseUrl(),
    supabaseAnonKey: _supabaseAnonKey(),
  );

  runApp(const ProviderScope(child: CheckInApp()));
}

/// Prefers a --dart-define value (so CI / prod can override .env) and falls
/// back to the .env file. Throws if neither is set so misconfiguration fails
/// loudly at startup instead of mid-request.
String _supabaseUrl() {
  const fromDefine = String.fromEnvironment('SUPABASE_URL');
  if (fromDefine.isNotEmpty) return fromDefine;
  final fromEnv = dotenv.env['SUPABASE_URL'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  throw StateError(
    'SUPABASE_URL is not set. Provide it via --dart-define=SUPABASE_URL=... '
    'or in a .env file in the project root.',
  );
}

String _supabaseAnonKey() {
  const fromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  final fromEnv = dotenv.env['SUPABASE_ANON_KEY'];
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  throw StateError(
    'SUPABASE_ANON_KEY is not set. Provide it via '
    '--dart-define=SUPABASE_ANON_KEY=... or in a .env file.',
  );
}

class CheckInApp extends ConsumerWidget {
  const CheckInApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Check In',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
        ),
      ),
      routerConfig: router,
    );
  }
}
