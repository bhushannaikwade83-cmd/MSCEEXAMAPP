import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_env.dart';

export '../config/supabase_env.dart' show SupabaseEnv;

/// True when `app_config.env` has Supabase URL + anon key (UI banner).
bool get isSupabaseEnvConfigured => SupabaseEnv.isConfigured;

/// True when Supabase client is initialized and safe to use.
bool get isSupabaseConfigured => SupabaseEnv.isReady;

SupabaseClient get supabase {
  if (!SupabaseEnv.isReady) {
    throw StateError('Supabase not initialized — check app_config.env');
  }
  return Supabase.instance.client;
}

Future<void> initSupabase() => SupabaseEnv.initializeRequired();
