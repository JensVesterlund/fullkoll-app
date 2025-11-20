import 'package:flutter/material.dart';
import 'i18n/app_localizations.dart';

import 'models.dart';
import 'services.dart';
import 'services/analytics.dart';
import 'theme.dart';

class DevStatusScreen extends StatefulWidget {
  final User user;

  const DevStatusScreen({super.key, required this.user});

  @override
  State<DevStatusScreen> createState() => _DevStatusScreenState();
}

class _DevStatusScreenState extends State<DevStatusScreen> {
  bool _isLoading = true;
  List<ScheduledNotification> _pending = const [];
  List<ScheduledNotification> _recent = const [];
  List<Breadcrumb> _breadcrumbs = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final pending = await NotificationService.getPending(widget.user.id);
    final recent = await NotificationService.getRecent(userId: widget.user.id, limit: 20);
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _recent = recent;
      _breadcrumbs = BreadcrumbBuffer.instance.items.reversed.toList();
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.user.notificationPrefs;
    final tiles = <Widget>[
      _buildSectionHeader(context.l10n.translate('dev.status.user')),
      _buildInfoTile('ID', widget.user.id),
      _buildInfoTile('E-post', widget.user.email),
      _buildInfoTile('Roll', widget.user.id == AuthService.guestUserId ? 'Gäst (seedad)' : 'Ordinarie'),
      _buildInfoTile('Språk', widget.user.locale),
      const SizedBox(height: 16),
      _buildSectionHeader(context.l10n.translate('dev.status.pushPerm')),
      _buildInfoTile('Push aktiverad', prefs.push ? context.l10n.translate('common.yes') : context.l10n.translate('common.no')),
      _buildInfoTile('Tyst läge', prefs.muted ? context.l10n.translate('common.on') : context.l10n.translate('common.off')),
      const SizedBox(height: 16),
      _buildSectionHeader('Planerade notiser (${_pending.length})'),
      if (_pending.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(context.l10n.translate('dev.status.noFutureJobs')),
        )
      else
        ..._pending.map(_buildNotificationTile),
      const SizedBox(height: 16),
      _buildSectionHeader('Senaste notisjobb (${_recent.length})'),
      if (_recent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(context.l10n.translate('dev.status.noJobsFound')),
        )
      else
        ..._recent.map(_buildNotificationTile),
      const SizedBox(height: 16),
      _buildSectionHeader('Senaste breadcrumbs (${_breadcrumbs.length})'),
      if (_breadcrumbs.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(context.l10n.translate('dev.status.noBreadcrumbs')),
        )
      else
        ..._breadcrumbs.map((crumb) => ListTile(
              leading: const Icon(Icons.bolt_outlined),
              title: Text(crumb.message),
              subtitle: Text('${crumb.timestamp.toIso8601String()}\n${crumb.context.isEmpty ? '' : crumb.context.toString()}'),
            )),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.translate('dev.status.title')),
        actions: [
          IconButton(
            tooltip: context.l10n.translate('dev.refresh'),
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _load,
          ),
          IconButton(
            tooltip: context.l10n.translate('dev.clearLog'),
            icon: const Icon(Icons.clear_all),
            onPressed: () {
              BreadcrumbBuffer.instance.clear();
              ErrorReporter.instance.clear();
              _load();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: tiles,
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _buildInfoTile(String label, String value) => ListTile(
        title: Text(label),
        subtitle: Text(value),
        dense: true,
      );

  Widget _buildNotificationTile(ScheduledNotification notification) {
    final statusColor = switch (notification.status) {
      'pending' => AppColors.warning,
      'delivered' => AppColors.success,
      'canceled' => AppColors.danger,
      _ => Theme.of(context).colorScheme.secondary,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: statusColor.withValues(alpha: 0.15), child: Icon(Icons.notifications, color: statusColor)),
        title: Text(notification.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 4),
            Text('Resurs: ${notification.resourceType} • ${notification.resourceId}', style: Theme.of(context).textTheme.bodySmall),
            Text('Schemalagd: ${notification.scheduledAt.toIso8601String()}', style: Theme.of(context).textTheme.bodySmall),
            Text('Status: ${notification.status}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        trailing: Chip(label: Text(notification.channel.toUpperCase())),
      ),
    );
  }
}