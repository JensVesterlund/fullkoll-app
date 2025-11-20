import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart' as app;
import '../database.dart';
import 'supabase_client.dart';

/// A thin adapter over supabase_flutter auth that maps Supabase user/session
/// to the app's User model and keeps a local users record for compatibility
/// with existing services.
class SupabaseAuthAdapter {
  SupabaseAuthAdapter._();

  /// Convert Supabase User to app.User with sane defaults.
  static app.User toAppUser(User sbUser, {DateTime? lastLoginAt}) {
    final String createdIso = sbUser.createdAt;
    final DateTime created = DateTime.tryParse(createdIso) ?? DateTime.now();
    final now = DateTime.now();
    return app.User(
      id: sbUser.id,
      email: sbUser.email ?? 'unknown@example.com',
      emailVerified: (() {
        final v = sbUser.emailConfirmedAt;
        if (v == null) return false;
        if (v is String) return DateTime.tryParse(v) != null;
        return v is DateTime; // fallback
      })(),
      createdAt: created,
      lastLoginAt: lastLoginAt ?? now,
      reminderDefaults: app.ReminderDefaults(),
      notificationPrefs: const app.NotificationPrefs(),
      role: 'user',
      privacyAcceptedAt: _readPrivacyAcceptedAt(sbUser),
      privacyVersion: (sbUser.userMetadata?['privacyVersion'] as int?) ?? 1,
      doNotTrack: (sbUser.userMetadata?['doNotTrack'] as bool?) ?? false,
    );
  }

  static DateTime? _readPrivacyAcceptedAt(User user) {
    final v = user.userMetadata?['privacyAcceptedAt'];
    if (v is String) {
      return DateTime.tryParse(v);
    }
    return null;
  }

  /// Ensure there is a local users record mirroring essential fields
  /// so that existing services continue to work.
  static Future<app.User> ensureLocalUser(app.User user) async {
    final existing = await AppDatabase.getById('users', user.id);
    if (existing == null) {
      await AppDatabase.put('users', user.id, user.toJson());
      return user;
    }
    final merged = app.User.fromJson(existing).copyWith(
      email: user.email,
      emailVerified: user.emailVerified,
      lastLoginAt: user.lastLoginAt,
      privacyAcceptedAt: user.privacyAcceptedAt,
      privacyVersion: user.privacyVersion,
      doNotTrack: user.doNotTrack,
    );
    await AppDatabase.put('users', merged.id, merged.toJson());
    return merged;
  }

  static Future<app.User> signInWithPassword({required String email, required String password}) async {
    final res = await supa.auth.signInWithPassword(email: email, password: password);
    final sbUser = res.user;
    if (sbUser == null) {
      throw AuthException('login_failed', 'No user returned by Supabase.');
    }
    final asApp = toAppUser(sbUser, lastLoginAt: DateTime.now());
    return await ensureLocalUser(asApp);
  }

  static Future<app.User> signUp({required String email, required String password}) async {
    final res = await supa.auth.signUp(email: email, password: password);
    final sbUser = res.user;
    if (sbUser == null) {
      // Magic link flow? Treat as pending and throw a gentle error upstream.
      throw AuthException('signup_pending', 'Check your email to confirm your account.');
    }
    final asApp = toAppUser(sbUser, lastLoginAt: DateTime.now());
    return await ensureLocalUser(asApp);
  }

  /// Optional: start passwordless magic-link sign-in. This does not return a user
  /// immediately; the user completes the flow via email link. We surface success
  /// or errors to the caller.
  static Future<void> signInWithMagicLink({required String email, required String emailRedirectTo}) async {
    await supa.auth.signInWithOtp(email: email, emailRedirectTo: emailRedirectTo);
  }

  static Future<void> signOut() async {
    await supa.auth.signOut();
  }

  static app.User? currentAppUserSync() {
    final sbUser = supa.auth.currentUser;
    if (sbUser == null) return null;
    return toAppUser(sbUser, lastLoginAt: DateTime.now());
  }

  static Future<app.User?> getCurrentUser() async {
    final sbUser = supa.auth.currentUser;
    if (sbUser == null) return null;
    final asApp = toAppUser(sbUser, lastLoginAt: DateTime.now());
    return await ensureLocalUser(asApp);
  }

  static Future<DateTime> acceptPrivacy(String userId, {int version = 1}) async {
    final acceptedAt = DateTime.now();
    try {
      await supa.auth.updateUser(UserAttributes(data: {
        'privacyAcceptedAt': acceptedAt.toIso8601String(),
        'privacyVersion': version,
      }));
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[SupabaseAuthAdapter] update metadata failed: $e');
      }
    }
    final raw = await AppDatabase.getById('users', userId);
    if (raw != null) {
      final data = Map<String, dynamic>.from(raw);
      data['privacyAcceptedAt'] = acceptedAt.toIso8601String();
      data['privacyVersion'] = version;
      await AppDatabase.put('users', userId, data);
    }
    return acceptedAt;
  }
}

class AuthException implements Exception {
  final String code;
  final String message;
  AuthException(this.code, this.message);
  @override
  String toString() => 'AuthException($code, $message)';
}
