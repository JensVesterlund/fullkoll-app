import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

class ReceiptsRepo {
  final _table = 'receipts';
  final _uuid = const Uuid();

  Future<Map<String, dynamic>> create({
    required String store,
    required double amount,
    required String currency,
    DateTime? purchasedAt,
    String? category,
    String? notes,
    String? imageUrl,
    String? budgetId,
    String? budgetCategoryId,
  }) async {
    final userId = supa.auth.currentUser!.id;
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'owner_id': userId,
      'store': store,
      'amount': amount,
      'currency': currency,
      'purchased_at': purchasedAt?.toIso8601String(),
      'category': category,
      'notes': notes,
      'image_url': imageUrl,
      'budget_id': budgetId,
      'budget_category_id': budgetCategoryId,
      'created_at': DateTime.now().toIso8601String(),
    };
    // debug log
    // ignore: avoid_print
    print('[SB][receipts] INSERT -> ${payload.toString()}');
    final res = await supa.from(_table).insert(payload).select().single();
    // ignore: avoid_print
    print('[SB][receipts] INSERT OK id=${res['id']}');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final userId = supa.auth.currentUser!.id;
    // ignore: avoid_print
    print('[SB][receipts] SELECT list for owner=$userId');
    final rows = await supa
        .from(_table)
        .select()
        .eq('owner_id', userId)
        .order('purchased_at', ascending: false);
    // ignore: avoid_print
    print('[SB][receipts] SELECT OK count=${rows.length}');
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getById(String id) async {
    // ignore: avoid_print
    print('[SB][receipts] SELECT by id=$id');
    final res = await supa.from(_table).select().eq('id', id).single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[SB][receipts] UPDATE id=$id patch=${patch.keys.toList()}');
    await supa.from(_table).update(patch).eq('id', id);
  }

  Future<void> delete(String id) async {
    // ignore: avoid_print
    print('[SB][receipts] DELETE id=$id');
    await supa.from(_table).delete().eq('id', id);
  }
}
