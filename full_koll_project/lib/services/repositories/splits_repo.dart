import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

class SplitsRepo {
  final _groups = 'split_groups';
  final _participants = 'participants';
  final _expenses = 'expenses';
  final _settlements = 'settlements';
  final _uuid = const Uuid();

  // Groups
  Future<List<Map<String, dynamic>>> listGroups() async {
    final ownerId = supa.auth.currentUser!.id;
    // ignore: avoid_print
    print('[SB][split_groups] SELECT list for creator=$ownerId');
    final rows = await supa.from(_groups).select().eq('creator_id', ownerId).order('created_at', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createGroup({required String title}) async {
    final ownerId = supa.auth.currentUser!.id;
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'title': title,
      'creator_id': ownerId,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
    };
    // ignore: avoid_print
    print('[SB][split_groups] INSERT -> $payload');
    final res = await supa.from(_groups).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> updateGroup(String id, Map<String, dynamic> patch) async {
    await supa.from(_groups).update(patch).eq('id', id);
  }

  Future<void> deleteGroup(String id) async {
    await supa.from(_groups).delete().eq('id', id);
  }

  // Participants
  Future<List<Map<String, dynamic>>> listParticipants(String splitGroupId) async {
    final rows = await supa.from(_participants).select().eq('split_group_id', splitGroupId);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createParticipant({
    required String splitGroupId,
    required String name,
    required String contact,
    String? userId,
  }) async {
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'split_group_id': splitGroupId,
      'user_id': userId,
      'name': name,
      'contact': contact,
      'balance': 0,
    };
    final res = await supa.from(_participants).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> updateParticipant(String id, Map<String, dynamic> patch) async {
    await supa.from(_participants).update(patch).eq('id', id);
  }

  Future<void> deleteParticipant(String id) async {
    await supa.from(_participants).delete().eq('id', id);
  }

  // Expenses
  Future<List<Map<String, dynamic>>> listExpenses(String splitGroupId) async {
    final rows = await supa
        .from(_expenses)
        .select()
        .eq('split_group_id', splitGroupId)
        .order('created_at', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createExpense({
    required String splitGroupId,
    required String paidBy,
    String? description,
    required double amount,
    required List<String> sharedWith,
  }) async {
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'split_group_id': splitGroupId,
      'paid_by': paidBy,
      'description': description,
      'amount': amount,
      'shared_with': sharedWith, // array column recommended
      'created_at': DateTime.now().toIso8601String(),
    };
    final res = await supa.from(_expenses).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> deleteExpense(String id) async {
    await supa.from(_expenses).delete().eq('id', id);
  }

  // Settlements
  Future<List<Map<String, dynamic>>> listSettlements(String splitGroupId) async {
    final rows = await supa.from(_settlements).select().eq('split_group_id', splitGroupId);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createSettlement({
    required String splitGroupId,
    required String payerId,
    required String receiverId,
    required double amount,
  }) async {
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'split_group_id': splitGroupId,
      'payer_id': payerId,
      'receiver_id': receiverId,
      'amount': amount,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    };
    final res = await supa.from(_settlements).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> updateSettlement(String id, Map<String, dynamic> patch) async {
    await supa.from(_settlements).update(patch).eq('id', id);
  }
}
