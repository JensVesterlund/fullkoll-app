import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

class GiftCardsRepo {
  final _table = 'gift_cards';
  final _uuid = const Uuid();

  Future<Map<String, dynamic>> create({
    required String brand,
    required double initialBalance,
    required double currentBalance,
    String currency = 'SEK',
    String? category,
    DateTime? purchaseAt,
    DateTime? expiresAt,
    String? notes,
    String? imageUrl,
    String? cardNumber,
  }) async {
    final userId = supa.auth.currentUser!.id;
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'owner_id': userId,
      'brand': brand,
      'category': category,
      'purchase_at': purchaseAt?.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
      'card_number': cardNumber,
      'initial_balance': initialBalance,
      'current_balance': currentBalance,
      'currency': currency,
      'notes': notes,
      'image_url': imageUrl,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    // ignore: avoid_print
    print('[SB][gift_cards] INSERT -> ${payload.toString()}');
    final res = await supa.from(_table).insert(payload).select().single();
    // ignore: avoid_print
    print('[SB][gift_cards] INSERT OK id=${res['id']}');
    return Map<String, dynamic>.from(res as Map);
  }

  Future<List<Map<String, dynamic>>> list() async {
    final userId = supa.auth.currentUser!.id;
    // ignore: avoid_print
    print('[SB][gift_cards] SELECT list for owner=$userId');
    final rows = await supa
        .from(_table)
        .select()
        .eq('owner_id', userId)
        .order('expires_at', ascending: true);
    // ignore: avoid_print
    print('[SB][gift_cards] SELECT OK count=${rows.length}');
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getById(String id) async {
    // ignore: avoid_print
    print('[SB][gift_cards] SELECT by id=$id');
    final res = await supa.from(_table).select().eq('id', id).single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[SB][gift_cards] UPDATE id=$id patch=${patch.keys.toList()}');
    await supa.from(_table).update(patch).eq('id', id);
  }

  Future<void> delete(String id) async {
    // ignore: avoid_print
    print('[SB][gift_cards] DELETE id=$id');
    await supa.from(_table).delete().eq('id', id);
  }
}
