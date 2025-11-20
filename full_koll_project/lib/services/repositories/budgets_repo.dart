import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

/// Supabase repository for top-level budgets table
class BudgetsRepo {
  final _table = 'budgets';
  final _uuid = const Uuid();

  Future<List<Map<String, dynamic>>> list() async {
    final userId = supa.auth.currentUser!.id;
    // ignore: avoid_print
    print('[SB][budgets] SELECT list for owner=$userId');
    final rows = await supa
        .from(_table)
        .select()
        .eq('owner_id', userId)
        .order('year', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> getById(String id) async {
    // ignore: avoid_print
    print('[SB][budgets] SELECT by id=$id');
    final res = await supa.from(_table).select().eq('id', id).maybeSingle();
    return res == null ? null : Map<String, dynamic>.from(res as Map);
  }

  /// Create a budget with a provided id (to keep app state consistent)
  Future<Map<String, dynamic>> create({
    String? id,
    required String name,
    required int year,
  }) async {
    final userId = supa.auth.currentUser!.id;
    final budgetId = id ?? _uuid.v4();
    final payload = {
      'id': budgetId,
      'owner_id': userId,
      'name': name,
      'year': year,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    // ignore: avoid_print
    print('[SB][budgets] INSERT -> $payload');
    final res = await supa.from(_table).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[SB][budgets] UPDATE id=$id patch=${patch.keys.toList()}');
    await supa.from(_table).update(patch).eq('id', id);
  }

  Future<void> delete(String id) async {
    // ignore: avoid_print
    print('[SB][budgets] DELETE id=$id');
    await supa.from(_table).delete().eq('id', id);
  }
}
