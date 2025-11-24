import '../../models.dart' as app;

class SupaMappers {
  static app.Receipt receipt(Map<String, dynamic> row) {
    final amountRaw = row['amount'];
    final amount = amountRaw is int ? amountRaw.toDouble() : (amountRaw as num?)?.toDouble() ?? 0.0;
    return app.Receipt(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String? ?? '',
      store: row['store'] as String? ?? 'Store',
      purchaseDate: _parseDate(row['purchased_at']) ?? DateTime.now(),
      amount: amount,
      currency: (row['currency'] as String?) ?? 'SEK',
      category: (row['category'] as String?) ?? 'Other',
      notes: row['notes'] as String?,
      imageUrl: row['image_url'] as String?,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? _parseDate(row['created_at']) ?? DateTime.now(),
      archived: false,
      budgetId: row['budget_id'] as String?,
      budgetCategoryId: row['budget_category_id'] as String?,
    );
  }

  static app.GiftCard giftCard(Map<String, dynamic> row) {
    final initialRaw = row['initial_balance'];
    final currentRaw = row['current_balance'];
    final initial = initialRaw is int ? initialRaw.toDouble() : (initialRaw as num?)?.toDouble() ?? 0.0;
    final current = currentRaw is int ? currentRaw.toDouble() : (currentRaw as num?)?.toDouble() ?? 0.0;
    return app.GiftCard(
      id: row['id'] as String,
      ownerId: row['owner_id'] as String? ?? '',
      brand: row['brand'] as String? ?? '',
      category: row['category'] as String? ?? 'Other',
      purchaseDate: _parseDate(row['purchase_at']),
      expiresAt: _parseDate(row['expires_at']),
      cardNumber: row['card_number'] as String? ?? '****',
      initialBalance: initial,
      currentBalance: current,
      currency: (row['currency'] as String?) ?? 'SEK',
      status: (row['status'] as String?) ?? 'active',
      notes: row['notes'] as String?,
      imageUrl: row['image_url'] as String?,
      remindersEnabled: false,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  static app.BudgetCategory budgetCategory(Map<String, dynamic> row) => app.BudgetCategory(
        id: row['id'] as String,
        budgetId: row['budget_id'] as String,
        name: row['name'] as String,
        limit: _asDouble(row['monthly_limit']),
      );

  static app.Transaction transaction(Map<String, dynamic> row) => app.Transaction(
        id: row['id'] as String,
        budgetId: row['budget_id'] as String,
        categoryId: row['category_id'] as String,
        type: row['type'] as String,
        description: row['description'] as String?,
        amount: _asDouble(row['amount']),
        date: _parseDate(row['date']) ?? DateTime.now(),
      );

  static app.AutoGiro subscription(Map<String, dynamic> row) => app.AutoGiro(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String? ?? '',
        serviceName: row['service_name'] as String? ?? '',
        category: row['category'] as String? ?? 'Other',
        amountPerPeriod: _asDouble(row['amount_per_period']),
        currency: (row['currency'] as String?) ?? 'SEK',
        billingInterval: row['billing_interval'] as String? ?? 'monthly',
        paymentMethod: row['payment_method'] as String? ?? 'card',
        nextChargeAt: _parseDate(row['next_charge_at']) ?? DateTime.now(),
        startDate: _parseDate(row['start_date']) ?? DateTime.now(),
        bindingMonths: row['binding_months'] as int?,
        trialEnabled: _asBool(row['trial_enabled']),
        trialEndsAt: _parseDate(row['trial_ends_at']),
        trialPrice: row['trial_price'] == null ? null : _asDouble(row['trial_price']),
        reminderBeforeChargeDays: _parseIntList(row['reminder_before_charge_days']),
        reminderOnTrialEnd: _asBool(row['reminder_on_trial_end']),
        budgetCategoryId: row['budget_category_id'] as String?,
        notes: row['notes'] as String?,
        portalUrl: row['portal_url'] as String?,
        status: (row['status'] as String?) ?? 'active',
        createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
      );

  static app.SplitGroup splitGroup(Map<String, dynamic> row) => app.SplitGroup(
        id: row['id'] as String,
        title: row['title'] as String? ?? 'Group',
        creatorId: row['creator_id'] as String? ?? '',
        status: (row['status'] as String?) ?? 'active',
        createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      );

  static app.Participant participant(Map<String, dynamic> row) => app.Participant(
        id: row['id'] as String,
        splitGroupId: row['split_group_id'] as String,
        userId: row['user_id'] as String?,
        name: row['name'] as String? ?? '',
        contact: row['contact'] as String? ?? '',
        balance: _asDouble(row['balance']),
      );

  static app.Expense expense(Map<String, dynamic> row) {
    final sharedRaw = row['shared_with'];
    List<String> sharedWith;
    if (sharedRaw is List) {
      sharedWith = sharedRaw.map((e) => e.toString()).toList();
    } else if (sharedRaw is String) {
      sharedWith = sharedRaw.split(',').where((e) => e.trim().isNotEmpty).toList();
    } else {
      sharedWith = const [];
    }
    return app.Expense(
      id: row['id'] as String,
      splitGroupId: row['split_group_id'] as String,
      paidBy: row['paid_by'] as String,
      description: row['description'] as String?,
      amount: _asDouble(row['amount']),
      sharedWith: sharedWith,
      splitMethod: (row['split_method'] as String?) ?? 'equal',
      receiptUrl: row['receipt_url'] as String?,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
    );
  }

  static app.Settlement settlement(Map<String, dynamic> row) => app.Settlement(
        id: row['id'] as String,
        splitGroupId: row['split_group_id'] as String,
        payerId: row['payer_id'] as String,
        receiverId: row['receiver_id'] as String,
        amount: _asDouble(row['amount']),
        status: (row['status'] as String?) ?? 'pending',
        settledAt: _parseDate(row['settled_at']),
        createdAt: _parseDate(row['created_at']),
        reminderJobId: row['reminder_job_id'] as String?,
      );

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
    }

  /// Public helper for callers outside this library to parse flexible Supabase timestamps.
  static DateTime? parseDate(dynamic v) => _parseDate(v);

  static double _asDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    if (v is String) return v == 'true' || v == '1';
    return false;
  }

  static List<int> _parseIntList(dynamic v) {
    if (v == null) return const [14, 1];
    if (v is String) {
      return v.split(',').where((e) => e.trim().isNotEmpty).map((e) => int.tryParse(e.trim()) ?? 0).toList();
    }
    if (v is List) {
      return v.map((e) => e is int ? e : int.tryParse(e.toString()) ?? 0).toList();
    }
    return const [14, 1];
  }
}
