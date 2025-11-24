import 'package:supabase_flutter/supabase_flutter.dart';

/// Global Supabase client instance.
///
/// Import this where needed:
///   import 'services/supabase_client.dart';
///   final res = await supa.from('table').select();
final SupabaseClient supa = Supabase.instance.client;
