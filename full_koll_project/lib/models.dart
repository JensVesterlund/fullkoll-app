class User {
  final String id;
  final String email;
  final bool emailVerified;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final String locale;
  final String currency;
  final ReminderDefaults reminderDefaults;
  final NotificationPrefs notificationPrefs;
  final String role;
  final String? passwordDevHash;
  final DateTime? privacyAcceptedAt;
  final int privacyVersion;
  final bool doNotTrack;

  User({
    required this.id,
    required this.email,
    this.emailVerified = false,
    required this.createdAt,
    required this.lastLoginAt,
    this.locale = 'sv-SE',
    this.currency = 'SEK',
    required this.reminderDefaults,
    required this.notificationPrefs,
    this.role = 'user',
    this.passwordDevHash,
    this.privacyAcceptedAt,
    this.privacyVersion = 1,
    this.doNotTrack = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'emailVerified': emailVerified ? 1 : 0,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt.toIso8601String(),
    'locale': locale,
    'currency': currency,
    'reminderDefaultsBeforeExpiry': reminderDefaults.beforeExpiryDays.join(','),
    'reminderDefaultsBeforeCharge': reminderDefaults.beforeChargeDays.join(','),
    'notificationPrefsPush': notificationPrefs.push ? 1 : 0,
    'notificationPrefsEmail': notificationPrefs.email ? 1 : 0,
    'notificationPrefsMuted': notificationPrefs.muted ? 1 : 0,
    'role': role,
    'passwordDevHash': passwordDevHash,
    'privacyAcceptedAt': privacyAcceptedAt?.toIso8601String(),
    'privacyVersion': privacyVersion,
    'doNotTrack': doNotTrack ? 1 : 0,
  };

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'],
    email: json['email'],
    emailVerified: json['emailVerified'] == 1,
    createdAt: DateTime.parse(json['createdAt']),
    lastLoginAt: DateTime.parse(json['lastLoginAt']),
    locale: json['locale'] ?? 'sv-SE',
    currency: json['currency'] ?? 'SEK',
    reminderDefaults: ReminderDefaults(
      beforeExpiryDays: (json['reminderDefaultsBeforeExpiry'] as String).split(',').map((e) => int.parse(e)).toList(),
      beforeChargeDays: (json['reminderDefaultsBeforeCharge'] as String).split(',').map((e) => int.parse(e)).toList(),
    ),
    notificationPrefs: NotificationPrefs(
      push: json['notificationPrefsPush'] == 1,
      email: json['notificationPrefsEmail'] == 1,
      muted: json['notificationPrefsMuted'] == 1,
    ),
    role: json['role'] ?? 'user',
    passwordDevHash: json['passwordDevHash'] as String?,
    privacyAcceptedAt: json['privacyAcceptedAt'] != null ? DateTime.parse(json['privacyAcceptedAt']) : null,
    privacyVersion: json['privacyVersion'] ?? 1,
    doNotTrack: json['doNotTrack'] == 1,
  );

  User copyWith({String? email, bool? emailVerified, DateTime? lastLoginAt, String? locale, String? currency, ReminderDefaults? reminderDefaults, NotificationPrefs? notificationPrefs, String? role, DateTime? privacyAcceptedAt, int? privacyVersion, String? passwordDevHash, bool? doNotTrack}) =>
    User(id: id, email: email ?? this.email, emailVerified: emailVerified ?? this.emailVerified, createdAt: createdAt, lastLoginAt: lastLoginAt ?? this.lastLoginAt, locale: locale ?? this.locale, currency: currency ?? this.currency, reminderDefaults: reminderDefaults ?? this.reminderDefaults, notificationPrefs: notificationPrefs ?? this.notificationPrefs, role: role ?? this.role, privacyAcceptedAt: privacyAcceptedAt ?? this.privacyAcceptedAt, privacyVersion: privacyVersion ?? this.privacyVersion, passwordDevHash: passwordDevHash ?? this.passwordDevHash, doNotTrack: doNotTrack ?? this.doNotTrack);
}

class ReminderDefaults {
  final List<int> beforeExpiryDays;
  final List<int> beforeChargeDays;
  ReminderDefaults({this.beforeExpiryDays = const [30, 7], this.beforeChargeDays = const [14, 1]});
}

class NotificationPrefs {
  final bool push;
  final bool email;
  final bool muted;

  const NotificationPrefs({this.push = true, this.email = false, this.muted = false});

  NotificationPrefs copyWith({bool? push, bool? email, bool? muted}) => NotificationPrefs(
        push: push ?? this.push,
        email: email ?? this.email,
        muted: muted ?? this.muted,
      );
}

class ScheduledNotification {
  final String id;
  final String userId;
  final String resourceType;
  final String resourceId;
  final String channel; // push, local, silent
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final DateTime scheduledAt;
  final DateTime createdAt;
  final String status; // pending, delivered, canceled
  final DateTime? deliveredAt;

  const ScheduledNotification({
    required this.id,
    required this.userId,
    required this.resourceType,
    required this.resourceId,
    required this.channel,
    required this.title,
    required this.body,
    this.data,
    required this.scheduledAt,
    required this.createdAt,
    this.status = 'pending',
    this.deliveredAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'channel': channel,
        'title': title,
        'body': body,
        'data': data,
        'scheduledAt': scheduledAt.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'deliveredAt': deliveredAt?.toIso8601String(),
      };

  factory ScheduledNotification.fromJson(Map<String, dynamic> json) => ScheduledNotification(
        id: json['id'],
        userId: json['userId'],
        resourceType: json['resourceType'],
        resourceId: json['resourceId'],
        channel: json['channel'] ?? 'push',
        title: json['title'],
        body: json['body'],
        data: json['data'] != null ? Map<String, dynamic>.from(json['data'] as Map) : null,
        scheduledAt: DateTime.parse(json['scheduledAt']),
        createdAt: DateTime.parse(json['createdAt']),
        status: json['status'] ?? 'pending',
        deliveredAt: json['deliveredAt'] != null ? DateTime.parse(json['deliveredAt']) : null,
      );

  ScheduledNotification copyWith({String? status, DateTime? deliveredAt}) => ScheduledNotification(
        id: id,
        userId: userId,
        resourceType: resourceType,
        resourceId: resourceId,
        channel: channel,
        title: title,
        body: body,
        data: data,
        scheduledAt: scheduledAt,
        createdAt: createdAt,
        status: status ?? this.status,
        deliveredAt: deliveredAt ?? this.deliveredAt,
      );
}

Map<String, List<String>> _parseStringListMap(dynamic raw) {
  if (raw == null) return const {};
  if (raw is Map) {
    final result = <String, List<String>>{};
    raw.forEach((key, value) {
      final list = value is List ? value.map((e) => e.toString()).toList() : <String>[];
      result[key.toString()] = list;
    });
    return Map<String, List<String>>.unmodifiable(result);
  }
  return const {};
}

List<String> _parseStringList(dynamic raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return List<String>.from(raw.map((e) => e.toString()));
  }
  if (raw is String) {
    if (raw.isEmpty) return const [];
    return raw.split(',').map((e) => e.trim()).where((element) => element.isNotEmpty).toList();
  }
  return const [];
}

class Receipt {
  final String id;
  final String ownerId;
  final String store;
  final DateTime purchaseDate;
  final double amount;
  final String currency;
  final String category;
  final DateTime? returnDeadline;
  final DateTime? exchangeDeadline;
  final DateTime? warrantyExpires;
  final DateTime? refundDeadline;
  final bool remindersEnabled;
  final DateTime? reminder1At;
  final DateTime? reminder2At;
  final Map<String, List<String>> reminderJobIds;
  final String? notes;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool archived;
  final String? budgetId;
  final String? budgetCategoryId;
  final String? budgetTransactionId;

  Receipt({
    required this.id,
    required this.ownerId,
    required this.store,
    required this.purchaseDate,
    required this.amount,
    this.currency = 'SEK',
    required this.category,
    this.returnDeadline,
    this.exchangeDeadline,
    this.warrantyExpires,
    this.refundDeadline,
    this.remindersEnabled = false,
    this.reminder1At,
    this.reminder2At,
    this.reminderJobIds = const {},
    this.notes,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
    this.archived = false,
    this.budgetId,
    this.budgetCategoryId,
    this.budgetTransactionId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'ownerId': ownerId,
    'store': store,
    'purchaseDate': purchaseDate.toIso8601String(),
    'amount': amount,
    'currency': currency,
    'category': category,
    'returnDeadline': returnDeadline?.toIso8601String(),
    'exchangeDeadline': exchangeDeadline?.toIso8601String(),
    'warrantyExpires': warrantyExpires?.toIso8601String(),
    'refundDeadline': refundDeadline?.toIso8601String(),
    'remindersEnabled': remindersEnabled ? 1 : 0,
    'reminder1At': reminder1At?.toIso8601String(),
    'reminder2At': reminder2At?.toIso8601String(),
    'reminderJobs': reminderJobIds.map((key, value) => MapEntry(key, List<String>.from(value))),
    'notes': notes,
    'imageUrl': imageUrl,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'archived': archived ? 1 : 0,
    'budgetId': budgetId,
    'budgetCategoryId': budgetCategoryId,
    'budgetTransactionId': budgetTransactionId,
  };

  factory Receipt.fromJson(Map<String, dynamic> json) => Receipt(
    id: json['id'],
    ownerId: json['ownerId'],
    store: json['store'],
    purchaseDate: DateTime.parse(json['purchaseDate']),
    amount: json['amount'],
    currency: json['currency'] ?? 'SEK',
    category: json['category'],
    returnDeadline: json['returnDeadline'] != null ? DateTime.parse(json['returnDeadline']) : null,
    exchangeDeadline: json['exchangeDeadline'] != null ? DateTime.parse(json['exchangeDeadline']) : null,
    warrantyExpires: json['warrantyExpires'] != null ? DateTime.parse(json['warrantyExpires']) : null,
    refundDeadline: json['refundDeadline'] != null ? DateTime.parse(json['refundDeadline']) : null,
    remindersEnabled: json['remindersEnabled'] == 1,
    reminder1At: json['reminder1At'] != null ? DateTime.parse(json['reminder1At']) : null,
    reminder2At: json['reminder2At'] != null ? DateTime.parse(json['reminder2At']) : null,
    reminderJobIds: _parseStringListMap(json['reminderJobs']),
    notes: json['notes'],
    imageUrl: json['imageUrl'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
    archived: json['archived'] == 1,
    budgetId: json['budgetId'],
    budgetCategoryId: json['budgetCategoryId'],
    budgetTransactionId: json['budgetTransactionId'],
  );

  // Sentinel so copyWith can distinguish explicit null from "not provided".
  static const Object _noChange = Object();

  Receipt copyWith({
    String? store,
    DateTime? purchaseDate,
    double? amount,
    String? currency,
    String? category,
    DateTime? returnDeadline,
    DateTime? exchangeDeadline,
    DateTime? warrantyExpires,
    DateTime? refundDeadline,
    bool? remindersEnabled,
    Object? reminder1At = _noChange,
    Object? reminder2At = _noChange,
    Map<String, List<String>>? reminderJobIds,
    String? notes,
    String? imageUrl,
    bool? archived,
    Object? budgetId = _noChange,
    Object? budgetCategoryId = _noChange,
    Object? budgetTransactionId = _noChange,
  }) =>
    Receipt(
      id: id,
      ownerId: ownerId,
      store: store ?? this.store,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      category: category ?? this.category,
      returnDeadline: returnDeadline ?? this.returnDeadline,
      exchangeDeadline: exchangeDeadline ?? this.exchangeDeadline,
      warrantyExpires: warrantyExpires ?? this.warrantyExpires,
      refundDeadline: refundDeadline ?? this.refundDeadline,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
       reminder1At: identical(reminder1At, _noChange) ? this.reminder1At : reminder1At as DateTime?,
       reminder2At: identical(reminder2At, _noChange) ? this.reminder2At : reminder2At as DateTime?,
      reminderJobIds: reminderJobIds ?? this.reminderJobIds,
      notes: notes ?? this.notes,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      archived: archived ?? this.archived,
      budgetId: identical(budgetId, _noChange) ? this.budgetId : budgetId as String?,
      budgetCategoryId:
          identical(budgetCategoryId, _noChange) ? this.budgetCategoryId : budgetCategoryId as String?,
      budgetTransactionId:
          identical(budgetTransactionId, _noChange) ? this.budgetTransactionId : budgetTransactionId as String?,
    );

  String get statusBadge {
    final now = DateTime.now();
    final deadlines = [returnDeadline, exchangeDeadline, warrantyExpires, refundDeadline].where((d) => d != null).toList();
    if (deadlines.isEmpty) return 'ok';
    final earliest = deadlines.reduce((a, b) => a!.isBefore(b!) ? a : b)!;
    if (earliest.isBefore(now)) return 'passed';
    if (earliest.difference(now).inDays <= 7) return 'dueSoon';
    return 'ok';
  }
}

class GiftCard {
  static const Object _noChange = Object();

  final String id;
  final String ownerId;
  final String brand;
  final String category;
  final DateTime? purchaseDate;
  final DateTime? expiresAt;
  final String cardNumber;
  final String? pin;
  final double initialBalance;
  final double currentBalance;
  final String currency;
  final String status;
  final String? notes;
  final String? imageUrl;
  final bool remindersEnabled;
  final DateTime? reminder1At;
  final DateTime? reminder2At;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GiftCardDocument> documents;
  final List<String> reminderJobIds;

  GiftCard({
    required this.id,
    required this.ownerId,
    required this.brand,
    required this.category,
    this.purchaseDate,
    this.expiresAt,
    required this.cardNumber,
    this.pin,
    required this.initialBalance,
    required this.currentBalance,
    this.currency = 'SEK',
    this.status = 'active',
    this.notes,
    this.imageUrl,
    this.remindersEnabled = false,
    this.reminder1At,
    this.reminder2At,
    required this.createdAt,
    required this.updatedAt,
    this.documents = const [],
    this.reminderJobIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'ownerId': ownerId, 'brand': brand, 'category': category, 'purchaseDate': purchaseDate?.toIso8601String(), 'expiresAt': expiresAt?.toIso8601String(),
    'cardNumber': cardNumber, 'pin': pin, 'initialBalance': initialBalance, 'currentBalance': currentBalance, 'currency': currency, 'status': status,
    'notes': notes, 'imageUrl': imageUrl, 'remindersEnabled': remindersEnabled ? 1 : 0, 'reminder1At': reminder1At?.toIso8601String(), 'reminder2At': reminder2At?.toIso8601String(),
    'reminderJobIds': List<String>.from(reminderJobIds),
    'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(),
    'documents': documents.map((d) => d.toJson()).toList(),
  };

  factory GiftCard.fromJson(Map<String, dynamic> json) => GiftCard(
    id: json['id'], ownerId: json['ownerId'], brand: json['brand'], category: json['category'], purchaseDate: json['purchaseDate'] != null ? DateTime.parse(json['purchaseDate']) : null, expiresAt: json['expiresAt'] != null ? DateTime.parse(json['expiresAt']) : null,
    cardNumber: json['cardNumber'], pin: json['pin'], initialBalance: json['initialBalance'], currentBalance: json['currentBalance'], currency: json['currency'] ?? 'SEK', status: json['status'] ?? 'active',
    notes: json['notes'], imageUrl: json['imageUrl'], remindersEnabled: json['remindersEnabled'] == 1, reminder1At: json['reminder1At'] != null ? DateTime.parse(json['reminder1At']) : null, reminder2At: json['reminder2At'] != null ? DateTime.parse(json['reminder2At']) : null,
    reminderJobIds: _parseStringList(json['reminderJobIds']),
    createdAt: DateTime.parse(json['createdAt']), updatedAt: DateTime.parse(json['updatedAt']),
    documents: (json['documents'] as List?)?.map((e) => GiftCardDocument.fromJson(Map<String, dynamic>.from(e as Map))).toList() ?? const [],
  );

  GiftCard copyWith({
    String? brand,
    String? category,
    Object? purchaseDate = _noChange,
    Object? expiresAt = _noChange,
    String? cardNumber,
    Object? pin = _noChange,
    double? initialBalance,
    double? currentBalance,
    String? currency,
    String? status,
    Object? notes = _noChange,
    Object? imageUrl = _noChange,
    bool? remindersEnabled,
    Object? reminder1At = _noChange,
    Object? reminder2At = _noChange,
    List<GiftCardDocument>? documents,
    List<String>? reminderJobIds,
  }) =>
    GiftCard(
      id: id,
      ownerId: ownerId,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      purchaseDate: purchaseDate == _noChange ? this.purchaseDate : purchaseDate as DateTime?,
      expiresAt: expiresAt == _noChange ? this.expiresAt : expiresAt as DateTime?,
      cardNumber: cardNumber ?? this.cardNumber,
      pin: pin == _noChange ? this.pin : pin as String?,
      initialBalance: initialBalance ?? this.initialBalance,
      currentBalance: currentBalance ?? this.currentBalance,
      currency: currency ?? this.currency,
      status: status ?? this.status,
      notes: notes == _noChange ? this.notes : notes as String?,
      imageUrl: imageUrl == _noChange ? this.imageUrl : imageUrl as String?,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      reminder1At: reminder1At == _noChange ? this.reminder1At : reminder1At as DateTime?,
      reminder2At: reminder2At == _noChange ? this.reminder2At : reminder2At as DateTime?,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      documents: documents ?? this.documents,
      reminderJobIds: reminderJobIds ?? this.reminderJobIds,
    );

  String get maskedCardNumber => cardNumber.length > 4 ? '****${cardNumber.substring(cardNumber.length - 4)}' : cardNumber;

  String get computedStatus {
    final now = DateTime.now();
    if (currentBalance <= 0) return 'used';
    if (expiresAt != null) {
      if (expiresAt!.isBefore(now)) return 'expired';
      if (expiresAt!.difference(now).inDays < 30) return 'expiring';
    }
    return 'active';
  }
}

class GiftCardDocument {
  final String id;
  final String name;
  final String url;
  final String mimeType;
  final int size;
  final DateTime uploadedAt;

  GiftCardDocument({
    required this.id,
    required this.name,
    required this.url,
    required this.mimeType,
    required this.size,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'mimeType': mimeType,
    'size': size,
    'uploadedAt': uploadedAt.toIso8601String(),
  };

  factory GiftCardDocument.fromJson(Map<String, dynamic> json) => GiftCardDocument(
    id: json['id'] as String,
    name: json['name'] as String? ?? 'dokument',
    url: json['url'] as String,
    mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
    size: json['size'] is int ? json['size'] as int : ((json['size'] as num?)?.toInt() ?? 0),
    uploadedAt: json['uploadedAt'] != null ? DateTime.parse(json['uploadedAt'] as String) : DateTime.now(),
  );

  bool get isImage => mimeType.startsWith('image/');
  bool get isPdf => mimeType == 'application/pdf';
}

class GiftCardTransaction {
  final String id;
  final String giftCardId;
  final DateTime date;
  final double amount;
  final String channel;
  final String? note;

  GiftCardTransaction({required this.id, required this.giftCardId, required this.date, required this.amount, required this.channel, this.note});

  Map<String, dynamic> toJson() => {'id': id, 'giftCardId': giftCardId, 'date': date.toIso8601String(), 'amount': amount, 'channel': channel, 'note': note};

  factory GiftCardTransaction.fromJson(Map<String, dynamic> json) => GiftCardTransaction(id: json['id'], giftCardId: json['giftCardId'], date: DateTime.parse(json['date']), amount: json['amount'], channel: json['channel'], note: json['note']);
}

class Budget {
  final String id;
  final String ownerId;
  final String name;
  final int year;
  final DateTime createdAt;
  final DateTime updatedAt;

  Budget({required this.id, required this.ownerId, required this.name, required this.year, required this.createdAt, required this.updatedAt});

  Map<String, dynamic> toJson() => {'id': id, 'ownerId': ownerId, 'name': name, 'year': year, 'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String()};

  factory Budget.fromJson(Map<String, dynamic> json) => Budget(id: json['id'], ownerId: json['ownerId'], name: json['name'], year: json['year'], createdAt: DateTime.parse(json['createdAt']), updatedAt: DateTime.parse(json['updatedAt']));

  Budget copyWith({String? name, int? year}) => Budget(id: id, ownerId: ownerId, name: name ?? this.name, year: year ?? this.year, createdAt: createdAt, updatedAt: DateTime.now());
}

class BudgetCategory {
  final String id;
  final String budgetId;
  final String name;
  final double limit;

  BudgetCategory({required this.id, required this.budgetId, required this.name, required this.limit});

  Map<String, dynamic> toJson() => {'id': id, 'budgetId': budgetId, 'name': name, 'limit': limit};

  factory BudgetCategory.fromJson(Map<String, dynamic> json) => BudgetCategory(id: json['id'], budgetId: json['budgetId'], name: json['name'], limit: json['limit']);

  BudgetCategory copyWith({String? name, double? limit}) => BudgetCategory(id: id, budgetId: budgetId, name: name ?? this.name, limit: limit ?? this.limit);
}

class Transaction {
  final String id;
  final String budgetId;
  final String categoryId;
  final String type;
  final String? description;
  final double amount;
  final DateTime date;

  Transaction({required this.id, required this.budgetId, required this.categoryId, required this.type, this.description, required this.amount, required this.date});

  Map<String, dynamic> toJson() => {'id': id, 'budgetId': budgetId, 'categoryId': categoryId, 'type': type, 'description': description, 'amount': amount, 'date': date.toIso8601String()};

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'] ?? 0;
    final amountValue = rawAmount is int ? rawAmount.toDouble() : (rawAmount as num).toDouble();
    return Transaction(id: json['id'], budgetId: json['budgetId'], categoryId: json['categoryId'], type: json['type'], description: json['description'], amount: amountValue, date: DateTime.parse(json['date']));
  }
}

class BudgetIncome {
  final String id;
  final String budgetId;
  final String description;
  final double amount;
  final String frequency; // 'monthly' or 'yearly'
  final DateTime createdAt;

  BudgetIncome({required this.id, required this.budgetId, required this.description, required this.amount, required this.frequency, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'id': id,
        'budgetId': budgetId,
        'description': description,
        'amount': amount,
        'frequency': frequency,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BudgetIncome.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'] ?? 0;
    final amountValue = rawAmount is int ? rawAmount.toDouble() : (rawAmount as num).toDouble();
    return BudgetIncome(
      id: json['id'],
      budgetId: json['budgetId'],
      description: json['description'] ?? '',
      amount: amountValue,
      frequency: json['frequency'] ?? 'monthly',
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  double get monthlyAmount => frequency == 'monthly' ? amount : amount / 12;
  double get yearlyAmount => frequency == 'yearly' ? amount : amount * 12;

  BudgetIncome copyWith({String? description, double? amount, String? frequency}) => BudgetIncome(
        id: id,
        budgetId: budgetId,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        frequency: frequency ?? this.frequency,
        createdAt: createdAt,
      );
}

class SplitGroup {
  final String id;
  final String title;
  final String creatorId;
  final String status;
  final DateTime createdAt;

  SplitGroup({required this.id, required this.title, required this.creatorId, this.status = 'active', required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'creatorId': creatorId, 'status': status, 'createdAt': createdAt.toIso8601String()};

  factory SplitGroup.fromJson(Map<String, dynamic> json) => SplitGroup(id: json['id'], title: json['title'], creatorId: json['creatorId'], status: json['status'] ?? 'active', createdAt: DateTime.parse(json['createdAt']));

  SplitGroup copyWith({String? title, String? status}) => SplitGroup(id: id, title: title ?? this.title, creatorId: creatorId, status: status ?? this.status, createdAt: createdAt);
}

class SplitAccessGrant {
  final String id;
  final String splitGroupId;
  final String principal;
  final String role; // owner, editor, viewer
  final String status; // pending, accepted, revoked
  final DateTime invitedAt;
  final DateTime? respondedAt;
  final bool allowExport;

  SplitAccessGrant({required this.id, required this.splitGroupId, required this.principal, required this.role, this.status = 'pending', required this.invitedAt, this.respondedAt, this.allowExport = false});

  static const Object _noChange = Object();

  Map<String, dynamic> toJson() => {
        'id': id,
        'splitGroupId': splitGroupId,
        'principal': principal,
        'role': role,
        'status': status,
        'invitedAt': invitedAt.toIso8601String(),
        'respondedAt': respondedAt?.toIso8601String(),
        'allowExport': allowExport ? 1 : 0,
      };

  factory SplitAccessGrant.fromJson(Map<String, dynamic> json) => SplitAccessGrant(
        id: json['id'],
        splitGroupId: json['splitGroupId'],
        principal: json['principal'],
        role: json['role'] ?? 'viewer',
        status: json['status'] ?? 'pending',
        invitedAt: DateTime.parse(json['invitedAt']),
        respondedAt: json['respondedAt'] != null ? DateTime.parse(json['respondedAt']) : null,
        allowExport: json['allowExport'] == 1 || json['allowExport'] == true,
      );

  SplitAccessGrant copyWith({String? principal, String? role, String? status, Object? respondedAt = _noChange, bool? allowExport}) => SplitAccessGrant(
        id: id,
        splitGroupId: splitGroupId,
        principal: principal ?? this.principal,
        role: role ?? this.role,
        status: status ?? this.status,
        invitedAt: invitedAt,
        respondedAt: identical(respondedAt, _noChange) ? this.respondedAt : respondedAt as DateTime?,
        allowExport: allowExport ?? this.allowExport,
      );
}

class Participant {
  final String id;
  final String splitGroupId;
  final String? userId;
  final String name;
  final String contact;
  double balance;

  Participant({required this.id, required this.splitGroupId, this.userId, required this.name, required this.contact, this.balance = 0.0});

  Map<String, dynamic> toJson() => {'id': id, 'splitGroupId': splitGroupId, 'userId': userId, 'name': name, 'contact': contact, 'balance': balance};

  factory Participant.fromJson(Map<String, dynamic> json) => Participant(id: json['id'], splitGroupId: json['splitGroupId'], userId: json['userId'], name: json['name'], contact: json['contact'], balance: json['balance'] ?? 0.0);
}

class Expense {
  final String id;
  final String splitGroupId;
  final String paidBy;
  final String? description;
  final double amount;
  final List<String> sharedWith;
  final String splitMethod;
  final String? receiptUrl;
  final DateTime createdAt;

  Expense({required this.id, required this.splitGroupId, required this.paidBy, this.description, required this.amount, required this.sharedWith, this.splitMethod = 'equal', this.receiptUrl, required this.createdAt});

  Map<String, dynamic> toJson() => {'id': id, 'splitGroupId': splitGroupId, 'paidBy': paidBy, 'description': description, 'amount': amount, 'sharedWith': sharedWith.join(','), 'splitMethod': splitMethod, 'receiptUrl': receiptUrl, 'createdAt': createdAt.toIso8601String()};

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(id: json['id'], splitGroupId: json['splitGroupId'], paidBy: json['paidBy'], description: json['description'], amount: json['amount'], sharedWith: (json['sharedWith'] as String).split(','), splitMethod: json['splitMethod'] ?? 'equal', receiptUrl: json['receiptUrl'], createdAt: DateTime.parse(json['createdAt']));
}

class Settlement {
  final String id;
  final String splitGroupId;
  final String payerId;
  final String receiverId;
  final double amount;
  final String status;
  final DateTime? settledAt;
  final DateTime createdAt;
  final String? reminderJobId;

  static const Object _noChange = Object();

  Settlement({required this.id, required this.splitGroupId, required this.payerId, required this.receiverId, required this.amount, this.status = 'pending', this.settledAt, DateTime? createdAt, this.reminderJobId}) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'splitGroupId': splitGroupId,
        'payerId': payerId,
        'receiverId': receiverId,
        'amount': amount,
        'status': status,
        'settledAt': settledAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'reminderJobId': reminderJobId,
      };

  factory Settlement.fromJson(Map<String, dynamic> json) => Settlement(
        id: json['id'],
        splitGroupId: json['splitGroupId'],
        payerId: json['payerId'],
        receiverId: json['receiverId'],
        amount: json['amount'],
        status: json['status'] ?? 'pending',
        settledAt: json['settledAt'] != null ? DateTime.parse(json['settledAt']) : null,
        createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : DateTime.now(),
        reminderJobId: json['reminderJobId'],
      );

  Settlement copyWith({String? status, DateTime? settledAt, DateTime? createdAt, Object? reminderJobId = _noChange}) => Settlement(
        id: id,
        splitGroupId: splitGroupId,
        payerId: payerId,
        receiverId: receiverId,
        amount: amount,
        status: status ?? this.status,
        settledAt: settledAt ?? this.settledAt,
        createdAt: createdAt ?? this.createdAt,
        reminderJobId: identical(reminderJobId, _noChange) ? this.reminderJobId : reminderJobId as String?,
      );
}

class AutoGiro {
  final String id;
  final String ownerId;
  final String serviceName;
  final String category;
  final double amountPerPeriod;
  final String currency;
  final String billingInterval;
  final String paymentMethod;
  final DateTime nextChargeAt;
  final DateTime startDate;
  final int? bindingMonths;
  final bool trialEnabled;
  final DateTime? trialEndsAt;
  final double? trialPrice;
  final List<int> reminderBeforeChargeDays;
  final bool reminderOnTrialEnd;
  final String? budgetCategoryId;
  final String? notes;
  final String? portalUrl;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> chargeReminderJobIds;
  final String? trialReminderJobId;
  final String? bindingReminderJobId;

  static const Object _noChange = Object();

  AutoGiro({
    required this.id,
    required this.ownerId,
    required this.serviceName,
    required this.category,
    required this.amountPerPeriod,
    this.currency = 'SEK',
    required this.billingInterval,
    required this.paymentMethod,
    required this.nextChargeAt,
    required this.startDate,
    this.bindingMonths,
    this.trialEnabled = false,
    this.trialEndsAt,
    this.trialPrice,
    this.reminderBeforeChargeDays = const [14, 1],
    this.reminderOnTrialEnd = true,
    this.budgetCategoryId,
    this.notes,
    this.portalUrl,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
    this.chargeReminderJobIds = const [],
    this.trialReminderJobId,
    this.bindingReminderJobId,
  });

  bool get isPaused => status == 'paused';

  DateTime? get bindingEndsAt {
    if (bindingMonths == null) return null;
    final targetMonthIndex = (startDate.month - 1) + bindingMonths!;
    final targetYear = startDate.year + targetMonthIndex ~/ 12;
    final targetMonth = (targetMonthIndex % 12) + 1;
    final lastDayOfMonth = DateTime(targetYear, targetMonth + 1, 0).day;
    final day = startDate.day > lastDayOfMonth ? lastDayOfMonth : startDate.day;
    return DateTime(targetYear, targetMonth, day);
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'ownerId': ownerId, 'serviceName': serviceName, 'category': category, 'amountPerPeriod': amountPerPeriod, 'currency': currency, 'billingInterval': billingInterval, 'paymentMethod': paymentMethod,
    'nextChargeAt': nextChargeAt.toIso8601String(), 'startDate': startDate.toIso8601String(), 'bindingMonths': bindingMonths, 'trialEnabled': trialEnabled ? 1 : 0, 'trialEndsAt': trialEndsAt?.toIso8601String(), 'trialPrice': trialPrice,
    'reminderBeforeChargeDays': reminderBeforeChargeDays.join(','), 'reminderOnTrialEnd': reminderOnTrialEnd ? 1 : 0, 'budgetCategoryId': budgetCategoryId, 'notes': notes, 'portalUrl': portalUrl, 'status': status,
    'createdAt': createdAt.toIso8601String(), 'updatedAt': updatedAt.toIso8601String(),
    'chargeReminderJobIds': List<String>.from(chargeReminderJobIds),
    'trialReminderJobId': trialReminderJobId,
    'bindingReminderJobId': bindingReminderJobId,
  };

  factory AutoGiro.fromJson(Map<String, dynamic> json) => AutoGiro(
    id: json['id'], ownerId: json['ownerId'], serviceName: json['serviceName'], category: json['category'], amountPerPeriod: json['amountPerPeriod'], currency: json['currency'] ?? 'SEK', billingInterval: json['billingInterval'], paymentMethod: json['paymentMethod'],
    nextChargeAt: DateTime.parse(json['nextChargeAt']), startDate: DateTime.parse(json['startDate']), bindingMonths: json['bindingMonths'], trialEnabled: json['trialEnabled'] == 1, trialEndsAt: json['trialEndsAt'] != null ? DateTime.parse(json['trialEndsAt']) : null, trialPrice: json['trialPrice'],
    reminderBeforeChargeDays: (json['reminderBeforeChargeDays'] as String).split(',').map((e) => int.parse(e)).toList(), reminderOnTrialEnd: json['reminderOnTrialEnd'] == 1, budgetCategoryId: json['budgetCategoryId'], notes: json['notes'], portalUrl: json['portalUrl'], status: json['status'] ?? 'active',
    createdAt: DateTime.parse(json['createdAt']), updatedAt: DateTime.parse(json['updatedAt']),
    chargeReminderJobIds: _parseStringList(json['chargeReminderJobIds']),
    trialReminderJobId: json['trialReminderJobId'],
    bindingReminderJobId: json['bindingReminderJobId'],
  );

  AutoGiro copyWith({String? serviceName, String? category, double? amountPerPeriod, String? currency, String? billingInterval, String? paymentMethod, DateTime? nextChargeAt, DateTime? startDate, int? bindingMonths, bool? trialEnabled, DateTime? trialEndsAt, double? trialPrice, List<int>? reminderBeforeChargeDays, bool? reminderOnTrialEnd, String? budgetCategoryId, String? notes, String? portalUrl, String? status, List<String>? chargeReminderJobIds, Object? trialReminderJobId = _noChange, Object? bindingReminderJobId = _noChange}) =>
    AutoGiro(
      id: id,
      ownerId: ownerId,
      serviceName: serviceName ?? this.serviceName,
      category: category ?? this.category,
      amountPerPeriod: amountPerPeriod ?? this.amountPerPeriod,
      currency: currency ?? this.currency,
      billingInterval: billingInterval ?? this.billingInterval,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      nextChargeAt: nextChargeAt ?? this.nextChargeAt,
      startDate: startDate ?? this.startDate,
      bindingMonths: bindingMonths ?? this.bindingMonths,
      trialEnabled: trialEnabled ?? this.trialEnabled,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      trialPrice: trialPrice ?? this.trialPrice,
      reminderBeforeChargeDays: reminderBeforeChargeDays ?? this.reminderBeforeChargeDays,
      reminderOnTrialEnd: reminderOnTrialEnd ?? this.reminderOnTrialEnd,
      budgetCategoryId: budgetCategoryId ?? this.budgetCategoryId,
      notes: notes ?? this.notes,
      portalUrl: portalUrl ?? this.portalUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      chargeReminderJobIds: chargeReminderJobIds ?? this.chargeReminderJobIds,
      trialReminderJobId: identical(trialReminderJobId, _noChange) ? this.trialReminderJobId : trialReminderJobId as String?,
      bindingReminderJobId: identical(bindingReminderJobId, _noChange) ? this.bindingReminderJobId : bindingReminderJobId as String?,
    );
}

class ShareRoles {
  static const String owner = 'owner';
  static const String editor = 'editor';
  static const String viewer = 'viewer';
}

class ShareGrant {
  final String id;
  final String resourceType;
  final String resourceId;
  final String principalType; // user, email
  final String principal;
  final String role;
  final String status; // active, pending, revoked
  final String createdBy;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final DateTime? updatedAt;
  final String? note;
  final bool allowExport;

  const ShareGrant({
    required this.id,
    required this.resourceType,
    required this.resourceId,
    this.principalType = 'email',
    required this.principal,
    this.role = ShareRoles.viewer,
    this.status = 'pending',
    required this.createdBy,
    required this.createdAt,
    this.respondedAt,
    this.updatedAt,
    this.note,
    this.allowExport = false,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending';
  bool get isRevoked => status == 'revoked';

  ShareGrant copyWith({
    String? principalType,
    String? principal,
    String? role,
    String? status,
    DateTime? respondedAt,
    DateTime? updatedAt,
    String? note,
    bool? allowExport,
  }) =>
      ShareGrant(
        id: id,
        resourceType: resourceType,
        resourceId: resourceId,
        principalType: principalType ?? this.principalType,
        principal: principal ?? this.principal,
        role: role ?? this.role,
        status: status ?? this.status,
        createdBy: createdBy,
        createdAt: createdAt,
        respondedAt: respondedAt ?? this.respondedAt,
        updatedAt: updatedAt ?? this.updatedAt,
        note: note ?? this.note,
        allowExport: allowExport ?? this.allowExport,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'resourceType': resourceType,
        'resourceId': resourceId,
        'principalType': principalType,
        'principal': principal,
        'role': role,
        'status': status,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        'respondedAt': respondedAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'note': note,
        'allowExport': allowExport ? 1 : 0,
      };

  factory ShareGrant.fromJson(Map<String, dynamic> json) => ShareGrant(
        id: json['id'],
        resourceType: json['resourceType'],
        resourceId: json['resourceId'],
        principalType: json['principalType'] ?? 'email',
        principal: json['principal'],
        role: json['role'] ?? ShareRoles.viewer,
        status: json['status'] ?? 'pending',
        createdBy: json['createdBy'] ?? '',
        createdAt: DateTime.parse(json['createdAt']),
        respondedAt: json['respondedAt'] != null ? DateTime.parse(json['respondedAt']) : null,
        updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
        note: json['note'],
        allowExport: json['allowExport'] == 1 || json['allowExport'] == true,
      );
}

class ShareAccess {
  final String effectiveRole;
  final bool isOwner;
  final bool allowExport;

  const ShareAccess({required this.effectiveRole, this.isOwner = false, this.allowExport = false});

  bool get canView => effectiveRole != 'none';
  bool get canEdit => effectiveRole == ShareRoles.owner || effectiveRole == ShareRoles.editor;
  bool get canShare => effectiveRole == ShareRoles.owner || effectiveRole == ShareRoles.editor;
  bool get canExport => isOwner || effectiveRole == ShareRoles.editor || allowExport;
}
