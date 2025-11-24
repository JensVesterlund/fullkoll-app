import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'i18n/app_localizations.dart';
import 'models.dart';
import 'services.dart';
// Web KV store for locale persistence
import 'utils/web_kv_store_stub.dart'
    if (dart.library.html) 'utils/web_kv_store_web.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.user,
    required this.localeController,
    required this.onUserUpdated,
    this.onLogout,
  });

  final User user;
  final LocaleController localeController;
  final ValueChanged<User> onUserUpdated;
  final Future<void> Function()? onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Locale _selectedLocale;
  bool _isUpdatingLocale = false;

  @override
  void initState() {
    super.initState();
    _selectedLocale = widget.localeController.locale;
  }

  Future<void> _changeLocale(Locale locale) async {
    if (_isUpdatingLocale || locale == _selectedLocale) return;
    setState(() => _isUpdatingLocale = true);
    try {
      widget.localeController.setLocale(locale);
      final updatedUser = await UserService.setLocale(widget.user.id, '${locale.languageCode}-${locale.countryCode ?? ''}');
      widget.onUserUpdated(updatedUser);
      // Persist to web localStorage for faster boot locale before auth loads.
      try {
        final tag = '${locale.languageCode}-${(locale.countryCode ?? locale.languageCode.toUpperCase())}';
        webSetItem('locale', tag);
      } catch (_) {}
      setState(() => _selectedLocale = locale);
    } finally {
      if (mounted) {
        setState(() => _isUpdatingLocale = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final locales = <Locale>[
      const Locale('sv', 'SE'),
      const Locale('en', 'US'),
    ];
    const privacyUrl = 'https://fullkoll.app/sekretess';
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('settings.title')),
        // Ensure back navigation reliably returns to Home when opened via GoRouter.push
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          // Dev: Quick access to /dev/health from Settings
          IconButton(
            tooltip: 'Health',
            icon: const Icon(Icons.science_outlined),
            onPressed: () => context.go('/dev/health'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.translate('settings.general.title'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: Text(l10n.translate('settings.language.label')),
              subtitle: Text(l10n.translate('settings.language.subtitle')),
              // Constrain trailing widget width; ListTile asserts if trailing consumes full width.
              trailing: SizedBox(
                width: 160,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Locale>(
                    isExpanded: true,
                    value: _selectedLocale,
                    onChanged: _isUpdatingLocale ? null : (value) {
                      if (value != null) {
                        _changeLocale(value);
                      }
                    },
                    items: locales
                        .map(
                          (locale) => DropdownMenuItem(
                            value: locale,
                            child: Text(
                              locale.languageCode == 'sv'
                                  ? l10n.translate('common.language.sv')
                                  : l10n.translate('common.language.en'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Notifications demo
          Text(l10n.translate('settings.notifications.title'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(l10n.translate('settings.notifications.preview')),
              subtitle: Text(l10n.translate('settings.notifications.previewHint')),
              onTap: () async {
                // Build a sample notification (gift card expiry) in both locales
                final sv = await AppLocalizations.load(const Locale('sv', 'SE'));
                final en = await AppLocalizations.load(const Locale('en', 'US'));
                if (!mounted) return;
                showModalBottomSheet(
                  context: context,
                  builder: (ctx) {
                    final dateSv = DateFormat('d MMM yyyy', 'sv-SE').format(DateTime(2025, 12, 31));
                    final dateEn = DateFormat('MMM d, yyyy', 'en-US').format(DateTime(2025, 12, 31));
                    final svTitle = sv.translate('notifications.giftcards.expiryTitle');
                    final svBody = sv.translate('notifications.giftcards.expiryBody', params: {
                      'brand': 'IKEA',
                      'date': dateSv,
                    });
                    final enTitle = en.translate('notifications.giftcards.expiryTitle');
                    final enBody = en.translate('notifications.giftcards.expiryBody', params: {
                      'brand': 'IKEA',
                      'date': dateEn,
                    });
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.translate('settings.notifications.example'), style: theme.textTheme.titleMedium),
                          const SizedBox(height: 12),
                          ListTile(
                            leading: const CircleAvatar(child: Text('SV')),
                            title: Text(svTitle),
                            subtitle: Text(svBody),
                          ),
                          ListTile(
                            leading: const CircleAvatar(child: Text('EN')),
                            title: Text(enTitle),
                            subtitle: Text(enBody),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text(l10n.translate('settings.privacy.title'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: Text(l10n.translate('settings.privacy.policy')),
                  subtitle: Text(l10n.translate('settings.privacy.policyDescription')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/legal/privacy'),
                ),
                const Divider(height: 0),
                SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: Text(l10n.translate('settings.privacy.dnt')),
                  subtitle: Text(l10n.translate('settings.privacy.dntDescription')),
                  value: widget.user.doNotTrack,
                  onChanged: (value) async {
                    final updated = await UserService.setDoNotTrack(widget.user.id, value);
                    widget.onUserUpdated(updated);
                    setState(() {});
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: const SelectableText(privacyUrl),
                  subtitle: Text(l10n.translate('settings.privacy.openExternal')),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () {
                      Clipboard.setData(const ClipboardData(text: privacyUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('common.feedback.copied'))),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  title: Text(l10n.translate('settings.privacy.permissions')),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(l10n.translate('settings.privacy.permission.camera')),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: Text(l10n.translate('settings.privacy.permission.notifications')),
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(l10n.translate('settings.privacy.permission.files')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download),
                  title: Text(l10n.translate('settings.privacy.exportAll.pdf')),
                  subtitle: Text(l10n.translate('settings.privacy.exportAll.pdfHint')),
                  onTap: () async {
                    try {
                      await ExportService.exportAllPdf(user: widget.user);
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('export.pdf.success'))),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('export.error', params: {'message': e.toString()}))),
                      );
                    }
                  },
                ),
                const Divider(height: 0),
                ListTile(
                  leading: const Icon(Icons.table_view),
                  title: Text(l10n.translate('settings.privacy.exportAll.csv')),
                  subtitle: Text(l10n.translate('settings.privacy.exportAll.csvHint')),
                  onTap: () async {
                    try {
                      await ExportService.exportReceiptsCsv(user: widget.user);
                      await ExportService.exportGiftCardsCsv(user: widget.user);
                      await ExportService.exportAutogiroCsv(user: widget.user);
                      await ExportService.exportSplitOverviewCsv(user: widget.user);
                      // Also export current-month transactions for each budget
                      final budgets = await BudgetService.getAllBudgets(widget.user.id, email: widget.user.email);
                      final now = DateTime.now();
                      final month = DateTime(now.year, now.month);
                      for (final b in budgets) {
                        await ExportService.exportBudgetTransactionsCsv(user: widget.user, budget: b, month: month);
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('export.csv.success'))),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('export.error', params: {'message': e.toString()}))),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Dangerous section (dev-only simulation)
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: Text(l10n.translate('settings.privacy.deleteAccount')),
                  subtitle: Text(l10n.translate('settings.privacy.deleteAccountHint')),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.translate('settings.privacy.deleteConfirmTitle')),
                            content: Text(l10n.translate('settings.privacy.deleteConfirmBody')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text(l10n.translate('common.cancel')),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text(l10n.translate('settings.privacy.deleteNow')),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                    if (!confirmed) return;
                    await UserService.deleteAccount(widget.user.id);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.translate('settings.privacy.deleteDone'))),
                    );
                    if (widget.onLogout != null) {
                      await widget.onLogout!.call();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.onLogout != null)
            Card(
              child: ListTile(
                title: Text(l10n.translate('settings.logout')),
                subtitle: Text(l10n.translate('settings.logout.description')),
                trailing: const Icon(Icons.logout),
                onTap: widget.onLogout,
              ),
            ),
        ],
      ),
    );
  }
}