import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

class BudgetRepo {
  final String _txTable = 'budget_transactions';
  final String _catTable = 'budget_categories';
  final _uuid = const Uuid();

  // Categories
  Future<List<Map<String, dynamic>>> listCategories(String budgetId) async {
    // ignore: avoid_print
    print('[SB][budget_categories] SELECT for budget=$budgetId');
    final rows = await supa.from(_catTable).select().eq('budget_id', budgetId).order('name');
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createCategory({required String budgetId, required String name, required double limit}) async {
    final id = _uuid.v4();
    final payload = {'id': id, 'budget_id': budgetId, 'name': name, 'monthly_limit': limit};
    // ignore: avoid_print
    print('[SB][budget_categories] INSERT -> $payload');
    final res = await supa.from(_catTable).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> updateCategory(String id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[SB][budget_categories] UPDATE id=$id patch=${patch.keys.toList()}');
    await supa.from(_catTable).update(patch).eq('id', id);
  }

  Future<void> deleteCategory(String id) async {
    // ignore: avoid_print
    print('[SB][budget_categories] DELETE id=$id');
    await supa.from(_catTable).delete().eq('id', id);
  }

  // Transactions
  Future<List<Map<String, dynamic>>> listTransactions(String budgetId) async {
    // ignore: avoid_print
    print('[SB][budget_transactions] SELECT for budget=$budgetId');
    final rows = await supa
        .from(_txTable)
        .select()
        .eq('budget_id', budgetId)
        .order('date', ascending: false);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createTransaction({
    required String budgetId,
    required String categoryId,
    required String type,
    String? description,
    required double amount,
    required DateTime date,
  }) async {
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'budget_id': budgetId,
      'category_id': categoryId,
      'type': type,
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
    };
    // ignore: avoid_print
    print('[SB][budget_transactions] INSERT -> $payload');
    final res = await supa.from(_txTable).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> deleteTransaction(String id) async {
    // ignore: avoid_print
    print('[SB][budget_transactions] DELETE id=$id');
    await supa.from(_txTable).delete().eq('id', id);
  }
}
