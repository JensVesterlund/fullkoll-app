import 'package:uuid/uuid.dart';

import '../supabase_client.dart';

class SubscriptionsRepo {
  final _table = 'subscriptions';
  final _uuid = const Uuid();

  Future<List<Map<String, dynamic>>> list() async {
    final userId = supa.auth.currentUser!.id;
    // ignore: avoid_print
    print('[SB][subscriptions] SELECT list for owner=$userId');
    final rows = await supa
        .from(_table)
        .select()
        .eq('owner_id', userId)
        .order('next_charge_at', ascending: true);
    return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> create({
    required String serviceName,
    required String category,
    required double amountPerPeriod,
    String currency = 'SEK',
    required String billingInterval,
    required String paymentMethod,
    required DateTime nextChargeAt,
    required DateTime startDate,
    int? bindingMonths,
    bool trialEnabled = false,
    DateTime? trialEndsAt,
    double? trialPrice,
    List<int>? reminderBeforeChargeDays,
    bool reminderOnTrialEnd = true,
    String? budgetCategoryId,
    String? notes,
    String? portalUrl,
    String status = 'active',
  }) async {
    final userId = supa.auth.currentUser!.id;
    final id = _uuid.v4();
    final payload = {
      'id': id,
      'owner_id': userId,
      'service_name': serviceName,
      'category': category,
      'amount_per_period': amountPerPeriod,
      'currency': currency,
      'billing_interval': billingInterval,
      'payment_method': paymentMethod,
      'next_charge_at': nextChargeAt.toIso8601String(),
      'start_date': startDate.toIso8601String(),
      'binding_months': bindingMonths,
      'trial_enabled': trialEnabled,
      'trial_ends_at': trialEndsAt?.toIso8601String(),
      'trial_price': trialPrice,
      'reminder_before_charge_days': (reminderBeforeChargeDays ?? const [14, 1]).join(','),
      'reminder_on_trial_end': reminderOnTrialEnd,
      'budget_category_id': budgetCategoryId,
      'notes': notes,
      'portal_url': portalUrl,
      'status': status,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    // ignore: avoid_print
    print('[SB][subscriptions] INSERT -> ${payload.toString()}');
    final res = await supa.from(_table).insert(payload).select().single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<Map<String, dynamic>> getById(String id) async {
    final res = await supa.from(_table).select().eq('id', id).single();
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> update(String id, Map<String, dynamic> patch) async {
    // ignore: avoid_print
    print('[SB][subscriptions] UPDATE id=$id patch=${patch.keys.toList()}');
    await supa.from(_table).update(patch).eq('id', id);
  }

  Future<void> delete(String id) async {
    // ignore: avoid_print
    print('[SB][subscriptions] DELETE id=$id');
    await supa.from(_table).delete().eq('id', id);
  }
}
