// lib/core/api/supabase_client.dart
//
// Central place to initialize and access the Supabase client.
// Call SupabaseService.initialize() once in main() before runApp().

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static late final SupabaseClient client;

  static Future<void> initialize({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // debug: true, // enable while developing to see auth/realtime logs
    );
    client = Supabase.instance.client;
  }

  static User? get currentUser => client.auth.currentUser;
  static bool get isAuthenticated => currentUser != null;
}
