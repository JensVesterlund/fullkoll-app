import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';
import 'utils/formatting.dart';

import 'models.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets/dev_guest_banner.dart';
import 'i18n/app_localizations.dart';
import 'widgets/placeholder_views.dart';

class HomeScreen extends StatefulWidget {
  final User user;
  final Future<void> Function() onLogout;

  const HomeScreen({super.key, required this.user, required this.onLogout});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late User _user;
  List<Receipt> _upcomingReceipts = [];
  List<GiftCard> _upcomingGiftCards = [];
  List<AutoGiro> _upcomingAutoGiros = [];
  List<ScheduledNotification> _pendingNotifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    _loadUpcoming();
  }

  Future<void> _loadUpcoming() async {
    setState(() => _isLoading = true);
    await ReminderMaintenance.checkReminders(_user.id);
    await NotificationService.deliverDueNotifications();
    final receipts = await ReceiptService.getAllReceipts(_user.id, email: _user.email);
    final giftCards = await GiftCardService.getAllGiftCards(_user.id, email: _user.email);
    final autoGiros = await AutoGiroService.getAllAutoGiros(_user.id, email: _user.email);
    final notifications = await NotificationService.getPending(_user.id);

    final now = DateTime.now();
    _upcomingReceipts = receipts.where((r) {
      final deadlines = [r.returnDeadline, r.exchangeDeadline, r.warrantyExpires, r.refundDeadline].where((d) => d != null).toList();
      if (deadlines.isEmpty) return false;
      final earliest = deadlines.reduce((a, b) => a!.isBefore(b!) ? a : b)!;
      return earliest.isAfter(now) && earliest.difference(now).inDays <= 30;
    }).toList();

    _upcomingGiftCards = giftCards.where((c) => c.expiresAt != null && c.expiresAt!.isAfter(now) && c.expiresAt!.difference(now).inDays <= 30).toList();
    _upcomingAutoGiros = autoGiros.where((a) => a.nextChargeAt.isAfter(now) && a.nextChargeAt.difference(now).inDays <= 14).toList();

    setState(() {
      _isLoading = false;
      _pendingNotifications = notifications;
    });
  }

  Future<void> _refreshNotifications() async {
    final notifications = await NotificationService.getPending(_user.id);
    if (!mounted) return;
    setState(() => _pendingNotifications = notifications);
  }

  Future<void> _updateNotificationPrefs({bool? push, bool? muted}) async {
    final l10n = context.l10n;
    try {
      final prefs = _user.notificationPrefs.copyWith(
        push: push ?? _user.notificationPrefs.push,
        muted: muted ?? _user.notificationPrefs.muted,
      );
      final updatedUser = await UserService.updateNotificationPrefs(_user.id, prefs);
      if (!mounted) return;
      setState(() => _user = updatedUser);
      await _refreshNotifications();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('notifications.updateError'))),
      );
    }
  }

  Future<void> _sendTestNotification(BuildContext context) async {
    final l10n = context.l10n;
    await NotificationService.sendPush(
      _user.id,
      l10n.translate('notifications.testTitle'),
      l10n.translate('notifications.testBody'),
    );
    await NotificationService.trackEvent('test_notification_sent', {'userId': _user.id});
    await _refreshNotifications();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.translate('notifications.testScheduled'))),
    );
  }

  String _formatNotificationTime(BuildContext context, DateTime date) => formatDateTimeShortLocalized(context, date);

  IconData _iconForNotification(String resourceType) {
    switch (resourceType) {
      case 'receipt':
        return Icons.receipt_long;
      case 'giftcard':
        return Icons.card_giftcard;
      case 'autogiro':
        return Icons.autorenew;
      case 'split_settlement':
        return Icons.people_alt_outlined;
      default:
        return Icons.notifications_active_outlined;
    }
  }

  /// Build a localized title/body for a scheduled notification using the current UI locale.
  /// Falls back to the stored strings when we cannot reconstruct.
  Future<(String, String)> _localizedNotificationText(ScheduledNotification n, AppLocalizations l10n) async {
    try {
      switch (n.resourceType) {
        case 'autogiro':
          // Distinguish between charge/trial/binding based on payload keys
          final data = n.data ?? const {};
          final giro = await AutoGiroService.getAutoGiro(n.resourceId);
          if (data.containsKey('trialEndsAt')) {
            final date = DateTime.tryParse(data['trialEndsAt']?.toString() ?? '') ?? n.scheduledAt;
            final title = l10n.translate('notifications.autogiro.trialEndTitle');
            final body = l10n.translate('notifications.autogiro.trialEndBody', params: {
              'service': giro?.serviceName ?? '',
              'date': formatDateShortLocalized(context, date),
            });
            return (title, body);
          }
          if (data.containsKey('bindingEndsAt')) {
            final date = DateTime.tryParse(data['bindingEndsAt']?.toString() ?? '') ?? n.scheduledAt;
            final title = l10n.translate('notifications.autogiro.bindingEndTitle', params: {
              'service': giro?.serviceName ?? '',
            });
            final body = l10n.translate('notifications.autogiro.bindingEndBody', params: {
              'date': formatDateShortLocalized(context, date),
            });
            return (title, body);
          }
          // Default: upcoming charge
          final date = DateTime.tryParse(data['chargeAt']?.toString() ?? '') ?? n.scheduledAt;
          final title = l10n.translate('notifications.autogiro.chargeSoonTitle');
          final body = l10n.translate('notifications.autogiro.chargeSoonBody', params: {
            'service': giro?.serviceName ?? '',
            'amount': (giro?.amountPerPeriod ?? 0).toStringAsFixed(0),
            'date': formatDateShortLocalized(context, date),
          });
          return (title, body);
        default:
          // For other resource types we currently show the stored strings.
          return (n.title, n.body);
      }
    } catch (_) {
      // Any failure → stored strings
      return (n.title, n.body);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isGuest = _user.id == AuthService.guestUserId;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('app.title')),
        actions: [
          IconButton(
            tooltip: l10n.translate('notifications.title'),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none),
                if (_pendingNotifications.isNotEmpty)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                      child: Text(
                        _pendingNotifications.length.toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showNotificationCenter,
          ),
          IconButton(
            tooltip: l10n.translate('common.actions.logout'),
            icon: const Icon(Icons.person),
            onPressed: () async {
              await widget.onLogout();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (isGuest) DevGuestBanner(onLogout: widget.onLogout),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadUpcoming,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          l10n.translate('home.welcome', params: {'email': _user.email}),
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 24),
                        _buildModuleGrid(context, l10n),
                        const SizedBox(height: 32),
                        Text(l10n.translate('home.section.upcoming'), style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        if (_upcomingReceipts.isEmpty && _upcomingGiftCards.isEmpty && _upcomingAutoGiros.isEmpty)
                          _buildUpcomingEmptyState(l10n)
                        else ...[
                          if (_upcomingReceipts.isNotEmpty) ..._upcomingReceipts.map((r) => _buildUpcomingReceiptCard(context, l10n, r)),
                          if (_upcomingGiftCards.isNotEmpty) ..._upcomingGiftCards.map((c) => _buildUpcomingGiftCardCard(context, l10n, c)),
                          if (_upcomingAutoGiros.isNotEmpty) ..._upcomingAutoGiros.map((a) => _buildUpcomingAutoGiroCard(context, l10n, a)),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleGrid(BuildContext context, AppLocalizations l10n) => LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth < 360 ? 1 : 2;
          return GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              _buildModuleCard(context, l10n.translate('home.module.receipts'), Icons.receipt_long, AppColors.primary, '/receipts'),
              _buildModuleCard(context, l10n.translate('home.module.giftcards'), Icons.card_giftcard, AppColors.success, '/giftcards'),
              _buildModuleCard(context, l10n.translate('home.module.budget'), Icons.account_balance_wallet, AppColors.warning, '/budget'),
              _buildModuleCard(context, l10n.translate('home.module.split'), Icons.people, Colors.teal, '/split'),
              _buildModuleCard(context, l10n.translate('home.module.autogiro'), Icons.autorenew, Colors.deepPurple, '/autogiro'),
              _buildModuleCard(context, l10n.translate('home.module.privacy'), Icons.privacy_tip, Colors.grey, '/privacy'),
              _buildModuleCard(context, l10n.translate('home.module.settings'), Icons.settings, Colors.blueGrey, '/settings'),
            ],
          );
        },
      );

  Widget _buildModuleCard(BuildContext ctx, String title, IconData icon, Color color, String route) => GestureDetector(
    onTap: () {
      // ignore: discarded_futures
      NotificationService.trackEvent('nav_to', {'route': route});
      ctx.push(route);
    },
    child: Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 8),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color), textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _buildUpcomingEmptyState(AppLocalizations l10n) => EmptyPlaceholder(
        icon: Icons.check_circle,
        title: l10n.translate('home.section.upcoming.emptyTitle'),
        description: l10n.translate('home.section.upcoming.empty'),
      );

  Future<void> _showNotificationCenter() async {
    final l10n = context.l10n;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final notifications = _pendingNotifications;
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l10n.translate('notifications.title'), style: Theme.of(context).textTheme.titleLarge),
                              Text(l10n.translate('notifications.subtitle'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                            ],
                          ),
                          IconButton(
                            tooltip: l10n.translate('common.actions.close'),
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.translate('notifications.allowPush')),
                              subtitle: Text(l10n.translate('notifications.allowPushDescription')),
                              value: _user.notificationPrefs.push,
                              onChanged: (value) async {
                                await _updateNotificationPrefs(push: value);
                                setSheetState(() {});
                              },
                            ),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l10n.translate('notifications.muted')),
                              subtitle: Text(l10n.translate('notifications.mutedDescription')),
                              value: _user.notificationPrefs.muted,
                              onChanged: (value) async {
                                await _updateNotificationPrefs(muted: value);
                                setSheetState(() {});
                              },
                            ),
                            if (kDebugMode) ...[
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await _sendTestNotification(context);
                                  setSheetState(() {});
                                },
                                icon: const Icon(Icons.notifications_active_outlined),
                                label: Text(l10n.translate('notifications.sendTest')),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Text(l10n.translate('notifications.schedule'), style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            if (notifications.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(l10n.translate('notifications.none'), style: Theme.of(context).textTheme.bodyMedium),
                              )
                            else
                              ...notifications.map(
                                (n) => FutureBuilder<(String, String)>(
                                  future: _localizedNotificationText(n, l10n),
                                  builder: (context, snapshot) {
                                    final titleBody = snapshot.data;
                                    final displayTitle = titleBody?.$1 ?? n.title;
                                    final displayBody = titleBody?.$2 ?? n.body;
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        leading: Icon(_iconForNotification(n.resourceType), color: AppColors.primary),
                                        title: Text(displayTitle),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(displayBody),
                                            const SizedBox(height: 4),
                                            Text(_formatNotificationTime(context, n.scheduledAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                                          ],
                                        ),
                                        trailing: Chip(
                                          label: Text(n.channel.toUpperCase()),
                                          backgroundColor: n.channel == 'push' ? AppColors.primary.withValues(alpha: 0.1) : Colors.grey[200],
                                          labelStyle: TextStyle(color: n.channel == 'push' ? AppColors.primary : Colors.grey[700], fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUpcomingReceiptCard(BuildContext context, AppLocalizations l10n, Receipt r) {
    final deadlines = [r.returnDeadline, r.exchangeDeadline, r.warrantyExpires, r.refundDeadline].where((d) => d != null).toList();
    final earliest = deadlines.reduce((a, b) => a!.isBefore(b!) ? a : b)!;
    final daysLeft = earliest.difference(DateTime.now()).inDays;
    final displayDays = daysLeft < 0 ? 0 : daysLeft;
    final badgeColor = daysLeft <= 7 ? (daysLeft < 0 ? AppColors.danger : AppColors.warning) : AppColors.success;
    final badgeKey = daysLeft < 0
        ? 'home.upcoming.receipt.badge.passed'
        : (daysLeft <= 7 ? 'home.upcoming.receipt.badge.dueSoon' : 'home.upcoming.receipt.badge.ok');
    return Card(
      child: ListTile(
        leading: Icon(Icons.receipt, color: badgeColor),
        title: Text(r.store),
        subtitle: Text(
          l10n.translate('home.upcoming.receiptSubtitle', params: {
            'date': _formatDate(earliest),
            'days': displayDays,
          }),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            l10n.translate(badgeKey),
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () => context.push('/receipts'),
      ),
    );
  }

  Widget _buildUpcomingGiftCardCard(BuildContext context, AppLocalizations l10n, GiftCard c) {
    final daysLeft = c.expiresAt!.difference(DateTime.now()).inDays;
    final displayDays = daysLeft < 0 ? 0 : daysLeft;
    final badgeColor = daysLeft <= 0
        ? AppColors.danger
        : (daysLeft <= 7 ? AppColors.warning : (c.computedStatus == 'used' ? Colors.grey : AppColors.success));
    final badgeKey = c.computedStatus == 'used'
        ? 'home.upcoming.giftcard.badge.used'
        : (daysLeft <= 0
            ? 'home.upcoming.giftcard.badge.expired'
            : (daysLeft <= 7 ? 'home.upcoming.giftcard.badge.expiring' : 'home.upcoming.giftcard.badge.active'));
    return Card(
      child: ListTile(
        leading: Icon(Icons.card_giftcard, color: badgeColor),
        title: Text(c.brand),
        subtitle: Text(
          l10n.translate('home.upcoming.giftcardSubtitle', params: {
            'date': _formatDate(c.expiresAt!),
            'days': displayDays,
          }),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            l10n.translate(badgeKey),
            style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () => context.push('/giftcards'),
      ),
    );
  }

  Widget _buildUpcomingAutoGiroCard(BuildContext context, AppLocalizations l10n, AutoGiro a) {
    final daysLeft = a.nextChargeAt.difference(DateTime.now()).inDays;
    final iconColor = daysLeft <= 3 ? AppColors.danger : AppColors.primary;
    return Card(
      child: ListTile(
        leading: Icon(Icons.autorenew, color: iconColor),
        title: Text(a.serviceName),
        subtitle: Text(
          l10n.translate('home.upcoming.autogiroSubtitle', params: {
            'date': _formatDate(a.nextChargeAt),
            'amount': a.amountPerPeriod.toStringAsFixed(0),
            'currency': a.currency,
          }),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
        onTap: () => context.push('/autogiro'),
      ),
    );
  }

  String _formatDate(DateTime date) => formatDateShortLocalized(context, date);
}
