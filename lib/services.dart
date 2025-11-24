import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sembast/sembast.dart' hide Transaction;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'database.dart';
import 'document_storage.dart';
import 'models.dart';
import 'utils/file_export_helper.dart';
import 'utils/notification_schedule.dart';
import 'services/analytics.dart';
import 'i18n/app_localizations.dart';
import 'services/auth_supabase.dart';
// Supabase repositories
import 'services/repositories/receipts_repo.dart';
import 'services/repositories/giftcards_repo.dart';
import 'services/repositories/budget_repo.dart';
import 'services/repositories/budgets_repo.dart';
import 'services/repositories/subscriptions_repo.dart';
import 'services/repositories/splits_repo.dart';
import 'services/repositories/mappers.dart';

const _uuid = Uuid();
FlutterSecureStorage? _secureStorageInstance;
FlutterSecureStorage get _secureStorage => _secureStorageInstance ??= const FlutterSecureStorage();

/// SensitiveAuth: lightweight re-auth and 60s unlock window for viewing sensitive data
class SensitiveAuth {
  static final Map<String, DateTime> _unlockedUntil = {};

  static bool isUnlocked(String userId) {
    final until = _unlockedUntil[userId];
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _unlockedUntil.remove(userId);
    return false;
  }

  static void _grant(String userId) {
    _unlockedUntil[userId] = DateTime.now().add(const Duration(seconds: 60));
  }

  static Future<bool> ensureUnlocked(BuildContext context, User user) async {
    if (isUnlocked(user.id)) return true;
    if (user.id == AuthService.guestUserId) {
      _grant(user.id);
      return true;
    }

    final l10n = context.l10n;
    final controller = TextEditingController();
    bool verified = false;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('sensitive.reauth.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.translate('sensitive.reauth.subtitle')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l10n.translate('sensitive.reauth.password'),
                prefixIcon: const Icon(Icons.lock),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.translate('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final stored = await AuthService._readSecure(AuthService._passwordKey(user.id));
              if (stored != null && stored == controller.text) {
                verified = true;
                // ignore: use_build_context_synchronously
                Navigator.of(ctx).pop();
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(l10n.translate('sensitive.reauth.failed'))),
                );
              }
            },
            child: Text(l10n.translate('sensitive.reauth.confirm')),
          ),
        ],
      ),
    );

    if (verified) {
      _grant(user.id);
      return true;
    }
    return false;
  }
}

class AuthService {
  static const String _currentUserIdKey = 'currentUserId';
  static const String guestUserId = 'dev-guest';

  static String _passwordKey(String userId) => 'password_$userId';

  static String _hashPassword(String password) => sha256.convert(utf8.encode('fullkoll::$password')).toString();

  static Future<String?> _readSecure(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      // ignore: avoid_print
      print('[AUTH] secure read failed for $key: $e');
      return null;
    }
  }

  static Future<void> _writeSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (e) {
      // ignore: avoid_print
      print('[AUTH] secure write failed for $key: $e');
    }
  }

  static Future<User?> login(String email, String password) async {
    // Prefer Supabase auth when available.
    try {
      final user = await SupabaseAuthAdapter.signInWithPassword(email: email, password: password);
      await _writeSecure(_passwordKey(user.id), password); // temporary local unlock support
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentUserIdKey, user.id);
      // ignore: discarded_futures
      NotificationService.trackEvent('auth_login', {'userId': user.id});
      return user;
    } catch (e) {
      // Fallback to local mock login for dev/guest scenarios
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AUTH] Supabase login failed, falling back: $e');
      }
      // Legacy local path
      final users = await AppDatabase.findAll(
        'users',
        filter: Filter.equals('email', email),
      );
      if (users.isEmpty) return null;
      final userMap = users.first;
      final user = User.fromJson(userMap);
      final hashedAttempt = _hashPassword(password);
      final secureKey = _passwordKey(user.id);
      final securePassword = await _readSecure(secureKey);
      final matchesSecure = securePassword != null && securePassword == password;
      final matchesFallback = user.passwordDevHash != null && user.passwordDevHash == hashedAttempt;
      final isLegacyUser = !matchesSecure && !matchesFallback && user.passwordDevHash == null && securePassword == null;
      if (!matchesSecure && !matchesFallback && !isLegacyUser) {
        return null;
      }
      if (securePassword == null) {
        await _writeSecure(secureKey, password);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentUserIdKey, user.id);
      final updatedUser = user.copyWith(lastLoginAt: DateTime.now(), passwordDevHash: hashedAttempt);
      await AppDatabase.put('users', user.id, updatedUser.toJson());
      // ignore: discarded_futures
      NotificationService.trackEvent('auth_login_local', {'userId': user.id});
      return updatedUser;
    }
  }

  static Future<User> signup(String email, String password) async {
    try {
      final user = await SupabaseAuthAdapter.signUp(email: email, password: password);
      await _writeSecure(_passwordKey(user.id), password); // temporary local unlock support
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentUserIdKey, user.id);
      // ignore: discarded_futures
      NotificationService.trackEvent('auth_signup', {'userId': user.id});
      return user;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[AUTH] Supabase signup failed, falling back local: $e');
      }
      final now = DateTime.now();
      final user = User(
        id: _uuid.v4(),
        email: email,
        createdAt: now,
        lastLoginAt: now,
        reminderDefaults: ReminderDefaults(),
        notificationPrefs: NotificationPrefs(),
        passwordDevHash: _hashPassword(password),
      );
      await AppDatabase.put('users', user.id, user.toJson());
      await _writeSecure(_passwordKey(user.id), password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentUserIdKey, user.id);
      // ignore: discarded_futures
      NotificationService.trackEvent('auth_signup_local', {'userId': user.id});
      return user;
    }
  }

  static Future<void> logout() async {
    try {
      await SupabaseAuthAdapter.signOut();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserIdKey);
    // ignore: discarded_futures
    NotificationService.trackEvent('auth_logout', {});
  }

  static Future<User> loginGuest({bool fresh = true}) async {
    // ignore: avoid_print
    print('[AUTH] guest login start');
    if (fresh) {
      await AppDatabase.reset();
      await DocumentStorage.clearAll();
      try {
        await _secureStorage.deleteAll();
      } catch (e) {
        // ignore: avoid_print
        print('[AUTH] secure deleteAll failed: $e');
      }
    }

    final now = DateTime.now();
    final existing = await AppDatabase.getById('users', guestUserId);
    User user;

    if (existing != null) {
      user = User.fromJson(existing).copyWith(lastLoginAt: now, privacyAcceptedAt: now, privacyVersion: 1);
      await AppDatabase.put('users', user.id, user.toJson());
    } else {
      user = User(
        id: guestUserId,
        email: 'gast@fullkoll.dev',
        createdAt: now,
        lastLoginAt: now,
        reminderDefaults: ReminderDefaults(),
        notificationPrefs: NotificationPrefs(),
        privacyAcceptedAt: now,
        privacyVersion: 1,
      );
      await AppDatabase.put('users', user.id, user.toJson());
      await SeedService.seedData(user);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserIdKey, user.id);
    // ignore: avoid_print
    print('[AUTH] guest login success');
    // ignore: discarded_futures
    NotificationService.trackEvent('auth_guest', {'userId': user.id});
    return user;
  }

  static Future<void> logoutGuest() async {
    // ignore: avoid_print
    print('[AUTH] guest logout start');
    await logout();
    await DocumentStorage.clearAll();
    try {
      await _secureStorage.deleteAll();
    } catch (e) {
      // ignore: avoid_print
      print('[AUTH] secure deleteAll failed: $e');
    }
    await AppDatabase.reset();
    // ignore: avoid_print
    print('[AUTH] guest logout done');
    // ignore: discarded_futures
    NotificationService.trackEvent('auth_guest_logout', {});
  }

  static Future<User?> getCurrentUser() async {
    // Try Supabase session first
    final sbUser = await SupabaseAuthAdapter.getCurrentUser();
    if (sbUser != null) {
      // Also mirror in prefs for compatibility
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_currentUserIdKey, sbUser.id);
      } catch (_) {}
      return sbUser;
    }
    // Legacy local lookup
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
      final userId = prefs.getString(_currentUserIdKey);
      if (userId == null) return null;
      final users = await AppDatabase.findAll('users', filter: Filter.equals('id', userId)).timeout(const Duration(seconds: 3));
      if (users.isEmpty) return null;
      return User.fromJson(users.first);
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime> acceptPrivacy(String userId) async {
    // Attempt to update Supabase user metadata and local mirror
    try {
      return await SupabaseAuthAdapter.acceptPrivacy(userId);
    } catch (_) {
      // Local fallback
      final currentRaw = await AppDatabase.getById('users', userId);
      if (currentRaw == null) {
        throw StateError('Kan inte uppdatera sekretess – användaren saknas');
      }
      final data = Map<String, dynamic>.from(currentRaw);
      final acceptedAt = DateTime.now();
      data['privacyAcceptedAt'] = acceptedAt.toIso8601String();
      data['privacyVersion'] = 1;
      await AppDatabase.put('users', userId, data);
      return acceptedAt;
    }
  }
}

class NotificationService {
  static const String _storeName = 'scheduled_notifications';

  static Future<ScheduledNotification> schedule({
    required String userId,
    required String resourceType,
    required String resourceId,
    required DateTime scheduledAt,
    required String title,
    required String body,
    Map<String, dynamic>? data,
    String channel = 'push',
  }) async {
    final now = DateTime.now();
    final user = await _getUser(userId);
    final prefs = user?.notificationPrefs ?? const NotificationPrefs();
    final effectiveChannel = (prefs.push && !prefs.muted) ? channel : 'local';

    final notification = ScheduledNotification(
      id: _uuid.v4(),
      userId: userId,
      resourceType: resourceType,
      resourceId: resourceId,
      channel: effectiveChannel,
      title: title,
      body: body,
      data: data,
      scheduledAt: scheduledAt,
      createdAt: now,
    );

    await AppDatabase.put(_storeName, notification.id, notification.toJson());

    if (!prefs.push || prefs.muted) {
      _log('[NOTIFY] Push inaktiv för $userId – använder lokal fallback.');
    }

    if (!scheduledAt.isAfter(now)) {
      await _deliver(notification);
    }

    return notification;
  }

  static Future<void> sendPush(String userId, String title, String body, {Map<String, dynamic>? data}) async {
    await schedule(
      userId: userId,
      resourceType: 'direct',
      resourceId: _uuid.v4(),
      scheduledAt: DateTime.now(),
      title: title,
      body: body,
      data: data,
    );
  }

  static Future<void> cancel(String jobId) async {
    final record = await AppDatabase.getById(_storeName, jobId);
    if (record == null) return;
    final notification = ScheduledNotification.fromJson(record);
    final canceled = notification.copyWith(status: 'canceled');
    await AppDatabase.put(_storeName, jobId, canceled.toJson());
    _log('[NOTIFY] Avbokar påminnelse $jobId (${notification.resourceType} :: ${notification.resourceId})');
  }

  static Future<void> cancelMany(Iterable<String> jobIds) async {
    for (final id in jobIds) {
      await cancel(id);
    }
  }

  static Future<void> deliverDueNotifications() async {
    final nowIso = DateTime.now().toIso8601String();
    final records = await AppDatabase.findAll(
      _storeName,
      filter: Filter.and([
        Filter.equals('status', 'pending'),
        Filter.lessThanOrEquals('scheduledAt', nowIso),
      ]),
      sortOrders: [SortOrder('scheduledAt')],
    );

    for (final raw in records) {
      final notification = ScheduledNotification.fromJson(raw);
      await _deliver(notification);
    }
  }

  static Future<List<ScheduledNotification>> getPending(String userId) async {
    final records = await AppDatabase.findAll(
      _storeName,
      filter: Filter.and([
        Filter.equals('userId', userId),
        Filter.equals('status', 'pending'),
      ]),
      sortOrders: [SortOrder('scheduledAt')],
    );
    return records.map(ScheduledNotification.fromJson).toList();
  }

  static Future<List<ScheduledNotification>> getRecent({String? userId, int limit = 25}) async {
    final filters = <Filter>[];
    if (userId != null) {
      filters.add(Filter.equals('userId', userId));
    }
    final records = await AppDatabase.findAll(
      _storeName,
      filter: filters.isEmpty ? null : Filter.and(filters),
      sortOrders: [SortOrder('createdAt', false)],
    );
    return records.map(ScheduledNotification.fromJson).take(limit).toList();
  }

  static Future<void> trackEvent(String event, Map<String, dynamic> payload) async {
    if (event.isEmpty) return;
    try {
      final user = await AuthService.getCurrentUser();
      if (user != null && user.doNotTrack) {
        return; // Respect DNT: skip analytics
      }
    } catch (_) {
      // ignore read errors
    }
    final enriched = {
      ...payload,
      'ts': DateTime.now().toIso8601String(),
    };
    _log('[ANALYTICS] $event ${jsonEncode(enriched)}');
  }

  static Future<void> _deliver(ScheduledNotification notification) async {
    final deliveredAt = DateTime.now();
    final updated = notification.copyWith(status: 'delivered', deliveredAt: deliveredAt);
    await AppDatabase.put(_storeName, notification.id, updated.toJson());

    final channelLabel = notification.channel.toUpperCase();
    _log('[NOTIFY][$channelLabel] ${updated.title} → ${updated.body}');
    if (notification.data != null && notification.data!.isNotEmpty) {
      _log('[NOTIFY] payload: ${jsonEncode(notification.data)}');
    }

    final analyticsEvent = notification.data?['analyticsEvent'] as String?;
    if (analyticsEvent != null) {
      await trackEvent(analyticsEvent, {
        'resourceType': notification.resourceType,
        'resourceId': notification.resourceId,
        'channel': notification.channel,
      });
    }
  }

  static Future<User?> _getUser(String userId) async {
    final raw = await AppDatabase.getById('users', userId);
    if (raw == null) return null;
    return User.fromJson(raw);
  }

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print(message);
    }
  }
}

class ReminderCoordinator {
  static Future<AppLocalizations> _l10nForTag(String tag) async {
    final parts = tag.split('-');
    final locale = parts.length == 2 ? Locale(parts[0], parts[1]) : Locale(parts.first);
    return AppLocalizations.load(locale);
  }

  static Future<String> _userLocaleTag(String userId) async {
    final user = await UserService.getById(userId);
    final raw = user?.locale ?? 'sv-SE';
    if (raw.contains('-')) return raw;
    return raw == 'en' ? 'en-US' : (raw == 'sv' ? 'sv-SE' : 'sv-SE');
  }

  static String _formatDate(DateTime date, String tag) => DateFormat('d MMM yyyy', tag).format(date);

  static Future<Receipt> syncReceipt(Receipt receipt, {Receipt? previous}) async {
    if (previous != null) {
      await cancelReceipt(previous);
    }

    if (!receipt.remindersEnabled) {
      await cancelReceipt(receipt);
      return receipt.copyWith(reminderJobIds: const {}, reminder1At: null, reminder2At: null);
    }

    final deadlines = <String, DateTime>{
      if (receipt.returnDeadline != null) 'returnDeadline': receipt.returnDeadline!,
      if (receipt.exchangeDeadline != null) 'exchangeDeadline': receipt.exchangeDeadline!,
      if (receipt.warrantyExpires != null) 'warrantyExpires': receipt.warrantyExpires!,
      if (receipt.refundDeadline != null) 'refundDeadline': receipt.refundDeadline!,
    };

    if (deadlines.isEmpty) {
      await cancelReceipt(receipt);
      return receipt.copyWith(reminderJobIds: const {}, reminder1At: null, reminder2At: null);
    }

    final now = DateTime.now();
    final newJobs = <String, List<String>>{};
    final scheduledTimes = <DateTime>[];

    final localeTag = await _userLocaleTag(receipt.ownerId);
    final l10n = await _l10nForTag(localeTag);
    for (final entry in deadlines.entries) {
      final slots = NotificationScheduleUtils.buildSlots(
        deadline: entry.value,
        offsetDays: const [7, 1],
        now: now,
      );
      if (slots.isEmpty) continue;

      final jobIds = <String>[];
      for (final scheduledAt in slots) {
        final notification = await NotificationService.schedule(
          userId: receipt.ownerId,
          resourceType: 'receipt',
          resourceId: receipt.id,
          scheduledAt: scheduledAt,
          title: l10n.translate('notifications.receipts.returnDeadlineTitle', params: {'store': receipt.store}),
          body: l10n.translate('notifications.receipts.returnDeadlineBody', params: {
            'date': _formatDate(entry.value, localeTag),
          }),
          data: {
            'deadline': entry.value.toIso8601String(),
            'deadlineType': entry.key,
            'analyticsEvent': 'receipt_reminder_fired',
          },
        );
        jobIds.add(notification.id);
        scheduledTimes.add(scheduledAt);

        await NotificationService.trackEvent('receipt_reminder_scheduled', {
          'receiptId': receipt.id,
          'deadlineType': entry.key,
          'scheduledAt': scheduledAt.toIso8601String(),
        });
      }
      newJobs[entry.key] = jobIds;
    }

    final sortedTimes = List<DateTime>.from(scheduledTimes)..sort();
    final reminder1 = sortedTimes.isNotEmpty ? sortedTimes.first : null;
    final reminder2 = sortedTimes.length > 1 ? sortedTimes[1] : null;

    return receipt.copyWith(
      reminderJobIds: newJobs,
      reminder1At: reminder1,
      reminder2At: reminder2,
    );
  }

  static Future<void> cancelReceipt(Receipt receipt) async {
    if (receipt.reminderJobIds.isEmpty) return;
    await NotificationService.cancelMany(receipt.reminderJobIds.values.expand((ids) => ids));
  }

  static Future<GiftCard> syncGiftCard(GiftCard card, {GiftCard? previous}) async {
    if (previous != null) {
      await cancelGiftCard(previous);
    }

    if (!card.remindersEnabled || card.expiresAt == null) {
      await cancelGiftCard(card);
      return card.copyWith(reminderJobIds: const [], reminder1At: null, reminder2At: null, status: card.computedStatus);
    }

    final now = DateTime.now();
    final jobIds = <String>[];
    final scheduledTimes = <DateTime>[];

    final slots = NotificationScheduleUtils.buildSlots(
      deadline: card.expiresAt!,
      offsetDays: const [30, 7],
      now: now,
    );

    final localeTag = await _userLocaleTag(card.ownerId);
    final l10n = await _l10nForTag(localeTag);
    for (final scheduledAt in slots) {
      final offset = card.expiresAt!.difference(scheduledAt).inDays;
      final notification = await NotificationService.schedule(
        userId: card.ownerId,
        resourceType: 'giftcard',
        resourceId: card.id,
        scheduledAt: scheduledAt,
        title: l10n.translate('notifications.giftcards.expiryTitle'),
        body: l10n.translate('notifications.giftcards.expiryBody', params: {
          'brand': card.brand,
          'date': _formatDate(card.expiresAt!, localeTag),
        }),
        data: {
          'expiresAt': card.expiresAt!.toIso8601String(),
          'offsetDays': offset,
          'analyticsEvent': 'giftcard_reminder_fired',
        },
      );
      jobIds.add(notification.id);
      scheduledTimes.add(scheduledAt);

      await NotificationService.trackEvent('giftcard_reminder_scheduled', {
        'giftCardId': card.id,
        'scheduledAt': scheduledAt.toIso8601String(),
        'offsetDays': offset,
      });
    }

    final sortedTimes = List<DateTime>.from(scheduledTimes)..sort();
    final reminder1 = sortedTimes.isNotEmpty ? sortedTimes.first : null;
    final reminder2 = sortedTimes.length > 1 ? sortedTimes[1] : null;

    return card.copyWith(
      reminderJobIds: jobIds,
      reminder1At: reminder1,
      reminder2At: reminder2,
      status: card.computedStatus,
    );
  }

  static Future<void> cancelGiftCard(GiftCard card) async {
    if (card.reminderJobIds.isEmpty) return;
    await NotificationService.cancelMany(card.reminderJobIds);
  }

  static Future<AutoGiro> syncAutoGiro(AutoGiro giro, {AutoGiro? previous}) async {
    if (previous != null) {
      await cancelAutoGiro(previous);
    }

    if (giro.isPaused) {
      await cancelAutoGiro(giro);
      return giro.copyWith(chargeReminderJobIds: const [], trialReminderJobId: null, bindingReminderJobId: null);
    }

    final now = DateTime.now();
    final scheduledTimes = <DateTime>[];
    final chargeJobIds = <String>[];

    final chargeSlots = NotificationScheduleUtils.buildSlots(
      deadline: giro.nextChargeAt,
      offsetDays: giro.reminderBeforeChargeDays.toSet(),
      now: now,
    );

    final localeTag = await _userLocaleTag(giro.ownerId);
    final l10n = await _l10nForTag(localeTag);
    for (final scheduledAt in chargeSlots) {
      final offset = giro.nextChargeAt.difference(scheduledAt).inDays;
      final notification = await NotificationService.schedule(
        userId: giro.ownerId,
        resourceType: 'autogiro',
        resourceId: giro.id,
        scheduledAt: scheduledAt,
        title: l10n.translate('notifications.autogiro.chargeSoonTitle'),
        body: l10n.translate('notifications.autogiro.chargeSoonBody', params: {
          'service': giro.serviceName,
          'amount': giro.amountPerPeriod.toStringAsFixed(0),
          'date': _formatDate(giro.nextChargeAt, localeTag),
        }),
        data: {
          'chargeAt': giro.nextChargeAt.toIso8601String(),
          'offsetDays': offset,
          'analyticsEvent': 'autogiro_reminder_fired',
        },
      );
      chargeJobIds.add(notification.id);
      scheduledTimes.add(scheduledAt);

      await NotificationService.trackEvent('autogiro_reminder_scheduled', {
        'autogiroId': giro.id,
        'scheduledAt': scheduledAt.toIso8601String(),
        'offsetDays': offset,
      });
    }

    String? trialJobId;
    if (giro.trialEnabled && giro.trialEndsAt != null && giro.reminderOnTrialEnd) {
      final scheduledAt = _normalized(giro.trialEndsAt!);
      if (scheduledAt.isAfter(now)) {
        final notification = await NotificationService.schedule(
          userId: giro.ownerId,
          resourceType: 'autogiro',
          resourceId: giro.id,
          scheduledAt: scheduledAt,
          title: l10n.translate('notifications.autogiro.trialEndTitle'),
          body: l10n.translate('notifications.autogiro.trialEndBody', params: {
            'service': giro.serviceName,
            'date': _formatDate(giro.trialEndsAt!, localeTag),
          }),
          data: {
            'trialEndsAt': giro.trialEndsAt!.toIso8601String(),
            'analyticsEvent': 'autogiro_trial_end',
          },
        );
        trialJobId = notification.id;
        scheduledTimes.add(scheduledAt);
      }
    }

    String? bindingJobId;
    final bindingEndsAt = giro.bindingEndsAt;
    if (bindingEndsAt != null) {
      final scheduledAt = _normalized(bindingEndsAt.subtract(const Duration(days: 30)));
      if (scheduledAt.isAfter(now)) {
        final notification = await NotificationService.schedule(
          userId: giro.ownerId,
          resourceType: 'autogiro',
          resourceId: giro.id,
          scheduledAt: scheduledAt,
          title: l10n.translate('notifications.autogiro.bindingEndTitle', params: {'service': giro.serviceName}),
          body: l10n.translate('notifications.autogiro.bindingEndBody', params: {
            'date': _formatDate(bindingEndsAt, localeTag),
          }),
          data: {
            'bindingEndsAt': bindingEndsAt.toIso8601String(),
            'analyticsEvent': 'autogiro_binding_reminder',
          },
        );
        bindingJobId = notification.id;
        scheduledTimes.add(scheduledAt);
      }
    }

    final updated = giro.copyWith(
      chargeReminderJobIds: chargeJobIds,
      trialReminderJobId: trialJobId,
      bindingReminderJobId: bindingJobId,
    );

    return updated;
  }

  static Future<void> cancelAutoGiro(AutoGiro giro) async {
    if (giro.chargeReminderJobIds.isNotEmpty) {
      await NotificationService.cancelMany(giro.chargeReminderJobIds);
    }
    if (giro.trialReminderJobId != null) {
      await NotificationService.cancel(giro.trialReminderJobId!);
    }
    if (giro.bindingReminderJobId != null) {
      await NotificationService.cancel(giro.bindingReminderJobId!);
    }
  }

  static Future<Settlement> syncSettlementReminder({
    required SplitGroup group,
    required Settlement settlement,
    required Participant debtor,
    required Participant receiver,
  }) async {
    if (settlement.status == 'settled') {
      await cancelSettlementReminder(settlement);
      return settlement.copyWith(reminderJobId: null);
    }

    await cancelSettlementReminder(settlement);

    final triggerAt = _normalized(settlement.createdAt.add(const Duration(days: 3)));
    final localeTag = await _userLocaleTag(debtor.userId ?? group.creatorId);
    final l10n = await _l10nForTag(localeTag);
    final notification = await NotificationService.schedule(
      userId: debtor.userId ?? group.creatorId,
      resourceType: 'split_settlement',
      resourceId: settlement.id,
      scheduledAt: triggerAt,
      title: l10n.translate('notifications.split.unpaidTitle'),
      body: l10n.translate('notifications.split.unpaidBody', params: {
        'payer': debtor.name,
        'receiver': receiver.name,
        'amount': settlement.amount.toStringAsFixed(0),
      }),
      data: {
        'splitGroupId': group.id,
        'analyticsEvent': 'split_payment_reminder_fired',
        'settlementId': settlement.id,
      },
    );

    await NotificationService.trackEvent('split_payment_reminder_scheduled', {
      'splitGroupId': group.id,
      'settlementId': settlement.id,
      'scheduledAt': triggerAt.toIso8601String(),
    });

    return settlement.copyWith(reminderJobId: notification.id);
  }

  static Future<void> cancelSettlementReminder(Settlement settlement) async {
    if (settlement.reminderJobId == null) return;
    await NotificationService.cancel(settlement.reminderJobId!);
  }

  static DateTime _normalized(DateTime target, {int hour = 9}) => NotificationScheduleUtils.normalize(target, hour: hour);

  static void _log(String message) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[REMIND] $message');
    }
  }

  static Future<void> reconcileAll(String userId) async {
    _log('[DAILY] synk startar för $userId');

    final user = await UserService.getById(userId);
    final receipts = await ReceiptService.getAllReceipts(userId, email: user?.email);
    for (final receipt in receipts) {
      await ReceiptService.updateReceipt(receipt);
    }

    final giftCards = await GiftCardService.getAllGiftCards(userId, email: user?.email);
    for (final card in giftCards) {
      await GiftCardService.updateGiftCard(card.copyWith(status: card.computedStatus));
    }

    final autogiros = await AutoGiroService.getAllAutoGiros(userId, email: user?.email);
    for (final giro in autogiros) {
      await AutoGiroService.updateAutoGiro(giro);
    }

    final splitGroups = await SplitService.getAllSplitGroups(userId, email: user?.email);
    for (final group in splitGroups) {
      final settlements = await SplitService.getSettlements(group.id);
      for (final settlement in settlements) {
        await SplitService.updateSettlement(settlement);
      }
    }

    _log('[DAILY] synk klar för $userId');
  }
}

class ReminderMaintenance {
  static const String _lastCheckKeyPrefix = 'reminder_last_check_';

  static Future<void> checkReminders(String userId, {bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_lastCheckKeyPrefix$userId';
    final now = DateTime.now();
    if (!force) {
      final lastRaw = prefs.getString(key);
      if (lastRaw != null) {
        final last = DateTime.tryParse(lastRaw);
        if (last != null) {
          final sameDay = last.year == now.year && last.month == now.month && last.day == now.day;
          final withinSixHours = now.difference(last) < const Duration(hours: 6);
          if (sameDay && withinSixHours) {
            if (kDebugMode) {
              // ignore: avoid_print
              print('[REMIND][DAILY] hoppar över – redan körd ${last.toIso8601String()}');
            }
            return;
          }
        }
      }
    }

    if (kDebugMode) {
      // ignore: avoid_print
      print('[REMIND][DAILY] kör checkReminders för $userId');
    }

    await ReminderCoordinator.reconcileAll(userId);
    await NotificationService.trackEvent('reminder_maintenance_run', {'userId': userId});
    await prefs.setString(key, now.toIso8601String());

    if (kDebugMode) {
      // ignore: avoid_print
      print('[REMIND][DAILY] klar ${now.toIso8601String()}');
    }
  }
}

class ReceiptService {
  static Future<List<Receipt>> getAllReceipts(String userId, {String? email}) async {
    // Prefer Supabase when a session exists
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = ReceiptsRepo();
      final rows = await repo.list();
      final receipts = rows.map(SupaMappers.receipt).toList();
      receipts.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      return receipts;
    }

    // Legacy local fallback
    final ownRecords = await AppDatabase.findAll(
      'receipts',
      filter: Filter.and([
        Filter.equals('ownerId', userId),
        Filter.equals('archived', 0),
      ]),
    );
    final receipts = ownRecords.map((e) => Receipt.fromJson(e)).toList();

    final sharedIds = await SharingService.getSharedResourceIdsForUser(
      resourceType: 'receipt',
      userId: userId,
      email: email,
    );
    for (final sharedId in sharedIds) {
      if (receipts.any((r) => r.id == sharedId)) continue;
      final raw = await AppDatabase.getById('receipts', sharedId);
      if (raw == null) continue;
      if (raw['archived'] == 1) continue;
      receipts.add(Receipt.fromJson(raw));
    }

    receipts.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
    return receipts;
  }

  static Future<Receipt?> getReceipt(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = ReceiptsRepo();
      try {
        final row = await repo.getById(id);
        return SupaMappers.receipt(row);
      } catch (_) {
        return null;
      }
    }
    final receipts = await AppDatabase.findAll(
      'receipts',
      filter: Filter.equals('id', id),
    );
    return receipts.isEmpty ? null : Receipt.fromJson(receipts.first);
  }

  static Future<void> createReceipt(Receipt receipt) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      // Supabase path
      final repo = ReceiptsRepo();
      await repo.create(
        store: receipt.store,
        amount: receipt.amount,
        currency: receipt.currency,
        purchasedAt: receipt.purchaseDate,
        category: receipt.category,
        notes: receipt.notes,
        imageUrl: receipt.imageUrl,
        budgetId: receipt.budgetId,
        budgetCategoryId: receipt.budgetCategoryId,
      );
      // If linked to a budget, also create a transaction via Supabase repo
      final hasBudgetLink =
          (receipt.budgetId != null && receipt.budgetId!.isNotEmpty) &&
          (receipt.budgetCategoryId != null && receipt.budgetCategoryId!.isNotEmpty);
      if (hasBudgetLink) {
        final tx = Transaction(
          id: _uuid.v4(),
          budgetId: receipt.budgetId!,
          categoryId: receipt.budgetCategoryId!,
          type: 'expense',
          description: receipt.store,
          amount: receipt.amount,
          date: receipt.purchaseDate,
        );
        await BudgetService.createTransaction(tx);
      }
      // Schedule reminders locally
      await ReminderCoordinator.syncReceipt(receipt);
      return;
    }
    final synced = await _syncBudgetLink(receipt);
    final prepared = await ReminderCoordinator.syncReceipt(synced);
    await AppDatabase.put('receipts', prepared.id, prepared.toJson());
  }

  static Future<void> updateReceipt(Receipt receipt) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = ReceiptsRepo();
      final patch = <String, dynamic>{
        'store': receipt.store,
        'amount': receipt.amount,
        'currency': receipt.currency,
        'purchased_at': receipt.purchaseDate.toIso8601String(),
        'category': receipt.category,
        'notes': receipt.notes,
        'image_url': receipt.imageUrl,
        'budget_id': receipt.budgetId,
        'budget_category_id': receipt.budgetCategoryId,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await repo.update(receipt.id, patch);
      // Reschedule reminders locally
      final previous = await getReceipt(receipt.id);
      await ReminderCoordinator.syncReceipt(receipt, previous: previous);
      return;
    }
    final existing = await getReceipt(receipt.id);
    final synced = await _syncBudgetLink(receipt, previous: existing);
    final prepared = await ReminderCoordinator.syncReceipt(synced, previous: existing);
    await AppDatabase.put('receipts', prepared.id, prepared.toJson());
  }

  static Future<void> deleteReceipt(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final existing = await getReceipt(id);
      final repo = ReceiptsRepo();
      await repo.delete(id);
      if (existing?.imageUrl != null) {
        await DocumentStorage.deleteDocument(existing!.imageUrl);
      }
      if (existing != null) {
        await ReminderCoordinator.cancelReceipt(existing);
      }
      return;
    }
    final existing = await getReceipt(id);
    await AppDatabase.delete('receipts', id);
    if (existing?.budgetTransactionId != null) {
      await BudgetService.deleteTransaction(existing!.budgetTransactionId!);
    }
    if (existing?.imageUrl != null) {
      await DocumentStorage.deleteDocument(existing!.imageUrl);
    }
    if (existing != null) {
      await ReminderCoordinator.cancelReceipt(existing);
    }
    if (existing != null) {
      await AuditLogService.log(
        action: 'resource.delete',
        resourceType: 'receipt',
        resourceId: existing.id,
        actorUserId: existing.ownerId,
      );
    }
  }

  static Future<List<Receipt>> getReceiptsForBudget(String ownerId, String budgetId, {DateTime? month}) async {
    final receipts = await AppDatabase.findAll(
      'receipts',
      filter: Filter.and([
        Filter.equals('ownerId', ownerId),
        Filter.equals('budgetId', budgetId),
        Filter.equals('archived', 0),
      ]),
      sortOrders: [SortOrder('purchaseDate', false)],
    );
    final parsed = receipts.map((e) => Receipt.fromJson(e)).toList();
    if (month == null) return parsed;
    return parsed.where((r) => r.purchaseDate.year == month.year && r.purchaseDate.month == month.month).toList();
  }

  static Future<Receipt> _syncBudgetLink(Receipt receipt, {Receipt? previous}) async {
    final hasBudgetLink =
        (receipt.budgetId != null && receipt.budgetId!.isNotEmpty) &&
        (receipt.budgetCategoryId != null && receipt.budgetCategoryId!.isNotEmpty);
    final hadBudgetLink = previous?.budgetTransactionId != null;

    String? txId = receipt.budgetTransactionId ?? previous?.budgetTransactionId;

    if (hasBudgetLink) {
      txId ??= _uuid.v4();
      final transaction = Transaction(
        id: txId,
        budgetId: receipt.budgetId!,
        categoryId: receipt.budgetCategoryId!,
        type: 'expense',
        description: receipt.store,
        amount: receipt.amount,
        date: receipt.purchaseDate,
      );
      await BudgetService.createTransaction(transaction);
    }

    if (!hasBudgetLink && hadBudgetLink && previous?.budgetTransactionId != null) {
      await BudgetService.deleteTransaction(previous!.budgetTransactionId!);
      txId = null;
    }

    return receipt.copyWith(budgetTransactionId: txId);
  }
}

class GiftCardService {
  static Future<List<GiftCard>> getAllGiftCards(String userId, {String? email}) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = GiftCardsRepo();
      final rows = await repo.list();
      final cards = rows.map(SupaMappers.giftCard).toList();
      cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return cards;
    }
    final ownRecords = await AppDatabase.findAll(
      'giftcards',
      filter: Filter.equals('ownerId', userId),
    );
    final cards = ownRecords.map((e) => GiftCard.fromJson(e)).toList();

    final sharedIds = await SharingService.getSharedResourceIdsForUser(
      resourceType: 'giftcard',
      userId: userId,
      email: email,
    );
    for (final sharedId in sharedIds) {
      if (cards.any((c) => c.id == sharedId)) continue;
      final raw = await AppDatabase.getById('giftcards', sharedId);
      if (raw == null) continue;
      cards.add(GiftCard.fromJson(raw));
    }

    cards.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return cards;
  }

  static Future<GiftCard?> getGiftCard(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = GiftCardsRepo();
      try {
        final row = await repo.getById(id);
        return SupaMappers.giftCard(row);
      } catch (_) {
        return null;
      }
    }
    final cards = await AppDatabase.findAll(
      'giftcards',
      filter: Filter.equals('id', id),
    );
    return cards.isEmpty ? null : GiftCard.fromJson(cards.first);
  }

  static Future<void> createGiftCard(GiftCard card) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = GiftCardsRepo();
      await repo.create(
        brand: card.brand,
        initialBalance: card.initialBalance,
        currentBalance: card.currentBalance,
        currency: card.currency,
        category: card.category,
        purchaseAt: card.purchaseDate,
        expiresAt: card.expiresAt,
        notes: card.notes,
        imageUrl: card.imageUrl,
        cardNumber: card.cardNumber,
      );
      await ReminderCoordinator.syncGiftCard(card);
      return;
    }
    final prepared = await ReminderCoordinator.syncGiftCard(card);
    final data = prepared.toJson();
    if (prepared.pin != null && prepared.pin != 'ENCRYPTED') {
      await _secureStorage.write(key: 'giftcard_pin_${prepared.id}', value: prepared.pin!);
      data['pin'] = 'ENCRYPTED';
    }
    await AppDatabase.put('giftcards', prepared.id, data);
  }

  static Future<void> updateGiftCard(GiftCard card) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = GiftCardsRepo();
      final patch = <String, dynamic>{
        'brand': card.brand,
        'category': card.category,
        'purchase_at': card.purchaseDate?.toIso8601String(),
        'expires_at': card.expiresAt?.toIso8601String(),
        'card_number': card.cardNumber,
        'initial_balance': card.initialBalance,
        'current_balance': card.currentBalance,
        'currency': card.currency,
        'notes': card.notes,
        'image_url': card.imageUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await repo.update(card.id, patch);
      final existing = await getGiftCard(card.id);
      await ReminderCoordinator.syncGiftCard(card, previous: existing);
      return;
    }
    final existing = await getGiftCard(card.id);
    final prepared = await ReminderCoordinator.syncGiftCard(card, previous: existing);
    final data = prepared.toJson();
    if (prepared.pin != null && prepared.pin != 'ENCRYPTED') {
      await _secureStorage.write(key: 'giftcard_pin_${prepared.id}', value: prepared.pin!);
      data['pin'] = 'ENCRYPTED';
    }
    if (prepared.pin == null) {
      await _secureStorage.delete(key: 'giftcard_pin_${prepared.id}');
    }
    await AppDatabase.put('giftcards', prepared.id, data);
  }

  static Future<void> deleteGiftCard(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final existing = await getGiftCard(id);
      final repo = GiftCardsRepo();
      await repo.delete(id);
      await _secureStorage.delete(key: 'giftcard_pin_$id');
      if (existing != null) {
        if (existing.imageUrl != null) {
          await DocumentStorage.deleteDocument(existing.imageUrl);
        }
        for (final doc in existing.documents) {
          await DocumentStorage.deleteDocument(doc.url);
        }
        await ReminderCoordinator.cancelGiftCard(existing);
      }
      return;
    }
    final existing = await getGiftCard(id);
    await AppDatabase.delete('giftcards', id);
    await _secureStorage.delete(key: 'giftcard_pin_$id');
    if (existing != null) {
      if (existing.imageUrl != null) {
        await DocumentStorage.deleteDocument(existing.imageUrl);
      }
      for (final doc in existing.documents) {
        await DocumentStorage.deleteDocument(doc.url);
      }
    }
    if (existing != null) {
      await ReminderCoordinator.cancelGiftCard(existing);
    }
    if (existing != null) {
      await AuditLogService.log(
        action: 'resource.delete',
        resourceType: 'giftcard',
        resourceId: existing.id,
        actorUserId: existing.ownerId,
      );
    }
  }

  static Future<String?> revealPin({required User user, required String cardId}) async {
    if (!SensitiveAuth.isUnlocked(user.id)) {
      throw StateError('reauth_required');
    }
    return await _secureStorage.read(key: 'giftcard_pin_$cardId');
  }

  static Future<List<GiftCardTransaction>> getTransactions(String giftCardId) async {
    final txs = await AppDatabase.findAll(
      'giftcard_transactions',
      filter: Filter.equals('giftCardId', giftCardId),
      sortOrders: [SortOrder('date', false)],
    );
    return txs.map((e) => GiftCardTransaction.fromJson(e)).toList();
  }

  static Future<GiftCard> addTransaction(GiftCardTransaction tx, GiftCard card) async {
    await AppDatabase.put('giftcard_transactions', tx.id, tx.toJson());

    final storedSnapshot = await AppDatabase.getById('giftcards', card.id);
    final baselineCard = storedSnapshot != null ? GiftCard.fromJson(storedSnapshot) : card;

    final newBalance = (baselineCard.currentBalance - tx.amount).clamp(0.0, double.infinity);
    final now = DateTime.now();
    final expiresAt = baselineCard.expiresAt;
    String status;
    if (newBalance <= 0) {
      status = 'used';
    } else if (expiresAt != null && expiresAt.isBefore(now)) {
      status = 'expired';
    } else if (expiresAt != null && expiresAt.difference(now).inDays < 30) {
      status = 'expiring';
    } else {
      status = 'active';
    }

    final updatedCard = baselineCard.copyWith(
      currentBalance: newBalance,
      status: status,
    );

    final data = updatedCard.toJson();
    if (baselineCard.pin == 'ENCRYPTED') {
      data['pin'] = 'ENCRYPTED';
    }

    await AppDatabase.put('giftcards', card.id, data);
    return updatedCard;
  }
}

class BudgetService {
  static Future<List<Budget>> getAllBudgets(String userId, {String? email}) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetsRepo();
      final rows = await repo.list();
      final budgets = rows.map((row) {
        return Budget(
          id: row['id'] as String,
          ownerId: row['owner_id'] as String? ?? sbUser.id,
          name: row['name'] as String? ?? '',
          year: (row['year'] as int?) ?? DateTime.now().year,
          createdAt: SupaMappers.parseDate(row['created_at']) ?? DateTime.now(),
          updatedAt: SupaMappers.parseDate(row['updated_at']) ?? DateTime.now(),
        );
      }).toList();
      budgets.sort((a, b) => b.year.compareTo(a.year));
      return budgets;
    }

    final ownRecords = await AppDatabase.findAll(
      'budgets',
      filter: Filter.equals('ownerId', userId),
    );
    final budgets = ownRecords.map((e) => Budget.fromJson(e)).toList();

    final sharedIds = await SharingService.getSharedResourceIdsForUser(
      resourceType: 'budget',
      userId: userId,
      email: email,
    );
    for (final sharedId in sharedIds) {
      if (budgets.any((b) => b.id == sharedId)) continue;
      final raw = await AppDatabase.getById('budgets', sharedId);
      if (raw == null) continue;
      budgets.add(Budget.fromJson(raw));
    }

    budgets.sort((a, b) => b.year.compareTo(a.year));
    return budgets;
  }

  static Future<Budget?> getBudget(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetsRepo();
      final row = await repo.getById(id);
      if (row == null) return null;
      return Budget(
        id: row['id'] as String,
        ownerId: row['owner_id'] as String? ?? sbUser.id,
        name: row['name'] as String? ?? '',
        year: (row['year'] as int?) ?? DateTime.now().year,
        createdAt: SupaMappers.parseDate(row['created_at']) ?? DateTime.now(),
        updatedAt: SupaMappers.parseDate(row['updated_at']) ?? DateTime.now(),
      );
    }
    final budgets = await AppDatabase.findAll(
      'budgets',
      filter: Filter.equals('id', id),
    );
    return budgets.isEmpty ? null : Budget.fromJson(budgets.first);
  }

  static Future<void> createBudget(Budget budget) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetsRepo();
      await repo.create(id: budget.id, name: budget.name, year: budget.year);
      return;
    }
    await AppDatabase.put('budgets', budget.id, budget.toJson());
  }

  static Future<void> updateBudget(Budget budget) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetsRepo();
      await repo.update(budget.id, {
        'name': budget.name,
        'year': budget.year,
        'updated_at': DateTime.now().toIso8601String(),
      });
      return;
    }
    await AppDatabase.put('budgets', budget.id, budget.toJson());
  }

  static Future<void> deleteBudget(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetsRepo();
      await repo.delete(id);
      return;
    }
    await AppDatabase.delete('budgets', id);
    await AppDatabase.deleteWhere('budget_categories', Filter.equals('budgetId', id));
    await AppDatabase.deleteWhere('transactions', Filter.equals('budgetId', id));
    await AppDatabase.deleteWhere('budget_incomes', Filter.equals('budgetId', id));
  }

  static Future<List<BudgetCategory>> getCategories(String budgetId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      final rows = await repo.listCategories(budgetId);
      return rows.map(SupaMappers.budgetCategory).toList();
    }
    final cats = await AppDatabase.findAll(
      'budget_categories',
      filter: Filter.equals('budgetId', budgetId),
    );
    return cats.map((e) => BudgetCategory.fromJson(e)).toList();
  }

  static Future<void> createCategory(BudgetCategory cat) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      await repo.createCategory(budgetId: cat.budgetId, name: cat.name, limit: cat.limit);
      return;
    }
    await AppDatabase.put('budget_categories', cat.id, cat.toJson());
  }

  static Future<void> updateCategory(BudgetCategory cat) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      await repo.updateCategory(cat.id, {'name': cat.name, 'monthly_limit': cat.limit});
      return;
    }
    await AppDatabase.put('budget_categories', cat.id, cat.toJson());
  }

  static Future<void> deleteCategory(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      await repo.deleteCategory(id);
      return;
    }
    await AppDatabase.delete('budget_categories', id);
  }

  static Future<List<Transaction>> getTransactions(String budgetId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      final rows = await repo.listTransactions(budgetId);
      return rows.map(SupaMappers.transaction).toList();
    }
    final txs = await AppDatabase.findAll(
      'transactions',
      filter: Filter.equals('budgetId', budgetId),
      sortOrders: [SortOrder('date', false)],
    );
    return txs.map((e) => Transaction.fromJson(e)).toList();
  }

  static Future<void> createTransaction(Transaction tx) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      await repo.createTransaction(
        budgetId: tx.budgetId,
        categoryId: tx.categoryId,
        type: tx.type,
        description: tx.description,
        amount: tx.amount,
        date: tx.date,
      );
      return;
    }
    await AppDatabase.put('transactions', tx.id, tx.toJson());
  }

  static Future<void> deleteTransaction(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = BudgetRepo();
      await repo.deleteTransaction(id);
      return;
    }
    await AppDatabase.delete('transactions', id);
  }

  static Future<Map<String, double>> getCategorySpent(String budgetId, {DateTime? month}) async {
    final txs = await getTransactions(budgetId);
    final result = <String, double>{};
    Iterable<Transaction> filtered = txs;
    if (month != null) {
      filtered = filtered.where((t) => t.date.year == month.year && t.date.month == month.month);
    }
    for (final tx in filtered.where((t) => t.type == 'expense')) {
      result[tx.categoryId] = (result[tx.categoryId] ?? 0.0) + tx.amount;
    }
    return result;
  }

  static Future<List<BudgetIncome>> getIncomes(String budgetId) async {
    final entries = await AppDatabase.findAll(
      'budget_incomes',
      filter: Filter.equals('budgetId', budgetId),
      sortOrders: [SortOrder('createdAt', false)],
    );
    return entries.map((e) => BudgetIncome.fromJson(e)).toList();
  }

  static Future<void> createIncome(BudgetIncome income) async {
    await AppDatabase.put('budget_incomes', income.id, income.toJson());
  }

  static Future<void> updateIncome(BudgetIncome income) async {
    await AppDatabase.put('budget_incomes', income.id, income.toJson());
  }

  static Future<void> deleteIncome(String id) async {
    await AppDatabase.delete('budget_incomes', id);
  }

  static Future<double> getMonthlyIncomeTotal(String budgetId) async {
    final incomes = await getIncomes(budgetId);
    return incomes.fold<double>(0.0, (sum, income) => sum + income.monthlyAmount);
  }
}

class SplitService {
  static Future<List<SplitGroup>> getAllSplitGroups(String userId, {String? email}) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      final rows = await repo.listGroups();
      final groups = rows.map(SupaMappers.splitGroup).toList();
      groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return groups;
    }
    final ownRecords = await AppDatabase.findAll(
      'split_groups',
      filter: Filter.equals('creatorId', userId),
    );
    final groups = ownRecords.map((e) => SplitGroup.fromJson(e)).toList();

    final sharedIds = await SharingService.getSharedResourceIdsForUser(
      resourceType: 'split_group',
      userId: userId,
      email: email,
    );
    for (final sharedId in sharedIds) {
      if (groups.any((g) => g.id == sharedId)) continue;
      final raw = await AppDatabase.getById('split_groups', sharedId);
      if (raw == null) continue;
      groups.add(SplitGroup.fromJson(raw));
    }

    groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return groups;
  }

  static Future<SplitGroup?> getSplitGroup(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      // SplitsRepo has no getById; list and find
      final repo = SplitsRepo();
      final rows = await repo.listGroups();
      final match = rows.cast<Map>().firstWhere(
        (e) => e['id'] == id,
        orElse: () => {},
      );
      if (match.isEmpty) return null;
      return SupaMappers.splitGroup(Map<String, dynamic>.from(match as Map));
    }
    final groups = await AppDatabase.findAll(
      'split_groups',
      filter: Filter.equals('id', id),
    );
    return groups.isEmpty ? null : SplitGroup.fromJson(groups.first);
  }

  static Future<void> createSplitGroup(SplitGroup group) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.createGroup(title: group.title);
      return;
    }
    await AppDatabase.put('split_groups', group.id, group.toJson());
  }

  static Future<void> updateSplitGroup(SplitGroup group) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.updateGroup(group.id, {'title': group.title, 'status': group.status});
      return;
    }
    await AppDatabase.put('split_groups', group.id, group.toJson());
  }

  static Future<void> deleteSplitGroup(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final settlements = await getSettlements(id);
      for (final settlement in settlements) {
        await ReminderCoordinator.cancelSettlementReminder(settlement);
      }
      final repo = SplitsRepo();
      await repo.deleteGroup(id);
      return;
    }
    final settlements = await getSettlements(id);
    for (final settlement in settlements) {
      await ReminderCoordinator.cancelSettlementReminder(settlement);
    }
    await AppDatabase.delete('split_groups', id);
    await AppDatabase.deleteWhere('participants', Filter.equals('splitGroupId', id));
    await AppDatabase.deleteWhere('expenses', Filter.equals('splitGroupId', id));
    await AppDatabase.deleteWhere('settlements', Filter.equals('splitGroupId', id));
    await AppDatabase.deleteWhere('split_access_grants', Filter.equals('splitGroupId', id));
  }

  static Future<List<Participant>> getParticipants(String splitGroupId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      final rows = await repo.listParticipants(splitGroupId);
      return rows.map(SupaMappers.participant).toList();
    }
    final parts = await AppDatabase.findAll(
      'participants',
      filter: Filter.equals('splitGroupId', splitGroupId),
    );
    return parts.map((e) => Participant.fromJson(e)).toList();
  }

  static Future<void> createParticipant(Participant p) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.createParticipant(splitGroupId: p.splitGroupId, name: p.name, contact: p.contact, userId: p.userId);
      return;
    }
    await AppDatabase.put('participants', p.id, p.toJson());
  }

  static Future<void> updateParticipant(Participant p) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.updateParticipant(p.id, {'name': p.name, 'contact': p.contact, 'balance': p.balance, 'user_id': p.userId});
      return;
    }
    await AppDatabase.put('participants', p.id, p.toJson());
  }

  static Future<void> deleteParticipant(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.deleteParticipant(id);
      return;
    }
    await AppDatabase.delete('participants', id);
  }

  static Future<List<Expense>> getExpenses(String splitGroupId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      final rows = await repo.listExpenses(splitGroupId);
      return rows.map(SupaMappers.expense).toList();
    }
    final exps = await AppDatabase.findAll(
      'expenses',
      filter: Filter.equals('splitGroupId', splitGroupId),
      sortOrders: [SortOrder('createdAt', false)],
    );
    return exps.map((e) => Expense.fromJson(e)).toList();
  }

  static Future<void> createExpense(Expense e) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.createExpense(
        splitGroupId: e.splitGroupId,
        paidBy: e.paidBy,
        description: e.description,
        amount: e.amount,
        sharedWith: e.sharedWith,
      );
      await _recalculateBalances(e.splitGroupId);
      return;
    }
    await AppDatabase.put('expenses', e.id, e.toJson());
    await _recalculateBalances(e.splitGroupId);
  }

  static Future<void> deleteExpense(String id, String splitGroupId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      await repo.deleteExpense(id);
      await _recalculateBalances(splitGroupId);
      return;
    }
    await AppDatabase.delete('expenses', id);
    await _recalculateBalances(splitGroupId);
  }

  static Future<void> _recalculateBalances(String splitGroupId) async {
    final participants = await getParticipants(splitGroupId);
    final expenses = await getExpenses(splitGroupId);

    for (final p in participants) {
      p.balance = 0.0;
    }

    for (final expense in expenses) {
      final payer = participants.firstWhere((p) => p.id == expense.paidBy);
      final sharedCount = expense.sharedWith.length;
      final share = expense.amount / sharedCount;

      payer.balance += expense.amount;
      for (final sharedId in expense.sharedWith) {
        final shared = participants.firstWhere((p) => p.id == sharedId);
        shared.balance -= share;
      }
    }

    for (final p in participants) {
      await updateParticipant(p);
    }
  }

  static Future<List<Settlement>> getSettlements(String splitGroupId) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SplitsRepo();
      final rows = await repo.listSettlements(splitGroupId);
      return rows.map(SupaMappers.settlement).toList();
    }
    final setts = await AppDatabase.findAll(
      'settlements',
      filter: Filter.equals('splitGroupId', splitGroupId),
    );
    return setts.map((e) => Settlement.fromJson(e)).toList();
  }

  static Future<void> createSettlement(Settlement s) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final group = await getSplitGroup(s.splitGroupId);
      Settlement toPersist = s;
      if (group != null) {
        final participants = await getParticipants(s.splitGroupId);
        final debtor = _findParticipant(participants, s.payerId);
        final receiver = _findParticipant(participants, s.receiverId);
        if (debtor != null && receiver != null) {
          toPersist = await ReminderCoordinator.syncSettlementReminder(
            group: group,
            settlement: s,
            debtor: debtor,
            receiver: receiver,
          );
        }
      }
      final repo = SplitsRepo();
      await repo.createSettlement(
        splitGroupId: toPersist.splitGroupId,
        payerId: toPersist.payerId,
        receiverId: toPersist.receiverId,
        amount: toPersist.amount,
      );
      return;
    }
    final group = await getSplitGroup(s.splitGroupId);
    Settlement toPersist = s;
    if (group != null) {
      final participants = await getParticipants(s.splitGroupId);
      final debtor = _findParticipant(participants, s.payerId);
      final receiver = _findParticipant(participants, s.receiverId);
      if (debtor != null && receiver != null) {
        toPersist = await ReminderCoordinator.syncSettlementReminder(
          group: group,
          settlement: s,
          debtor: debtor,
          receiver: receiver,
        );
      }
    }
    await AppDatabase.put('settlements', toPersist.id, toPersist.toJson());
  }

  static Future<void> updateSettlement(Settlement s) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      // For Supabase, we update only fields; reminder scheduling stays local
      final group = await getSplitGroup(s.splitGroupId);
      final participants = await getParticipants(s.splitGroupId);
      final debtor = _findParticipant(participants, s.payerId);
      final receiver = _findParticipant(participants, s.receiverId);
      var toPersist = s;
      if (group != null && debtor != null && receiver != null) {
        toPersist = await ReminderCoordinator.syncSettlementReminder(
          group: group,
          settlement: s,
          debtor: debtor,
          receiver: receiver,
        );
      }
      final repo = SplitsRepo();
      final patch = <String, dynamic>{
        'status': toPersist.status,
        'settled_at': toPersist.settledAt?.toIso8601String(),
      };
      await repo.updateSettlement(toPersist.id, patch);
      return;
    }
    final existingRaw = await AppDatabase.getById('settlements', s.id);
    final previous = existingRaw != null ? Settlement.fromJson(existingRaw) : null;

    if (s.status == 'settled') {
      await ReminderCoordinator.cancelSettlementReminder(previous ?? s);
      final base = previous != null ? s.copyWith(reminderJobId: previous.reminderJobId) : s;
      final settled = base.copyWith(reminderJobId: null, settledAt: s.settledAt ?? DateTime.now());
      await AppDatabase.put('settlements', settled.id, settled.toJson());
      return;
    }

    final group = await getSplitGroup(s.splitGroupId);
    Settlement toPersist = previous != null ? s.copyWith(reminderJobId: previous.reminderJobId) : s;
    if (group != null) {
      final participants = await getParticipants(s.splitGroupId);
      final debtor = _findParticipant(participants, s.payerId);
      final receiver = _findParticipant(participants, s.receiverId);
      if (debtor != null && receiver != null) {
        toPersist = await ReminderCoordinator.syncSettlementReminder(
          group: group,
          settlement: toPersist,
          debtor: debtor,
          receiver: receiver,
        );
      }
    }
    await AppDatabase.put('settlements', toPersist.id, toPersist.toJson());
  }

  static Future<Settlement> toggleSettlementReminder({required Settlement settlement, required bool enable}) async {
    final existingRaw = await AppDatabase.getById('settlements', settlement.id);
    if (existingRaw == null) {
      throw StateError('Avräkningen finns inte längre.');
    }
    final current = Settlement.fromJson(existingRaw);
    if (current.status == 'settled') {
      return current;
    }

    if (!enable) {
      await ReminderCoordinator.cancelSettlementReminder(current);
      final cleared = current.copyWith(reminderJobId: null);
      await AppDatabase.put('settlements', cleared.id, cleared.toJson());
      return cleared;
    }

    final group = await getSplitGroup(current.splitGroupId);
    if (group == null) {
      return current;
    }
    final participants = await getParticipants(current.splitGroupId);
    final debtor = _findParticipant(participants, current.payerId);
    final receiver = _findParticipant(participants, current.receiverId);
    if (debtor == null || receiver == null) {
      return current;
    }

    final refreshed = await ReminderCoordinator.syncSettlementReminder(
      group: group,
      settlement: current.copyWith(reminderJobId: null),
      debtor: debtor,
      receiver: receiver,
    );
    await AppDatabase.put('settlements', refreshed.id, refreshed.toJson());
    return refreshed;
  }

  static Future<List<Settlement>> generateSettlements(String splitGroupId) async {
    final participants = await getParticipants(splitGroupId);
    final settlements = <Settlement>[];

    final debtors = participants.where((p) => p.balance < 0).toList();
    final creditors = participants.where((p) => p.balance > 0).toList();

    for (final debtor in debtors) {
      var remaining = -debtor.balance;
      for (final creditor in creditors) {
        if (remaining <= 0) break;
        if (creditor.balance <= 0) continue;

        final amount = remaining < creditor.balance ? remaining : creditor.balance;
        settlements.add(Settlement(id: _uuid.v4(), splitGroupId: splitGroupId, payerId: debtor.id, receiverId: creditor.id, amount: amount, createdAt: DateTime.now()));
        remaining -= amount;
        creditor.balance -= amount;
      }
    }

    for (final s in settlements) {
      await createSettlement(s);
    }

    return settlements;
  }

  static Future<List<SplitAccessGrant>> getAccessGrants(String splitGroupId) async {
    final records = await AppDatabase.findAll(
      'split_access_grants',
      filter: Filter.equals('splitGroupId', splitGroupId),
      sortOrders: [SortOrder('invitedAt', false)],
    );
    return records.map((e) => SplitAccessGrant.fromJson(e)).toList();
  }

  static Future<void> createAccessGrant(SplitAccessGrant grant) async {
    await AppDatabase.put('split_access_grants', grant.id, grant.toJson());
  }

  static Future<void> updateAccessGrant(SplitAccessGrant grant) async {
    await AppDatabase.put('split_access_grants', grant.id, grant.toJson());
  }

  static Future<void> deleteAccessGrant(String id) async {
    await AppDatabase.delete('split_access_grants', id);
  }

  static Participant? _findParticipant(List<Participant> participants, String id) {
    for (final participant in participants) {
      if (participant.id == id) return participant;
    }
    return null;
  }
}

class UserService {
  static Future<User?> getById(String userId) async {
    final raw = await AppDatabase.getById('users', userId);
    if (raw == null) return null;
    return User.fromJson(raw);
  }

  static Future<User> updateNotificationPrefs(String userId, NotificationPrefs prefs) async {
    final raw = await AppDatabase.getById('users', userId);
    if (raw == null) {
      throw StateError('Användare saknas: $userId');
    }
    final existing = User.fromJson(raw);
    final updated = existing.copyWith(notificationPrefs: prefs);
    await AppDatabase.put('users', userId, updated.toJson());
    return updated;
  }

  static Future<User> setLocale(String userId, String locale) async {
    final raw = await AppDatabase.getById('users', userId);
    if (raw == null) {
      throw StateError('Användare saknas: $userId');
    }
    final existing = User.fromJson(raw);
    final updated = existing.copyWith(locale: locale);
    await AppDatabase.put('users', userId, updated.toJson());
    return updated;
  }

  static Future<void> deleteAccount(String userId) async {
    // Delete all user-owned records across stores
    final storesWithOwner = <String, String>{
      'receipts': 'ownerId',
      'giftcards': 'ownerId',
      'budgets': 'ownerId',
      'autogiros': 'ownerId',
      'split_groups': 'creatorId',
      'scheduled_notifications': 'userId',
      'giftcard_transactions': 'giftCardId', // will be swept below by giftcards loop
    };

    // Receipts: also delete linked documents
    final receipts = await AppDatabase.findAll('receipts', filter: Filter.equals('ownerId', userId));
    for (final r in receipts) {
      final receipt = Receipt.fromJson(r);
      if (receipt.imageUrl != null) {
        await DocumentStorage.deleteDocument(receipt.imageUrl);
      }
      await AppDatabase.delete('receipts', receipt.id);
    }

    // Gift cards: delete documents and transactions
    final giftcards = await AppDatabase.findAll('giftcards', filter: Filter.equals('ownerId', userId));
    for (final raw in giftcards) {
      final card = GiftCard.fromJson(raw);
      for (final doc in card.documents) {
        await DocumentStorage.deleteDocument(doc.url);
      }
      final txs = await AppDatabase.findAll('giftcard_transactions', filter: Filter.equals('giftCardId', card.id));
      for (final tx in txs) {
        await AppDatabase.delete('giftcard_transactions', tx['id'] as String);
      }
      await _secureStorage.delete(key: 'giftcard_pin_${card.id}');
      await AppDatabase.delete('giftcards', card.id);
    }

    // Budgets and related data
    final budgets = await AppDatabase.findAll('budgets', filter: Filter.equals('ownerId', userId));
    for (final b in budgets) {
      final budgetId = b['id'] as String;
      final cats = await AppDatabase.findAll('budget_categories', filter: Filter.equals('budgetId', budgetId));
      for (final c in cats) {
        await AppDatabase.delete('budget_categories', c['id'] as String);
      }
      final txs = await AppDatabase.findAll('budget_transactions', filter: Filter.equals('budgetId', budgetId));
      for (final t in txs) {
        await AppDatabase.delete('budget_transactions', t['id'] as String);
      }
      await AppDatabase.delete('budgets', budgetId);
    }

    // Autogiro
    final giros = await AppDatabase.findAll('autogiros', filter: Filter.equals('ownerId', userId));
    for (final g in giros) {
      await AppDatabase.delete('autogiros', g['id'] as String);
    }

    // Sharing grants where user is owner or grantee
    final grants = await AppDatabase.findAll('share_grants');
    for (final raw in grants) {
      final principalType = raw['principalType'] as String? ?? 'email';
      final principal = raw['principal'] as String?;
      final createdBy = raw['createdBy'] as String?;
      if (createdBy == userId || (principalType == 'user' && principal == userId)) {
        await AppDatabase.delete('share_grants', raw['id'] as String);
      }
    }

    // Split access grants where user participated by id or email is unknown here; best effort cleanup skipped.

    // Finally, delete user record and password
    await AppDatabase.delete('users', userId);
    try {
      await _secureStorage.delete(key: AuthService._passwordKey(userId));
    } catch (_) {}
  }

  static Future<User> setDoNotTrack(String userId, bool doNotTrack) async {
    final raw = await AppDatabase.getById('users', userId);
    if (raw == null) {
      throw StateError('Användare saknas: $userId');
    }
    final existing = User.fromJson(raw);
    final updated = existing.copyWith(doNotTrack: doNotTrack);
    await AppDatabase.put('users', userId, updated.toJson());
    return updated;
  }
}

class AuditLogService {
  static const String _store = 'audit_log';

  static Future<void> log({
    required String action,
    required String resourceType,
    required String resourceId,
    required String actorUserId,
    Map<String, dynamic>? details,
  }) async {
    final entry = {
      'id': _uuid.v4(),
      'at': DateTime.now().toIso8601String(),
      'action': action,
      'resourceType': resourceType,
      'resourceId': resourceId,
      'actor': actorUserId,
      'details': details,
    };
    await AppDatabase.put(_store, entry['id'] as String, entry);
  }

  static Future<List<Map<String, dynamic>>> list({int limit = 100}) async {
    final records = await AppDatabase.findAll(
      _store,
      sortOrders: [SortOrder('at', false)],
    );
    return records.take(limit).toList();
  }
}

class SharingService {
  static const String _grantStore = 'share_grants';

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static Future<ShareAccess> getAccessForUser({
    required String resourceType,
    required String resourceId,
    required User user,
    String? ownerId,
  }) async {
    final resolvedOwnerId = ownerId ?? await _resolveOwnerId(resourceType, resourceId);
    if (resolvedOwnerId != null && resolvedOwnerId == user.id) {
      return const ShareAccess(effectiveRole: ShareRoles.owner, isOwner: true, allowExport: true);
    }

    final grants = await listGrants(resourceType: resourceType, resourceId: resourceId);
    ShareGrant? matchingGrant;
    for (final grant in grants) {
      if (grant.principalType == 'user' && grant.principal == user.id) {
        matchingGrant = grant;
        break;
      }
      if (grant.principalType == 'email' && grant.principal == _normalizeEmail(user.email)) {
        matchingGrant = grant;
        break;
      }
    }

    if (matchingGrant == null) {
      return const ShareAccess(effectiveRole: 'none');
    }

    if (matchingGrant.principalType == 'email') {
      matchingGrant = await _promoteEmailGrantToUser(grant: matchingGrant, user: user);
    }

    if (matchingGrant.status != 'active') {
      return ShareAccess(
        effectiveRole: matchingGrant.role,
        allowExport: matchingGrant.allowExport,
      );
    }

    final grantAllowsExport = matchingGrant.allowExport || matchingGrant.role == ShareRoles.editor;
    return ShareAccess(
      effectiveRole: matchingGrant.role,
      allowExport: grantAllowsExport,
    );
  }

  static Future<List<ShareGrant>> listGrants({
    required String resourceType,
    required String resourceId,
  }) async {
    if (resourceType == 'split_group') {
      final splitGrants = await SplitService.getAccessGrants(resourceId);
      final ownerId = await _resolveOwnerId(resourceType, resourceId) ?? '';
      return splitGrants
          .map(
            (grant) => ShareGrant(
              id: grant.id,
              resourceType: resourceType,
              resourceId: resourceId,
              principalType: grant.principal.contains('@') ? 'email' : 'user',
              principal: grant.principal,
              role: grant.role,
              status: grant.status,
              createdBy: ownerId,
              createdAt: grant.invitedAt,
              respondedAt: grant.respondedAt,
              updatedAt: grant.respondedAt,
              allowExport: grant.allowExport,
            ),
          )
          .toList();
    }

    final records = await AppDatabase.findAll(
      _grantStore,
      filter: Filter.and([
        Filter.equals('resourceType', resourceType),
        Filter.equals('resourceId', resourceId),
      ]),
      sortOrders: [SortOrder('createdAt')],
    );
    return records.map((raw) => ShareGrant.fromJson(raw)).toList();
  }

  static Future<ShareGrant> invite({
    required String resourceType,
    required String resourceId,
    required User fromUser,
    required String email,
    String role = ShareRoles.viewer,
    bool allowExport = false,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail == _normalizeEmail(fromUser.email)) {
      throw StateError('Du kan inte bjuda in dig själv.');
    }

    final now = DateTime.now();
    final principalResolution = await _resolvePrincipal(normalizedEmail);

    final existing = await _findExistingGrant(
      resourceType: resourceType,
      resourceId: resourceId,
      principalType: principalResolution.type,
      principal: principalResolution.value,
    );

    if (existing != null && !existing.isRevoked) {
      throw StateError('Användaren har redan åtkomst.');
    }

    if (resourceType == 'split_group') {
      final grant = SplitAccessGrant(
        id: _uuid.v4(),
        splitGroupId: resourceId,
        principal: principalResolution.value,
        role: role,
        status: principalResolution.isExistingUser ? 'accepted' : 'pending',
        invitedAt: now,
        respondedAt: principalResolution.isExistingUser ? now : null,
        allowExport: allowExport || role == ShareRoles.editor,
      );
      await SplitService.createAccessGrant(grant);
      await AuditLogService.log(
        action: 'share_invite',
        resourceType: resourceType,
        resourceId: resourceId,
        actorUserId: fromUser.id,
        details: {
          'principal': principalResolution.value,
          'role': role,
          'allowExport': allowExport || role == ShareRoles.editor,
        },
      );
      await NotificationService.trackEvent('share_invite_sent', {
        'resourceType': resourceType,
        'resourceId': resourceId,
        'principalType': principalResolution.type,
        'role': role,
      });
      return ShareGrant(
        id: grant.id,
        resourceType: resourceType,
        resourceId: resourceId,
        principalType: grant.principal.contains('@') ? 'email' : 'user',
        principal: grant.principal,
        role: grant.role,
        status: grant.status,
        createdBy: fromUser.id,
        createdAt: grant.invitedAt,
        respondedAt: grant.respondedAt,
        allowExport: grant.allowExport,
      );
    }

    final newGrant = ShareGrant(
      id: _uuid.v4(),
      resourceType: resourceType,
      resourceId: resourceId,
      principalType: principalResolution.type,
      principal: principalResolution.value,
      role: role,
      status: principalResolution.isExistingUser ? 'active' : 'pending',
      createdBy: fromUser.id,
      createdAt: now,
      respondedAt: principalResolution.isExistingUser ? now : null,
      allowExport: allowExport || role == ShareRoles.editor,
    );

    await AppDatabase.put(_grantStore, newGrant.id, newGrant.toJson());
    await AuditLogService.log(
      action: 'share_invite',
      resourceType: resourceType,
      resourceId: resourceId,
      actorUserId: fromUser.id,
      details: {
        'principalType': principalResolution.type,
        'principal': principalResolution.value,
        'role': role,
        'allowExport': newGrant.allowExport,
      },
    );
    await NotificationService.trackEvent('share_invite_sent', {
      'resourceType': resourceType,
      'resourceId': resourceId,
      'principalType': principalResolution.type,
      'role': role,
    });
    return newGrant;
  }

  static Future<ShareGrant> updateRole({
    required ShareGrant grant,
    required String role,
    User? actor,
  }) async {
    if (grant.role == role) {
      return grant;
    }
    final now = DateTime.now();

    if (grant.resourceType == 'split_group') {
      final splitGrant = await _findSplitGrant(grant.id);
      if (splitGrant == null) {
        throw StateError('Åtkomstposten finns inte längre.');
      }
      final updatedSplit = splitGrant.copyWith(role: role, respondedAt: splitGrant.respondedAt);
      await SplitService.updateAccessGrant(updatedSplit);
      await AuditLogService.log(
        action: 'share_role_updated',
        resourceType: grant.resourceType,
        resourceId: grant.resourceId,
        actorUserId: actor?.id ?? grant.createdBy,
        details: {'role': role},
      );
      final updatedGrant = grant.copyWith(role: role, updatedAt: now);
      await NotificationService.trackEvent('share_role_updated', {
        'resourceType': grant.resourceType,
        'resourceId': grant.resourceId,
        'role': role,
      });
      return updatedGrant;
    }

    final updated = grant.copyWith(role: role, updatedAt: now);
    await AppDatabase.put(_grantStore, updated.id, updated.toJson());
    await AuditLogService.log(
      action: 'share_role_updated',
      resourceType: grant.resourceType,
      resourceId: grant.resourceId,
      actorUserId: actor?.id ?? grant.createdBy,
      details: {'role': role},
    );
    await NotificationService.trackEvent('share_role_updated', {
      'resourceType': grant.resourceType,
      'resourceId': grant.resourceId,
      'role': role,
    });
    return updated;
  }

  static Future<ShareGrant> setAllowExport({
    required ShareGrant grant,
    required bool allowExport,
    User? actor,
  }) async {
    final now = DateTime.now();

    if (grant.resourceType == 'split_group') {
      final splitGrant = await _findSplitGrant(grant.id);
      if (splitGrant == null) {
        throw StateError('Åtkomstposten finns inte längre.');
      }
      final updatedSplit = splitGrant.copyWith(allowExport: allowExport);
      await SplitService.updateAccessGrant(updatedSplit);
      await AuditLogService.log(
        action: 'share_export_updated',
        resourceType: grant.resourceType,
        resourceId: grant.resourceId,
        actorUserId: actor?.id ?? grant.createdBy,
        details: {'allowExport': allowExport},
      );
      final updatedGrant = grant.copyWith(allowExport: allowExport, updatedAt: now);
      await NotificationService.trackEvent('share_export_updated', {
        'resourceType': grant.resourceType,
        'resourceId': grant.resourceId,
        'allowExport': allowExport,
      });
      return updatedGrant;
    }

    final updated = grant.copyWith(allowExport: allowExport, updatedAt: now);
    await AppDatabase.put(_grantStore, updated.id, updated.toJson());
    await AuditLogService.log(
      action: 'share_export_updated',
      resourceType: grant.resourceType,
      resourceId: grant.resourceId,
      actorUserId: actor?.id ?? grant.createdBy,
      details: {'allowExport': allowExport},
    );
    await NotificationService.trackEvent('share_export_updated', {
      'resourceType': grant.resourceType,
      'resourceId': grant.resourceId,
      'allowExport': allowExport,
    });
    return updated;
  }

  static Future<ShareGrant> revoke(ShareGrant grant, {User? actor}) async {
    final now = DateTime.now();

    if (grant.resourceType == 'split_group') {
      final splitGrant = await _findSplitGrant(grant.id);
      if (splitGrant != null) {
        await SplitService.updateAccessGrant(splitGrant.copyWith(status: 'revoked', respondedAt: now));
      }
      await AuditLogService.log(
        action: 'share_revoked',
        resourceType: grant.resourceType,
        resourceId: grant.resourceId,
        actorUserId: actor?.id ?? grant.createdBy,
      );
      await NotificationService.trackEvent('share_revoked', {
        'resourceType': grant.resourceType,
        'resourceId': grant.resourceId,
      });
      return grant.copyWith(status: 'revoked', updatedAt: now, respondedAt: now);
    }

    final updated = grant.copyWith(status: 'revoked', updatedAt: now, respondedAt: now);
    await AppDatabase.put(_grantStore, updated.id, updated.toJson());
    await AuditLogService.log(
      action: 'share_revoked',
      resourceType: grant.resourceType,
      resourceId: grant.resourceId,
      actorUserId: actor?.id ?? grant.createdBy,
    );
    await NotificationService.trackEvent('share_revoked', {
      'resourceType': grant.resourceType,
      'resourceId': grant.resourceId,
    });
    return updated;
  }

  static Future<String?> getOwnerEmail({
    required String resourceType,
    required String resourceId,
  }) async {
    final ownerId = await _resolveOwnerId(resourceType, resourceId);
    if (ownerId == null) return null;
    final owner = await UserService.getById(ownerId);
    return owner?.email;
  }

  static Future<String> resolvePrincipalLabel(ShareGrant grant) async {
    if (grant.principalType == 'user') {
      final user = await UserService.getById(grant.principal);
      if (user != null) {
        return user.email;
      }
    }
    return grant.principal;
  }

  static Future<List<String>> getSharedResourceIdsForUser({
    required String resourceType,
    required String userId,
    String? email,
  }) async {
    final normalizedEmail = email != null ? _normalizeEmail(email) : null;

    if (resourceType == 'split_group') {
      final grants = await AppDatabase.findAll('split_access_grants');
      final matching = grants.where((raw) {
        if (raw['status'] != 'accepted') return false;
        final principal = raw['principal'] as String?;
        if (principal == null) return false;
        if (principal == userId) return true;
        if (normalizedEmail != null && principal == normalizedEmail) return true;
        return false;
      }).map((raw) => raw['splitGroupId'] as String).toSet();
      return matching.toList();
    }

    final grants = await AppDatabase.findAll(
      _grantStore,
      filter: Filter.and([
        Filter.equals('resourceType', resourceType),
        Filter.equals('status', 'active'),
      ]),
    );

    final matching = grants.where((raw) {
      final principalType = raw['principalType'] as String? ?? 'email';
      final principal = raw['principal'] as String?;
      if (principal == null) return false;
      if (principalType == 'user') {
        return principal == userId;
      }
      if (normalizedEmail == null) return false;
      return principal == normalizedEmail;
    }).map((raw) => raw['resourceId'] as String).toSet();

    return matching.toList();
  }

  static Future<String?> _resolveOwnerId(String resourceType, String resourceId) async {
    switch (resourceType) {
      case 'receipt':
        final rawReceipt = await AppDatabase.getById('receipts', resourceId);
        return rawReceipt?['ownerId'] as String?;
      case 'giftcard':
        final rawCard = await AppDatabase.getById('giftcards', resourceId);
        return rawCard?['ownerId'] as String?;
      case 'budget':
        final rawBudget = await AppDatabase.getById('budgets', resourceId);
        return rawBudget?['ownerId'] as String?;
      case 'autogiro':
        final rawAutoGiro = await AppDatabase.getById('autogiros', resourceId);
        return rawAutoGiro?['ownerId'] as String?;
      case 'split_group':
        final rawSplit = await AppDatabase.getById('split_groups', resourceId);
        return rawSplit?['creatorId'] as String?;
      default:
        return null;
    }
  }

  static Future<_PrincipalResolution> _resolvePrincipal(String normalizedEmail) async {
    var userRecord = await AppDatabase.findAll(
      'users',
      filter: Filter.equals('email', normalizedEmail),
    );
    if (userRecord.isEmpty) {
      final allUsers = await AppDatabase.findAll('users');
      for (final raw in allUsers) {
        final email = (raw['email'] as String?)?.toLowerCase();
        if (email == normalizedEmail) {
          userRecord = [raw];
          break;
        }
      }
    }
    if (userRecord.isNotEmpty) {
      final userId = userRecord.first['id'] as String?;
      if (userId != null) {
        return _PrincipalResolution(type: 'user', value: userId, isExistingUser: true);
      }
    }
    return _PrincipalResolution(type: 'email', value: normalizedEmail, isExistingUser: false);
  }

  static Future<ShareGrant?> _findExistingGrant({
    required String resourceType,
    required String resourceId,
    required String principalType,
    required String principal,
  }) async {
    if (resourceType == 'split_group') {
      final grants = await SplitService.getAccessGrants(resourceId);
      for (final grant in grants) {
        final isUser = !grant.principal.contains('@');
        final type = isUser ? 'user' : 'email';
        if (type == principalType && grant.principal == principal) {
          return ShareGrant(
            id: grant.id,
            resourceType: resourceType,
            resourceId: resourceId,
            principalType: type,
            principal: grant.principal,
            role: grant.role,
            status: grant.status,
            createdBy: '',
            createdAt: grant.invitedAt,
            respondedAt: grant.respondedAt,
            allowExport: grant.allowExport,
          );
        }
      }
      return null;
    }

    final records = await AppDatabase.findAll(
      _grantStore,
      filter: Filter.and([
        Filter.equals('resourceType', resourceType),
        Filter.equals('resourceId', resourceId),
        Filter.equals('principalType', principalType),
        Filter.equals('principal', principal),
      ]),
    );
    if (records.isEmpty) {
      return null;
    }
    return ShareGrant.fromJson(records.first);
  }

  static Future<ShareGrant> _promoteEmailGrantToUser({
    required ShareGrant grant,
    required User user,
  }) async {
    final now = DateTime.now();
    if (grant.resourceType == 'split_group') {
      final splitGrant = await _findSplitGrant(grant.id);
      if (splitGrant == null) {
        return grant;
      }
      final updatedSplit = splitGrant.copyWith(
        principal: user.id,
        status: 'accepted',
        respondedAt: now,
        allowExport: splitGrant.allowExport,
      );
      await SplitService.updateAccessGrant(updatedSplit);
      await NotificationService.trackEvent('share_invite_accepted', {
        'resourceType': grant.resourceType,
        'resourceId': grant.resourceId,
      });
      await AuditLogService.log(
        action: 'share_invite_accepted',
        resourceType: grant.resourceType,
        resourceId: grant.resourceId,
        actorUserId: user.id,
        details: {'principal': user.id},
      );
      return grant.copyWith(
        principalType: 'user',
        principal: user.id,
        status: 'active',
        respondedAt: now,
        updatedAt: now,
        allowExport: updatedSplit.allowExport,
      );
    }

    final updated = grant.copyWith(
      principalType: 'user',
      principal: user.id,
      status: 'active',
      respondedAt: now,
      updatedAt: now,
      allowExport: grant.allowExport,
    );
    await AppDatabase.put(_grantStore, updated.id, updated.toJson());
    await NotificationService.trackEvent('share_invite_accepted', {
      'resourceType': grant.resourceType,
      'resourceId': grant.resourceId,
    });
    await AuditLogService.log(
      action: 'share_invite_accepted',
      resourceType: grant.resourceType,
      resourceId: grant.resourceId,
      actorUserId: user.id,
      details: {'principal': user.id},
    );
    return updated;
  }

  static Future<SplitAccessGrant?> _findSplitGrant(String grantId) async {
    final raw = await AppDatabase.getById('split_access_grants', grantId);
    if (raw == null) return null;
    return SplitAccessGrant.fromJson(raw);
  }
}

class _PrincipalResolution {
  final String type;
  final String value;
  final bool isExistingUser;

  const _PrincipalResolution({required this.type, required this.value, required this.isExistingUser});
}

class AutoGiroService {
  static Future<List<AutoGiro>> getAllAutoGiros(String userId, {String? email}) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SubscriptionsRepo();
      final rows = await repo.list();
      final giros = rows.map(SupaMappers.subscription).toList();
      giros.sort((a, b) => a.nextChargeAt.compareTo(b.nextChargeAt));
      return giros;
    }
    final ownRecords = await AppDatabase.findAll(
      'autogiros',
      filter: Filter.equals('ownerId', userId),
    );
    final giros = ownRecords.map((e) => AutoGiro.fromJson(e)).toList();

    final sharedIds = await SharingService.getSharedResourceIdsForUser(
      resourceType: 'autogiro',
      userId: userId,
      email: email,
    );
    for (final sharedId in sharedIds) {
      if (giros.any((g) => g.id == sharedId)) continue;
      final raw = await AppDatabase.getById('autogiros', sharedId);
      if (raw == null) continue;
      giros.add(AutoGiro.fromJson(raw));
    }

    giros.sort((a, b) => a.nextChargeAt.compareTo(b.nextChargeAt));
    return giros;
  }

  static Future<AutoGiro?> getAutoGiro(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SubscriptionsRepo();
      try {
        final row = await repo.getById(id);
        return SupaMappers.subscription(row);
      } catch (_) {
        return null;
      }
    }
    final giros = await AppDatabase.findAll(
      'autogiros',
      filter: Filter.equals('id', id),
    );
    return giros.isEmpty ? null : AutoGiro.fromJson(giros.first);
  }

  static Future<void> createAutoGiro(AutoGiro giro) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SubscriptionsRepo();
      await repo.create(
        serviceName: giro.serviceName,
        category: giro.category,
        amountPerPeriod: giro.amountPerPeriod,
        currency: giro.currency,
        billingInterval: giro.billingInterval,
        paymentMethod: giro.paymentMethod,
        nextChargeAt: giro.nextChargeAt,
        startDate: giro.startDate,
        bindingMonths: giro.bindingMonths,
        trialEnabled: giro.trialEnabled,
        trialEndsAt: giro.trialEndsAt,
        trialPrice: giro.trialPrice,
        reminderBeforeChargeDays: giro.reminderBeforeChargeDays,
        reminderOnTrialEnd: giro.reminderOnTrialEnd,
        budgetCategoryId: giro.budgetCategoryId,
        notes: giro.notes,
        portalUrl: giro.portalUrl,
        status: giro.status,
      );
      await ReminderCoordinator.syncAutoGiro(giro);
      return;
    }
    final prepared = await ReminderCoordinator.syncAutoGiro(giro);
    await AppDatabase.put('autogiros', prepared.id, prepared.toJson());
  }

  static Future<void> updateAutoGiro(AutoGiro giro) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final repo = SubscriptionsRepo();
      final patch = <String, dynamic>{
        'service_name': giro.serviceName,
        'category': giro.category,
        'amount_per_period': giro.amountPerPeriod,
        'currency': giro.currency,
        'billing_interval': giro.billingInterval,
        'payment_method': giro.paymentMethod,
        'next_charge_at': giro.nextChargeAt.toIso8601String(),
        'start_date': giro.startDate.toIso8601String(),
        'binding_months': giro.bindingMonths,
        'trial_enabled': giro.trialEnabled,
        'trial_ends_at': giro.trialEndsAt?.toIso8601String(),
        'trial_price': giro.trialPrice,
        'reminder_before_charge_days': giro.reminderBeforeChargeDays.join(','),
        'reminder_on_trial_end': giro.reminderOnTrialEnd,
        'budget_category_id': giro.budgetCategoryId,
        'notes': giro.notes,
        'portal_url': giro.portalUrl,
        'status': giro.status,
        'updated_at': DateTime.now().toIso8601String(),
      };
      await repo.update(giro.id, patch);
      final existing = await getAutoGiro(giro.id);
      await ReminderCoordinator.syncAutoGiro(giro, previous: existing);
      return;
    }
    final existing = await getAutoGiro(giro.id);
    final prepared = await ReminderCoordinator.syncAutoGiro(giro, previous: existing);
    await AppDatabase.put('autogiros', prepared.id, prepared.toJson());
  }

  static Future<void> deleteAutoGiro(String id) async {
    final sbUser = SupabaseAuthAdapter.currentAppUserSync();
    if (sbUser != null) {
      final existing = await getAutoGiro(id);
      final repo = SubscriptionsRepo();
      await repo.delete(id);
      if (existing != null) {
        await ReminderCoordinator.cancelAutoGiro(existing);
      }
      return;
    }
    final existing = await getAutoGiro(id);
    await AppDatabase.delete('autogiros', id);
    if (existing != null) {
      await ReminderCoordinator.cancelAutoGiro(existing);
    }
    if (existing != null) {
      await AuditLogService.log(
        action: 'resource.delete',
        resourceType: 'autogiro',
        resourceId: existing.id,
        actorUserId: existing.ownerId,
      );
    }
  }

  static Future<void> advanceCharge(AutoGiro giro) async {
    DateTime next = giro.nextChargeAt;
    switch (giro.billingInterval) {
      case 'weekly':
        next = next.add(const Duration(days: 7));
        break;
      case 'monthly':
        next = DateTime(next.year, next.month + 1, next.day);
        break;
      case 'quarterly':
        next = DateTime(next.year, next.month + 3, next.day);
        break;
      case 'yearly':
        next = DateTime(next.year + 1, next.month, next.day);
        break;
    }

    final updated = giro.copyWith(nextChargeAt: next);
    await updateAutoGiro(updated);

    if (giro.budgetCategoryId != null) {
      final tx = Transaction(id: _uuid.v4(), budgetId: '', categoryId: giro.budgetCategoryId!, type: 'expense', description: giro.serviceName, amount: giro.amountPerPeriod, date: DateTime.now());
      await BudgetService.createTransaction(tx);
    }
  }
}

class SeedService {
  static Future<void> seedData(User currentUser) async {
    // ignore: avoid_print
    print('[SEED] start for user ${currentUser.email}');
    await _seedReceipts(currentUser.id);
    // ignore: avoid_print
    print('[SEED] receipts done');
    await _seedGiftCards(currentUser.id);
    // ignore: avoid_print
    print('[SEED] giftcards done');
    await _seedBudget(currentUser.id);
    // ignore: avoid_print
    print('[SEED] budget done');
    await _seedSplitGroup(currentUser.id);
    // ignore: avoid_print
    print('[SEED] split group done');
    await _seedAutoGiros(currentUser.id);
    // ignore: avoid_print
    print('[SEED] autogiros done');
    await _seedSharing(currentUser);
    // ignore: avoid_print
    print('[SEED] complete');
  }

  static Future<void> _seedReceipts(String ownerId) async {
    final receipts = [
      Receipt(id: _uuid.v4(), ownerId: ownerId, store: 'Elgiganten', purchaseDate: DateTime.now().subtract(const Duration(days: 10)), amount: 8990, category: 'Electronics', returnDeadline: DateTime.now().add(const Duration(days: 20)), warrantyExpires: DateTime.now().add(const Duration(days: 355)), remindersEnabled: true, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Receipt(id: _uuid.v4(), ownerId: ownerId, store: 'H&M', purchaseDate: DateTime.now().subtract(const Duration(days: 5)), amount: 599, category: 'Clothes', returnDeadline: DateTime.now().add(const Duration(days: 25)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Receipt(id: _uuid.v4(), ownerId: ownerId, store: 'IKEA', purchaseDate: DateTime.now().subtract(const Duration(days: 60)), amount: 2499, category: 'Home', exchangeDeadline: DateTime.now().subtract(const Duration(days: 5)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Receipt(id: _uuid.v4(), ownerId: ownerId, store: 'ICA Maxi', purchaseDate: DateTime.now().subtract(const Duration(days: 2)), amount: 437, category: 'Food', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
    for (final r in receipts) {
      await ReceiptService.createReceipt(r);
    }
  }

  static Future<void> _seedGiftCards(String ownerId) async {
    final cards = [
      GiftCard(id: _uuid.v4(), ownerId: ownerId, brand: 'Spotify', category: 'Entertainment', purchaseDate: DateTime.now().subtract(const Duration(days: 180)), expiresAt: DateTime.now().add(const Duration(days: 185)), cardNumber: '1234567890123456', initialBalance: 500, currentBalance: 150, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      GiftCard(id: _uuid.v4(), ownerId: ownerId, brand: 'Åhléns', category: 'Shopping', purchaseDate: DateTime.now().subtract(const Duration(days: 30)), expiresAt: DateTime.now().add(const Duration(days: 335)), cardNumber: '9876543210987654', initialBalance: 1000, currentBalance: 1000, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      GiftCard(id: _uuid.v4(), ownerId: ownerId, brand: 'Netflix', category: 'Entertainment', purchaseDate: DateTime.now().subtract(const Duration(days: 400)), expiresAt: DateTime.now().subtract(const Duration(days: 5)), cardNumber: '1111222233334444', initialBalance: 300, currentBalance: 50, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      GiftCard(id: _uuid.v4(), ownerId: ownerId, brand: 'Stadium', category: 'Sports', purchaseDate: DateTime.now().subtract(const Duration(days: 100)), expiresAt: DateTime.now().add(const Duration(days: 265)), cardNumber: '5555666677778888', initialBalance: 800, currentBalance: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
    for (final c in cards) {
      await GiftCardService.createGiftCard(c);
    }
  }

  static Future<void> _seedBudget(String ownerId) async {
    final budget = Budget(id: _uuid.v4(), ownerId: ownerId, name: 'Budget 2025', year: 2025, createdAt: DateTime.now(), updatedAt: DateTime.now());
    await BudgetService.createBudget(budget);

    final incomes = [
      BudgetIncome(id: _uuid.v4(), budgetId: budget.id, description: 'Lön', amount: 42000, frequency: 'monthly', createdAt: DateTime.now()),
      BudgetIncome(id: _uuid.v4(), budgetId: budget.id, description: 'Barnbidrag', amount: 1250, frequency: 'monthly', createdAt: DateTime.now()),
    ];
    for (final income in incomes) {
      await BudgetService.createIncome(income);
    }

    final categories = [
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Mat', limit: 5000),
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Transport', limit: 1500),
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Nöje', limit: 2000),
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Boende', limit: 8000),
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Kläder', limit: 1000),
      BudgetCategory(id: _uuid.v4(), budgetId: budget.id, name: 'Övrigt', limit: 1500),
    ];
    for (final c in categories) {
      await BudgetService.createCategory(c);
    }

    final txs = [
      Transaction(id: _uuid.v4(), budgetId: budget.id, categoryId: categories[0].id, type: 'expense', description: 'ICA', amount: 437, date: DateTime.now().subtract(const Duration(days: 2))),
      Transaction(id: _uuid.v4(), budgetId: budget.id, categoryId: categories[0].id, type: 'expense', description: 'Hemköp', amount: 312, date: DateTime.now().subtract(const Duration(days: 5))),
      Transaction(id: _uuid.v4(), budgetId: budget.id, categoryId: categories[2].id, type: 'expense', description: 'Spotify', amount: 119, date: DateTime.now().subtract(const Duration(days: 1))),
      Transaction(id: _uuid.v4(), budgetId: budget.id, categoryId: categories[4].id, type: 'expense', description: 'H&M', amount: 599, date: DateTime.now().subtract(const Duration(days: 5))),
    ];
    for (final t in txs) {
      await BudgetService.createTransaction(t);
    }
  }

  static Future<void> _seedSplitGroup(String ownerId) async {
    final group = SplitGroup(id: _uuid.v4(), title: 'Teneriffa-resa', creatorId: ownerId, createdAt: DateTime.now());
    await SplitService.createSplitGroup(group);

    final participants = [
      Participant(id: _uuid.v4(), splitGroupId: group.id, name: 'Anna', contact: 'anna@example.com'),
      Participant(id: _uuid.v4(), splitGroupId: group.id, name: 'Erik', contact: 'erik@example.com'),
      Participant(id: _uuid.v4(), splitGroupId: group.id, name: 'Sofia', contact: 'sofia@example.com'),
    ];
    for (final p in participants) {
      await SplitService.createParticipant(p);
    }

    final accessGrants = [
      SplitAccessGrant(id: _uuid.v4(), splitGroupId: group.id, principal: 'anna@example.com', role: 'editor', status: 'accepted', invitedAt: DateTime.now(), respondedAt: DateTime.now()),
      SplitAccessGrant(id: _uuid.v4(), splitGroupId: group.id, principal: 'sofia@example.com', role: 'viewer', status: 'pending', invitedAt: DateTime.now()),
    ];
    for (final grant in accessGrants) {
      await SplitService.createAccessGrant(grant);
    }

    final expenses = [
      Expense(id: _uuid.v4(), splitGroupId: group.id, paidBy: participants[0].id, description: 'Flyg', amount: 4500, sharedWith: [participants[0].id, participants[1].id, participants[2].id], createdAt: DateTime.now().subtract(const Duration(days: 10))),
      Expense(id: _uuid.v4(), splitGroupId: group.id, paidBy: participants[1].id, description: 'Hotell', amount: 6000, sharedWith: [participants[0].id, participants[1].id, participants[2].id], createdAt: DateTime.now().subtract(const Duration(days: 9))),
      Expense(id: _uuid.v4(), splitGroupId: group.id, paidBy: participants[2].id, description: 'Mat & dryck', amount: 2400, sharedWith: [participants[0].id, participants[1].id, participants[2].id], createdAt: DateTime.now().subtract(const Duration(days: 5))),
    ];
    for (final e in expenses) {
      await SplitService.createExpense(e);
    }
  }

  static Future<void> _seedAutoGiros(String ownerId) async {
    final giros = [
      AutoGiro(id: _uuid.v4(), ownerId: ownerId, serviceName: 'Spotify Premium', category: 'Entertainment', amountPerPeriod: 119, billingInterval: 'monthly', paymentMethod: 'card', nextChargeAt: DateTime.now().add(const Duration(days: 12)), startDate: DateTime.now().subtract(const Duration(days: 200)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
      AutoGiro(id: _uuid.v4(), ownerId: ownerId, serviceName: 'Netflix Standard', category: 'Entertainment', amountPerPeriod: 139, billingInterval: 'monthly', paymentMethod: 'card', nextChargeAt: DateTime.now().add(const Duration(days: 18)), startDate: DateTime.now().subtract(const Duration(days: 300)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
      AutoGiro(id: _uuid.v4(), ownerId: ownerId, serviceName: 'Gymkort', category: 'Health', amountPerPeriod: 399, billingInterval: 'monthly', paymentMethod: 'autogiro', nextChargeAt: DateTime.now().add(const Duration(days: 5)), startDate: DateTime.now().subtract(const Duration(days: 150)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
      AutoGiro(id: _uuid.v4(), ownerId: ownerId, serviceName: 'Disney+', category: 'Entertainment', amountPerPeriod: 99, billingInterval: 'monthly', paymentMethod: 'card', nextChargeAt: DateTime.now().add(const Duration(days: 25)), startDate: DateTime.now().subtract(const Duration(days: 90)), trialEnabled: true, trialEndsAt: DateTime.now().add(const Duration(days: 5)), trialPrice: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      AutoGiro(id: _uuid.v4(), ownerId: ownerId, serviceName: 'Hemförsäkring', category: 'Insurance', amountPerPeriod: 2400, billingInterval: 'yearly', paymentMethod: 'invoice', nextChargeAt: DateTime.now().add(const Duration(days: 180)), startDate: DateTime.now().subtract(const Duration(days: 185)), createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
    for (final g in giros) {
      await AutoGiroService.createAutoGiro(g);
    }
  }

  static Future<void> _seedSharing(User owner) async {
    final existingShares = await AppDatabase.findAll('share_grants');
    if (existingShares.isNotEmpty) {
      return;
    }

    try {
      final receipts = await ReceiptService.getAllReceipts(owner.id, email: owner.email);
      if (receipts.isNotEmpty) {
        await SharingService.invite(
          resourceType: 'receipt',
          resourceId: receipts.first.id,
          fromUser: owner,
          email: 'familj@fullkoll.dev',
          role: ShareRoles.viewer,
        );
      }

      final giftCards = await GiftCardService.getAllGiftCards(owner.id, email: owner.email);
      if (giftCards.isNotEmpty) {
        await SharingService.invite(
          resourceType: 'giftcard',
          resourceId: giftCards.first.id,
          fromUser: owner,
          email: 'partner@fullkoll.dev',
          role: ShareRoles.editor,
        );
      }

      final groups = await SplitService.getAllSplitGroups(owner.id, email: owner.email);
      if (groups.isNotEmpty) {
        await SharingService.invite(
          resourceType: 'split_group',
          resourceId: groups.first.id,
          fromUser: owner,
          email: 'resa@example.com',
          role: ShareRoles.viewer,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SEED] share seeding skipped: $e');
      }
    }
  }
}

class ExportService {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');
  static final DateFormat _timestampFormat = DateFormat('yyyyMMdd_HHmmss');
  static const ListToCsvConverter _csvConverter = ListToCsvConverter();

  static Future<void> exportReceiptsCsv({required User user}) async {
    final receipts = await ReceiptService.getAllReceipts(user.id, email: user.email);
    final allowed = await _filterExportable<Receipt>(
      user: user,
      items: receipts,
      resourceType: 'receipt',
      resolveOwnerId: (r) => r.ownerId,
      resolveResourceId: (r) => r.id,
    );

    if (allowed.isEmpty) {
      throw StateError('export_not_allowed');
    }

    final rows = <List<String>>[
      ['date', 'store', 'category', 'amount', 'currency', 'notes'],
      ...allowed.map((receipt) => [
            _formatDate(receipt.purchaseDate),
            receipt.store,
            receipt.category,
            receipt.amount.toStringAsFixed(2),
            receipt.currency,
            receipt.notes ?? '',
          ]),
    ];

    final csv = _csvConverter.convert(rows);
    await _deliverCsv(csv, 'kvitton');
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_csv', {'kind': 'receipts', 'rows': rows.length - 1});
  }

  static Future<void> exportGiftCardsCsv({required User user}) async {
    final cards = await GiftCardService.getAllGiftCards(user.id, email: user.email);
    final allowed = await _filterExportable<GiftCard>(
      user: user,
      items: cards,
      resourceType: 'giftcard',
      resolveOwnerId: (c) => c.ownerId,
      resolveResourceId: (c) => c.id,
    );

    if (allowed.isEmpty) {
      throw StateError('export_not_allowed');
    }

    final rows = <List<String>>[
      ['brand', 'cardNumber', 'currentBalance', 'expiresAt', 'status'],
      ...allowed.map((card) => [
            card.brand,
            card.maskedCardNumber,
            card.currentBalance.toStringAsFixed(2),
            card.expiresAt != null ? _formatDate(card.expiresAt!) : '',
            card.computedStatus,
          ]),
    ];

    final csv = _csvConverter.convert(rows);
    await _deliverCsv(csv, 'presentkort');
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_csv', {'kind': 'giftcards', 'rows': rows.length - 1});
  }

  static Future<void> exportBudgetTransactionsCsv({
    required User user,
    required Budget budget,
    required DateTime month,
  }) async {
    final access = await SharingService.getAccessForUser(
      resourceType: 'budget',
      resourceId: budget.id,
      user: user,
      ownerId: budget.ownerId,
    );
    if (!access.canExport) {
      throw StateError('export_not_allowed');
    }

    final transactions = await BudgetService.getTransactions(budget.id);
    final categories = await BudgetService.getCategories(budget.id);
    final categoryNames = {
      for (final c in categories) c.id: c.name,
    };

    final filtered = transactions.where((tx) => tx.date.year == month.year && tx.date.month == month.month);
    if (filtered.isEmpty) {
      throw StateError('export_no_rows');
    }

    final rows = <List<String>>[
      ['date', 'category', 'type', 'amount', 'description'],
      ...filtered.map((tx) => [
            _formatDate(tx.date),
            categoryNames[tx.categoryId] ?? tx.categoryId,
            tx.type,
            tx.amount.toStringAsFixed(2),
            tx.description ?? '',
          ]),
    ];

    final csv = _csvConverter.convert(rows);
    await _deliverCsv(csv, 'budget');
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_csv', {'kind': 'budget', 'rows': rows.length - 1});
  }

  static Future<void> exportAutogiroCsv({required User user}) async {
    final entries = await AutoGiroService.getAllAutoGiros(user.id, email: user.email);
    final allowed = await _filterExportable<AutoGiro>(
      user: user,
      items: entries,
      resourceType: 'autogiro',
      resolveOwnerId: (g) => g.ownerId,
      resolveResourceId: (g) => g.id,
    );

    if (allowed.isEmpty) {
      throw StateError('export_not_allowed');
    }

    final rows = <List<String>>[
      ['serviceName', 'amountPerPeriod', 'interval', 'nextChargeAt', 'status'],
      ...allowed.map((giro) => [
            giro.serviceName,
            giro.amountPerPeriod.toStringAsFixed(2),
            giro.billingInterval,
            _formatDate(giro.nextChargeAt),
            giro.status,
          ]),
    ];

    final csv = _csvConverter.convert(rows);
    await _deliverCsv(csv, 'autogiro');
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_csv', {'kind': 'autogiro', 'rows': rows.length - 1});
  }

  static Future<void> exportSplitOverviewCsv({required User user}) async {
    final groups = await SplitService.getAllSplitGroups(user.id, email: user.email);
    final allowed = await _filterExportable<SplitGroup>(
      user: user,
      items: groups,
      resourceType: 'split_group',
      resolveOwnerId: (g) => g.creatorId,
      resolveResourceId: (g) => g.id,
    );

    if (allowed.isEmpty) {
      throw StateError('export_not_allowed');
    }

    final rows = <List<String>>[
      ['title', 'participant', 'paidBy', 'description', 'amount'],
    ];

    for (final group in allowed) {
      final participants = await SplitService.getParticipants(group.id);
      final participantNames = {
        for (final p in participants) p.id: p.name,
      };
      final expenses = await SplitService.getExpenses(group.id);
      for (final expense in expenses) {
        final payerName = participantNames[expense.paidBy] ?? 'Okänt';
        final shareCount = expense.sharedWith.isEmpty ? 1 : expense.sharedWith.length;
        final shareAmount = expense.amount / shareCount;
        for (final participantId in expense.sharedWith) {
          final participantName = participantNames[participantId] ?? 'Okänt';
          rows.add([
            group.title,
            participantName,
            payerName,
            expense.description ?? '',
            shareAmount.toStringAsFixed(2),
          ]);
        }
      }
    }

    if (rows.length == 1) {
      throw StateError('export_no_rows');
    }

    final csv = _csvConverter.convert(rows);
    await _deliverCsv(csv, 'split');
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_csv', {'kind': 'split', 'rows': rows.length - 1});
  }

  static Future<void> exportReceiptPdf({required User user, required Receipt receipt}) async {
    final access = await SharingService.getAccessForUser(
      resourceType: 'receipt',
      resourceId: receipt.id,
      user: user,
      ownerId: receipt.ownerId,
    );
    if (!access.canExport) {
      throw StateError('export_not_allowed');
    }

    final grants = await SharingService.listGrants(resourceType: 'receipt', resourceId: receipt.id);
    final activeLabels = await _activeShareLabels(grants);
    final document = pw.Document();

    pw.ImageProvider? receiptImage;
    final stored = await DocumentStorage.fetchDocument(receipt.imageUrl);
    if (stored?.bytes != null && stored!.isImage) {
      receiptImage = pw.MemoryImage(stored.bytes);
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Kvitto', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text(receipt.store, style: const pw.TextStyle(fontSize: 20)),
              pw.SizedBox(height: 24),
              pw.Text('Belopp: ${receipt.amount.toStringAsFixed(2)} ${receipt.currency}', style: const pw.TextStyle(fontSize: 16)),
              pw.Text('Köpdatum: ${_formatDate(receipt.purchaseDate)}'),
              if (receipt.notes != null && receipt.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Text('Anteckningar', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text(receipt.notes!),
              ],
              pw.SizedBox(height: 16),
              _buildDeadlinesSection(receipt),
              pw.SizedBox(height: 16),
              pw.Text(
                activeLabels.isEmpty ? 'Delad med: Endast dig' : 'Delad med: ${activeLabels.join(', ')}',
                style: const pw.TextStyle(fontSize: 12),
              ),
              if (receiptImage != null) ...[
                pw.SizedBox(height: 24),
                pw.Text('Bilaga', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Container(
                  height: 180,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                  child: pw.Center(child: pw.Image(receiptImage, fit: pw.BoxFit.contain)),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final bytes = await document.save();
    await FileExportHelper.deliver(
      bytes: Uint8List.fromList(bytes),
      fileName: 'fullkoll_kvitto_${_timestampFormat.format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
    );
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_pdf', {'kind': 'receipt'});
  }

  static Future<void> exportBudgetReportPdf({
    required User user,
    required Budget budget,
    required DateTime month,
  }) async {
    final access = await SharingService.getAccessForUser(
      resourceType: 'budget',
      resourceId: budget.id,
      user: user,
      ownerId: budget.ownerId,
    );
    if (!access.canExport) {
      throw StateError('export_not_allowed');
    }

    final transactions = await BudgetService.getTransactions(budget.id);
    final categories = await BudgetService.getCategories(budget.id);
    final categoryNames = {
      for (final c in categories) c.id: c.name,
    };
    final monthTx = transactions.where((tx) => tx.date.year == month.year && tx.date.month == month.month).toList();
    final incomes = await BudgetService.getIncomes(budget.id);
    final totalIncome = incomes.fold<double>(0, (sum, income) => sum + income.monthlyAmount);
    final totalExpenses = monthTx.where((tx) => tx.type == 'expense').fold<double>(0, (sum, tx) => sum + tx.amount);
    final net = totalIncome - totalExpenses;

    final categoryTotals = <String, double>{};
    for (final tx in monthTx.where((tx) => tx.type == 'expense')) {
      final label = categoryNames[tx.categoryId] ?? tx.categoryId;
      categoryTotals[label] = (categoryTotals[label] ?? 0) + tx.amount;
    }

    final document = pw.Document();

    final tableData = <List<String>>[
      ['Datum', 'Kategori', 'Typ', 'Belopp', 'Beskrivning'],
      ...monthTx.map((tx) => [
            _formatDate(tx.date),
            categoryNames[tx.categoryId] ?? tx.categoryId,
            tx.type,
            tx.amount.toStringAsFixed(2),
            tx.description ?? '',
          ]),
    ];

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('Budgetrapport – ${budget.name}', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Period: ${DateFormat('MMMM yyyy', 'sv-SE').format(month)}'),
          pw.SizedBox(height: 24),
          _buildBudgetSummary(totalIncome: totalIncome, totalExpenses: totalExpenses, net: net),
          pw.SizedBox(height: 24),
          if (categoryTotals.isNotEmpty) ...[
            pw.Text('Utgifter per kategori', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 12),
            _buildCategoryChart(categoryTotals),
            pw.SizedBox(height: 24),
          ],
          pw.Text('Transaktioner', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            data: tableData,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );

    final bytes = await document.save();
    await FileExportHelper.deliver(
      bytes: Uint8List.fromList(bytes),
      fileName: 'fullkoll_budget_${_timestampFormat.format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
    );
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_pdf', {'kind': 'budget'});
  }

  static Future<List<String>> _activeShareLabels(List<ShareGrant> grants) async {
    final active = grants.where((grant) => grant.status == 'active');
    final labels = await Future.wait(active.map(SharingService.resolvePrincipalLabel));
    return labels;
  }

  static pw.Widget _buildDeadlinesSection(Receipt receipt) {
    final entries = <MapEntry<String, DateTime>>[];
    if (receipt.returnDeadline != null) entries.add(MapEntry('Returrätt', receipt.returnDeadline!));
    if (receipt.exchangeDeadline != null) entries.add(MapEntry('Bytesrätt', receipt.exchangeDeadline!));
    if (receipt.warrantyExpires != null) entries.add(MapEntry('Garanti', receipt.warrantyExpires!));
    if (receipt.refundDeadline != null) entries.add(MapEntry('Ångerfrist', receipt.refundDeadline!));

    if (entries.isEmpty) {
      return pw.Text('Inga deadlines registrerade.');
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: entries
          .map((entry) => pw.Text('${entry.key}: ${_formatDate(entry.value)}', style: const pw.TextStyle(fontSize: 12)))
          .toList(),
    );
  }

  static pw.Widget _buildBudgetSummary({
    required double totalIncome,
    required double totalExpenses,
    required double net,
  }) {
    String format(double value) => '${value.toStringAsFixed(0)} SEK';
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Sammanfattning', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 8),
        pw.Text('Inkomster denna månad: ${format(totalIncome)}'),
        pw.Text('Utgifter denna månad: ${format(totalExpenses)}'),
        pw.Text(net >= 0 ? 'Saldo: ${format(net)}' : 'Överdrag: ${format(net.abs())}'),
      ],
    );
  }

  static pw.Widget _buildCategoryChart(Map<String, double> totals) {
    final max = totals.values.fold<double>(0, (prev, value) => value > prev ? value : prev);
    if (max <= 0) {
      return pw.Text('Inga utgifter registrerade.');
    }

    final barWidth = 24.0;
    final barHeight = 160.0;

    return pw.Container(
      height: barHeight + 40,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: totals.entries.map((entry) {
          final height = (entry.value / max) * barHeight;
          return pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: barWidth,
                height: height,
                decoration: pw.BoxDecoration(color: PdfColors.deepPurple400, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              ),
              pw.SizedBox(height: 8),
              pw.Container(
                width: barWidth + 32,
                alignment: pw.Alignment.center,
                child: pw.Text(entry.key, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  static Future<List<T>> _filterExportable<T>({
    required User user,
    required List<T> items,
    required String resourceType,
    required String Function(T item) resolveOwnerId,
    required String Function(T item) resolveResourceId,
  }) async {
    final checks = await Future.wait(items.map((item) async {
      final access = await SharingService.getAccessForUser(
        resourceType: resourceType,
        resourceId: resolveResourceId(item),
        user: user,
        ownerId: resolveOwnerId(item),
      );
      return access.canExport ? item : null;
    }));
    return checks.whereType<T>().toList();
  }

  static String _formatDate(DateTime date) => _dateFormat.format(date.toLocal());

  static Future<void> _deliverCsv(String content, String key) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final fileName = 'fullkoll_${key}_${_timestampFormat.format(DateTime.now())}.csv';
    await FileExportHelper.deliver(bytes: bytes, fileName: fileName, mimeType: 'text/csv');
  }

  static Future<void> exportAllPdf({required User user}) async {
    // Build a consolidated PDF with key datasets
    final document = pw.Document();

    // Header page
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => pw.Padding(
          padding: const pw.EdgeInsets.all(32),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Full Koll – Dataexport', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Text('Skapad: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
              pw.SizedBox(height: 16),
              pw.Text('Denna PDF innehåller en översikt av dina data i Full Koll.'),
            ],
          ),
        ),
      ),
    );

    // Receipts table
    final receipts = await ReceiptService.getAllReceipts(user.id, email: user.email);
    if (receipts.isNotEmpty) {
      final rows = <List<String>>[
        ['Datum', 'Butik', 'Kategori', 'Belopp', 'Valuta'],
        ...receipts.map((r) => [
              _formatDate(r.purchaseDate),
              r.store,
              r.category,
              r.amount.toStringAsFixed(2),
              r.currency,
            ]),
      ];
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Text('Kvitton', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(data: rows),
          ],
        ),
      );
    }

    // Gift cards
    final cards = await GiftCardService.getAllGiftCards(user.id, email: user.email);
    if (cards.isNotEmpty) {
      final rows = <List<String>>[
        ['Varumärke', 'Kortnummer', 'Saldo', 'Giltig till', 'Status'],
        ...cards.map((c) => [
              c.brand,
              c.maskedCardNumber,
              c.currentBalance.toStringAsFixed(2),
              c.expiresAt != null ? _formatDate(c.expiresAt!) : '',
              c.computedStatus,
            ]),
      ];
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Text('Presentkort', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(data: rows),
          ],
        ),
      );
    }

    // Autogiro
    final giros = await AutoGiroService.getAllAutoGiros(user.id, email: user.email);
    if (giros.isNotEmpty) {
      final rows = <List<String>>[
        ['Tjänst', 'Belopp/period', 'Intervall', 'Nästa dragning', 'Status'],
        ...giros.map((g) => [
              g.serviceName,
              g.amountPerPeriod.toStringAsFixed(2),
              g.billingInterval,
              _formatDate(g.nextChargeAt),
              g.status,
            ]),
      ];
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            pw.Text('Autogiro', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(data: rows),
          ],
        ),
      );
    }

    final bytes = await document.save();
    await FileExportHelper.deliver(
      bytes: Uint8List.fromList(bytes),
      fileName: 'fullkoll_export_${_timestampFormat.format(DateTime.now())}.pdf',
      mimeType: 'application/pdf',
    );
    // ignore: discarded_futures
    await NotificationService.trackEvent('export_pdf', {'kind': 'all_in_one'});
  }
}
