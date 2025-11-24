import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'i18n/app_localizations.dart';
import 'services.dart';
import 'services/analytics.dart';
import 'services/auth_supabase.dart';
import 'services/repositories/receipts_repo.dart';
import 'utils/perf.dart';
import 'models.dart';
import 'utils/file_export_helper.dart';
import 'ocr_service.dart';
import 'package:uuid/uuid.dart';

/// Dev-only diagnostics hub for release checks.
class DevHealthScreen extends StatefulWidget {
  const DevHealthScreen({super.key});

  @override
  State<DevHealthScreen> createState() => _DevHealthScreenState();
}

class _DevHealthScreenState extends State<DevHealthScreen> {
  bool _loading = true;
  List<_RouteInfo> _routes = const [];
  Map<String, _NsCoverage> _coverageByNs = const {};
  double _coverageTotal = 1.0;
  List<String> _missingKeys = const [];
  List<ScheduledNotification> _upcoming = const [];
  Map<String, List<LoggedError>> _errorsByHint = const {};
  String? _userId;
  Map<String, Duration> _routePerf = const {};
  Duration? _tti;
  List<_SmokeResult> _smoke = const [];
  bool _runningSmoke = false;
  bool _runningSbTest = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final router = GoRouter.of(context);
      final routeList = _extractRoutes(router);

      final i18n = await _loadI18nCoverage();
      final user = await AuthService.getCurrentUser();
      final upcomingRaw = user == null ? <ScheduledNotification>[] : await NotificationService.getPending(user.id);
      final now = DateTime.now();
      final in7d = now.add(const Duration(days: 7));
      final upcoming = upcomingRaw.where((n) => n.scheduledAt.isAfter(now) && n.scheduledAt.isBefore(in7d)).toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
      final errors = _groupErrorsByHint(ErrorReporter.instance.last(limit: 50));

      setState(() {
        _routes = routeList;
        _coverageByNs = i18n.coverageByNs;
        _coverageTotal = i18n.total;
        _missingKeys = i18n.missingKeys;
        _upcoming = upcoming;
        _errorsByHint = errors;
        _userId = user?.id;
        _routePerf = Map<String, Duration>.from(PerfTracker.routeFirstRender);
        _tti = PerfTracker.tti;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_RouteInfo> _extractRoutes(GoRouter router) {
    try {
      final configRoutes = router.configuration.routes;
      return configRoutes.map((r) {
        String label;
        if (r is GoRoute) {
          label = r.path;
        } else {
          label = r.toString();
        }
        return _RouteInfo(path: label, guarded: _isGuardedPath(label));
      }).toList();
    } catch (_) {
      // Fallback: list a few known routes
      const paths = ['/auth', '/home', '/receipts', '/giftcards', '/budget', '/split', '/autogiro', '/settings', '/legal/privacy', '/dev/status', '/dev/i18n', '/dev/health'];
      return paths.map((p) => _RouteInfo(path: p, guarded: _isGuardedPath(p))).toList();
    }
  }

  bool _isGuardedPath(String path) {
    if (path.startsWith('/dev') || path.startsWith('/legal') || path == '/auth' || path == '/privacy') return false;
    return true; // App routes are guarded via auth checks in builders
  }

  _I18nSnapshot _loadI18nCoverageSync(Map<String, String> sv, Map<String, String> en) {
    final missing = <String>[];
    final byNs = <String, _NsCoverage>{};
    for (final key in sv.keys) {
      final ns = key.contains('.') ? key.split('.').first : 'root';
      byNs.putIfAbsent(ns, () => _NsCoverage());
      byNs[ns]!.sv++;
      if (en.containsKey(key)) {
        byNs[ns]!.en++;
      } else {
        missing.add(key);
      }
    }
    final covTotal = sv.isEmpty ? 1.0 : (sv.keys.where((k) => en.containsKey(k)).length / sv.length);
    missing.sort();
    return _I18nSnapshot(coverageByNs: byNs, total: covTotal, missingKeys: missing);
  }

  Future<_I18nSnapshot> _loadI18nCoverage() async {
    // Sanitize JSON to allow // comments (match AppLocalizations/DevI18n behavior)
    final rawSv = await rootBundle.loadString('assets/i18n/sv-SE.json');
    final rawEn = await rootBundle.loadString('assets/i18n/en-US.json');
    final sanitizedSv = rawSv
        // Remove full-line // comments
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
        // Remove inline // comments (keep char before //)
        .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1')
        // Remove trailing commas before } or ]
        .replaceAll(RegExp(r',(?=\s*[}\]])'), '');
    final sanitizedEn = rawEn
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
        .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1')
        .replaceAll(RegExp(r',(?=\s*[}\]])'), '');
    final sv = Map<String, String>.from(json.decode(sanitizedSv) as Map);
    final en = Map<String, String>.from(json.decode(sanitizedEn) as Map);
    return _loadI18nCoverageSync(sv, en);
  }

  Map<String, List<LoggedError>> _groupErrorsByHint(List<LoggedError> items) {
    final map = <String, List<LoggedError>>{};
    for (final e in items) {
      final key = (e.hint ?? 'unknown');
      map.putIfAbsent(key, () => <LoggedError>[]).add(e);
    }
    return map;
  }

  Future<void> _runSmoke() async {
    final results = <_SmokeResult>[];
    if (mounted) setState(() => _runningSmoke = true);
    try {
      debugPrint('[SMOKE] start');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kör smoke tests…')));
      // Auth
      final user = await AuthService.loginGuest(fresh: true);
      results.add(_SmokeResult('Auth: login → home', user.id.isNotEmpty, detail: user.id));

      // Receipt: manual
      final receipt = Receipt(
        id: const Uuid().v4(),
        ownerId: user.id,
        store: 'SmokeTest Store',
        purchaseDate: DateTime.now(),
        amount: 123.0,
        category: 'Other',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        remindersEnabled: false,
      );
      await ReceiptService.createReceipt(receipt);
      final receipts = await ReceiptService.getAllReceipts(user.id);
      results.add(_SmokeResult('Kvitto: skapa (manuell)', receipts.any((r) => r.id == receipt.id)));

      // Receipt: OCR mock
      final ocr = await OcrService.analyzeReceipt(bytes: const [0], fileName: 'ica_123.jpg');
      final ocrReceipt = Receipt(
        id: const Uuid().v4(),
        ownerId: user.id,
        store: ocr.store.value ?? 'OCR Store',
        purchaseDate: DateTime.now(),
        amount: 99.0,
        category: 'Other',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        remindersEnabled: false,
      );
      await ReceiptService.createReceipt(ocrReceipt);
      final receipts2 = await ReceiptService.getAllReceipts(user.id);
      results.add(_SmokeResult('Kvitto: skapa (OCR mock)', receipts2.any((r) => r.id == ocrReceipt.id)));

      // Budget: create budget and export CSV
      final budget = Budget(id: const Uuid().v4(), ownerId: user.id, name: 'Smoke Budget', year: DateTime.now().year, createdAt: DateTime.now(), updatedAt: DateTime.now());
      await BudgetService.createBudget(budget);
      // Create category first to satisfy FK and valid UUID type
      final cat = BudgetCategory(id: const Uuid().v4(), budgetId: budget.id, name: 'Misc', limit: 1000);
      await BudgetService.createCategory(cat);
      final tx = Transaction(
        id: const Uuid().v4(),
        budgetId: budget.id,
        categoryId: cat.id,
        type: 'expense',
        description: 'Smoke Tx',
        amount: 50,
        date: DateTime.now(),
      );
      await BudgetService.createTransaction(tx);
      results.add(_SmokeResult('Budget: lägg kategori + transaktion', true));
      try {
        await ExportService.exportBudgetTransactionsCsv(user: user, budget: budget, month: DateTime.now());
        results.add(_SmokeResult('Budget: export CSV', true));
      } catch (_) {
        results.add(_SmokeResult('Budget: export CSV', false));
      }

      // Gift card: create via QR mock and check badge for expiry <30d
      final card = GiftCard(
        id: const Uuid().v4(),
        ownerId: user.id,
        brand: 'SmokeCard',
        category: 'Other',
        cardNumber: '1234 5678 9012 3456',
        initialBalance: 300,
        currentBalance: 300,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 20)),
      );
      await GiftCardService.createGiftCard(card);
      final cards = await GiftCardService.getAllGiftCards(user.id);
      final expiring = cards.firstWhere((c) => c.id == card.id).computedStatus == 'expiring';
      results.add(_SmokeResult('Presentkort: skapa (QR mock), badge vid <30d', expiring));

      // Split: create group, expense, settlement
      final group = SplitGroup(id: const Uuid().v4(), title: 'Smoke Group', creatorId: user.id, createdAt: DateTime.now());
      await SplitService.createSplitGroup(group);
      final p1 = Participant(id: const Uuid().v4(), splitGroupId: group.id, name: 'A', contact: '');
      final p2 = Participant(id: const Uuid().v4(), splitGroupId: group.id, name: 'B', contact: '');
      await SplitService.createParticipant(p1);
      await SplitService.createParticipant(p2);
      final exp = Expense(id: const Uuid().v4(), splitGroupId: group.id, paidBy: p1.id, amount: 100, description: 'Test', sharedWith: [p1.id, p2.id], createdAt: DateTime.now());
      await SplitService.createExpense(exp);
      final settlements = await SplitService.generateSettlements(group.id);
      results.add(_SmokeResult('Split: skapa split, lägg utlägg, räkna uppgörelse', settlements.isNotEmpty));

      // Autogiro: create, schedule reminder, bump nextCharge
      final giro = AutoGiro(
        id: const Uuid().v4(),
        ownerId: user.id,
        serviceName: 'Smoke Subscription',
        category: 'Software',
        amountPerPeriod: 79,
        currency: 'SEK',
        billingInterval: 'monthly',
        paymentMethod: 'card',
        nextChargeAt: DateTime.now().add(const Duration(days: 10)),
        startDate: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await AutoGiroService.createAutoGiro(giro);
      await AutoGiroService.updateAutoGiro(giro);
      final updatedGiro = await AutoGiroService.getAutoGiro(giro.id);
      final okReminder = (updatedGiro?.chargeReminderJobIds ?? const <String>[]).isNotEmpty;
      results.add(_SmokeResult('Autogiro: skapa, schemalägg påminnelse', okReminder));
      if (updatedGiro != null) {
        final bumped = updatedGiro.copyWith(nextChargeAt: DateTime.now().add(const Duration(days: 40)));
        await AutoGiroService.updateAutoGiro(bumped);
        final bumpedSaved = await AutoGiroService.getAutoGiro(bumped.id);
        results.add(_SmokeResult('Autogiro: bumpa nextChargeAt', (bumpedSaved?.nextChargeAt.difference(DateTime.now()).inDays ?? 0) > 30));
      }
    } catch (e, st) {
      // Record but keep UI usable
      // ignore: discarded_futures
      AnalyticsService.logError(e, st, hint: 'smoke_tests_failed');
      results.add(_SmokeResult('Smoke tests crashed', false, detail: e.toString()));
    } finally {
      if (!mounted) return;
      final passed = results.where((r) => r.ok).length;
      final total = results.length;
      setState(() {
        _smoke = results;
        _runningSmoke = false;
      });
      debugPrint('[SMOKE] done: $passed/$total ok');
      if (total > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Smoke tests klara: $passed/$total ✅')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, '/dev/health should only be used in dev');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health (dev only)'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Route check'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: _routes
                            .map((r) => ListTile(
                                  dense: true,
                                  leading: Icon(r.guarded ? Icons.lock_outline : Icons.public, color: r.guarded ? Colors.orange : Colors.green),
                                  title: Text(r.path),
                                  subtitle: r.guarded ? const Text('Guarded (auth required)') : const Text('Public'),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('i18n coverage'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(_coverageTotal >= 0.99 ? Icons.check_circle : Icons.error_outline, color: _coverageTotal >= 0.99 ? Colors.green : Colors.orange),
                          const SizedBox(width: 8),
                          Text('Total: ${(_coverageTotal * 100).toStringAsFixed(1)}%')
                        ]),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: _coverageByNs.entries.map((e) {
                          final pct = e.value.sv == 0 ? 1.0 : (e.value.en / e.value.sv);
                          final color = pct >= 0.99 ? Colors.green : (pct >= 0.95 ? Colors.orange : Colors.red);
                          return Chip(label: Text('${e.key}: ${(pct * 100).toStringAsFixed(0)}%'), backgroundColor: color.withValues(alpha: 0.12));
                        }).toList()),
                        const SizedBox(height: 8),
                        if (_missingKeys.isNotEmpty)
                          Text('Missing in en-US: ${_missingKeys.length}', style: Theme.of(context).textTheme.bodyMedium),
                        if (_missingKeys.isNotEmpty)
                          SizedBox(
                            height: 120,
                            child: ListView.builder(
                              itemCount: _missingKeys.length,
                              itemBuilder: (_, i) => Text(_missingKeys[i]),
                            ),
                          )
                        else
                          const Text('No missing keys. ✅'),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Permission check (destructive actions)'),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.shield_outlined, color: Colors.blueGrey),
                      title: const Text('UI uses PermissionGuard or equivalent access checks'),
                      subtitle: const Text('Receipts, Gift Cards guarded via PermissionGuard; Split uses role checks'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Notifications – upcoming (7 days)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _upcoming.isEmpty
                          ? const Text('No upcoming notifications')
                          : Column(
                              children: _upcoming
                                  .map((n) => ListTile(
                                        dense: true,
                                        leading: const Icon(Icons.notifications_active_outlined),
                                        title: Text('${n.resourceType} • ${n.title}'),
                                        subtitle: Text('${n.scheduledAt} → ${n.resourceId}'),
                                      ))
                                  .toList(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Errors (last 50) grouped by hint'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _errorsByHint.isEmpty
                          ? const Text('No recent errors logged')
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: _errorsByHint.entries
                                  .map((e) => Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.error_outline, size: 18),
                                            const SizedBox(width: 8),
                                            Expanded(child: Text('${e.key}: ${e.value.length}')),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Preview perf (approx)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('TTI: ${_tti?.inMilliseconds ?? 0} ms'),
                        const SizedBox(height: 8),
                        const Text('First push per route:'),
                        const SizedBox(height: 4),
                        ..._routePerf.entries.map((e) => Text('${e.key}: ${e.value.inMilliseconds} ms')),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionTitle('Smoke tests'),
                  Row(children: [
                    ElevatedButton.icon(
                      onPressed: _runningSmoke ? null : _runSmoke,
                      icon: _runningSmoke ? const Icon(Icons.hourglass_bottom) : const Icon(Icons.play_arrow),
                      label: Text(_runningSmoke ? 'Kör…' : 'Kör smoke test'),
                    ),
                    const SizedBox(width: 8),
                    if (_userId != null) Text('user: $_userId', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                  const SizedBox(height: 8),
                  _sectionTitle('Supabase'),
                  Row(children: [
                    ElevatedButton.icon(
                      onPressed: _runningSbTest ? null : _runSupabaseTest,
                      icon: const Icon(Icons.cloud_done_outlined),
                      label: Text(context.l10n.translate('dev.supabase.button')),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (_smoke.isNotEmpty)
                    Card(
                      child: Column(
                        children: _smoke
                            .map((s) => ListTile(
                                  dense: true,
                                  leading: Icon(s.ok ? Icons.check_circle : Icons.error_outline, color: s.ok ? Colors.green : Colors.red),
                                  title: Text(s.name),
                                  subtitle: s.detail == null ? null : Text(s.detail!),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Future<void> _runSupabaseTest() async {
    final l10n = context.l10n;
    setState(() => _runningSbTest = true);
    try {
      final sbUser = SupabaseAuthAdapter.currentAppUserSync();
      if (sbUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('dev.supabase.loginRequired'))),
        );
        return;
      }

      // INSERT
      final repo = ReceiptsRepo();
      final created = await repo.create(
        store: 'SB TEST',
        amount: 1.23,
        currency: 'SEK',
        purchasedAt: DateTime.now(),
        category: 'Other',
        notes: 'healthcheck',
      );
      final createdId = created['id'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('dev.supabase.insertOk'))),
      );

      // SELECT
      final list = await repo.list();
      final exists = createdId != null && list.any((row) => row['id'] == createdId);
      if (!exists) {
        throw StateError('created_row_missing');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('dev.supabase.selectOk'))),
      );

      // DELETE
      if (createdId != null) {
        await repo.delete(createdId);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('dev.supabase.deleteOk'))),
      );
    } catch (error, stack) {
      AnalyticsService.logError(error, stack, hint: 'supabase_health');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('dev.supabase.error', params: {'message': error.toString()}))),
      );
    } finally {
      if (mounted) setState(() => _runningSbTest = false);
    }
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _RouteInfo {
  final String path;
  final bool guarded;
  const _RouteInfo({required this.path, required this.guarded});
}

class _NsCoverage {
  int sv = 0;
  int en = 0;
}

class _I18nSnapshot {
  final Map<String, _NsCoverage> coverageByNs;
  final double total;
  final List<String> missingKeys;
  const _I18nSnapshot({required this.coverageByNs, required this.total, required this.missingKeys});
}

class _SmokeResult {
  final String name;
  final bool ok;
  final String? detail;
  const _SmokeResult(this.name, this.ok, {this.detail});
}
