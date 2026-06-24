import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client.dart';

/// Same alias as MSCE APP 2 — routes face services to this app's Supabase client.
SupabaseClient get appDb => supabase;
