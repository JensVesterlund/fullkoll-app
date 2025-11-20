import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'utils/formatting.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets/dev_guest_banner.dart';
import 'components/sharing/permission_guard.dart';
import 'components/sharing/share_dialog.dart';
import 'i18n/app_localizations.dart';

const _uuid = Uuid();

class AutoGiroScreen extends StatefulWidget {
  final User user;
  final Future<void> Function()? onLogout;

  const AutoGiroScreen({super.key, required this.user, this.onLogout});

  @override
  State<AutoGiroScreen> createState() => _AutoGiroScreenState();
}

class _AutoGiroScreenState extends State<AutoGiroScreen> {
  List<AutoGiro> _giros = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGiros();
  }

  Future<void> _loadGiros() async {
    setState(() => _isLoading = true);
    _giros = await AutoGiroService.getAllAutoGiros(widget.user.id, email: widget.user.email);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.user.id == AuthService.guestUserId;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.translate('autogiro.title'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showGiroDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (isGuest) DevGuestBanner(onLogout: widget.onLogout),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _giros.isEmpty
                    ? _buildEmptyState()
                    : Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.all(16),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.l10n.translate('autogiro.summary.monthlyTotal'), style: Theme.of(context).textTheme.titleMedium),
                                Text('${_calculateMonthlyTotal().toStringAsFixed(0)} SEK', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: AppColors.primary)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: _giros.length,
                              itemBuilder: (context, i) => _buildGiroCard(_giros[i]),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.autorenew, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(context.l10n.translate('autogiro.empty.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.l10n.translate('autogiro.empty.subtitle'), style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  Widget _buildGiroCard(AutoGiro g) {
    final daysLeft = g.nextChargeAt.difference(DateTime.now()).inDays;
    final urgencyColor = daysLeft <= 3 ? AppColors.danger : (daysLeft <= 7 ? AppColors.warning : AppColors.success);

    return Card(
      child: ExpansionTile(
        leading: Icon(Icons.autorenew, color: AppColors.primary),
        title: Text(g.serviceName),
        subtitle: Text('${g.amountPerPeriod.toStringAsFixed(0)} SEK • ${_intervalLabel(g.billingInterval, context)}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: urgencyColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(context.l10n.translate('autogiro.daysLeft', params: {'days': daysLeft.toString()}), style: TextStyle(color: urgencyColor, fontWeight: FontWeight.w600)),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PermissionGuard(
                      user: widget.user,
                      resourceType: 'autogiro',
                      resourceId: g.id,
                      ownerId: g.ownerId,
                      requiredRole: ShareRoles.editor,
                      builder: (context, access) => IconButton(
                        tooltip: context.l10n.translate('common.actions.share'),
                        icon: const Icon(Icons.ios_share),
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => ShareDialog(
                              user: widget.user,
                              resourceType: 'autogiro',
                              resourceId: g.id,
                              resourceName: context.l10n.translate('autogiro.shareDialog.title', params: {'name': g.serviceName}),
                              ownerId: g.ownerId,
                            ),
                          );
                        },
                      ),
                      fallback: const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildDetailRow(context.l10n.translate('autogiro.detail.category'), g.category),
                _buildDetailRow(context.l10n.translate('autogiro.detail.nextCharge'), _formatDate(context, g.nextChargeAt)),
                _buildDetailRow(context.l10n.translate('autogiro.detail.paymentMethod'), g.paymentMethod),
                if (g.trialEnabled && g.trialEndsAt != null) _buildDetailRow(context.l10n.translate('autogiro.detail.trialEnds'), _formatDate(context, g.trialEndsAt!)),
                const SizedBox(height: 16),
                Text(context.l10n.translate('autogiro.reminders.title'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildGiroReminderSummary(g),
                const SizedBox(height: 16),
                PermissionGuard(
                  user: widget.user,
                  resourceType: 'autogiro',
                  resourceId: g.id,
                  ownerId: g.ownerId,
                  requiredRole: ShareRoles.viewer,
                  builder: (context, access) {
                    final canEdit = access.canEdit;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 200,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit),
                              label: Text(context.l10n.translate('common.actions.edit')),
                            onPressed: canEdit ? () => _showGiroDialog(initial: g) : null,
                          ),
                        ),
                        SizedBox(
                          width: 200,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.skip_next),
                              label: Text(context.l10n.translate('autogiro.actions.simulateCharge')),
                            onPressed: !canEdit
                                ? null
                                : () async {
                                    await AutoGiroService.advanceCharge(g);
                                    _loadGiros();
                                  },
                          ),
                        ),
                        SizedBox(
                          width: 200,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.delete),
                              label: Text(context.l10n.translate('common.actions.delete')),
                            onPressed: !canEdit
                                ? null
                                : () async {
                                    await AutoGiroService.deleteAutoGiro(g.id);
                                    _loadGiros();
                                  },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _buildGiroReminderSummary(AutoGiro giro) {
    if (giro.isPaused) {
      return Text(context.l10n.translate('autogiro.reminders.paused'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]));
    }

    final now = DateTime.now();
    final rows = <Widget>[];

    final offsets = giro.reminderBeforeChargeDays.toSet().toList()..sort();
    for (final offset in offsets) {
      final scheduled = DateTime(giro.nextChargeAt.year, giro.nextChargeAt.month, giro.nextChargeAt.day).subtract(Duration(days: offset));
      final normalized = DateTime(scheduled.year, scheduled.month, scheduled.day, 9);
      final isFuture = normalized.isAfter(now);
      rows.add(Row(
        children: [
          Icon(isFuture ? Icons.schedule : Icons.check_circle, size: 16, color: isFuture ? AppColors.primary : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.l10n.translate('autogiro.reminders.chargeOffset', params: {'days': offset.toString()})} • ${_formatDate(context, normalized)}${isFuture ? '' : ' ${context.l10n.translate('common.labels.sent')}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ));
      rows.add(const SizedBox(height: 6));
    }

    if (giro.trialEnabled && giro.trialEndsAt != null && giro.reminderOnTrialEnd) {
      final normalized = DateTime(giro.trialEndsAt!.year, giro.trialEndsAt!.month, giro.trialEndsAt!.day, 9);
      final isFuture = normalized.isAfter(now);
      rows.add(Row(
        children: [
          Icon(isFuture ? Icons.notifications_active : Icons.check_circle, size: 16, color: isFuture ? AppColors.warning : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.l10n.translate('autogiro.reminders.trialEnds')} • ${_formatDate(context, normalized)}${isFuture ? '' : ' ${context.l10n.translate('common.labels.sent')}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ));
      rows.add(const SizedBox(height: 6));
    }

    final bindingEnds = giro.bindingEndsAt;
    if (bindingEnds != null) {
      final scheduled = DateTime(bindingEnds.year, bindingEnds.month, bindingEnds.day).subtract(const Duration(days: 30));
      final normalized = DateTime(scheduled.year, scheduled.month, scheduled.day, 9);
      final isFuture = normalized.isAfter(now);
      rows.add(Row(
        children: [
          Icon(isFuture ? Icons.schedule : Icons.check_circle, size: 16, color: isFuture ? AppColors.primary : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${context.l10n.translate('autogiro.reminders.bindingOffset', params: {'days': '30'})} • ${_formatDate(context, normalized)}${isFuture ? '' : ' ${context.l10n.translate('common.labels.sent')}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ));
      rows.add(const SizedBox(height: 6));
    }

    if (rows.isEmpty) {
      return Text(context.l10n.translate('autogiro.reminders.none'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Future<void> _showGiroDialog({AutoGiro? initial}) async {
    final isEditing = initial != null;
    final serviceController = TextEditingController(text: initial?.serviceName ?? '');
    final amountController = TextEditingController(
      text: initial != null ? initial.amountPerPeriod.toStringAsFixed(initial.amountPerPeriod % 1 == 0 ? 0 : 2) : '',
    );
    final notesController = TextEditingController(text: initial?.notes ?? '');
    final trialPriceController = TextEditingController(
      text: initial?.trialPrice != null
          ? initial!.trialPrice!.toStringAsFixed(initial.trialPrice! % 1 == 0 ? 0 : 2)
          : '',
    );

    String category = initial?.category ?? 'Entertainment';
    String interval = initial?.billingInterval ?? 'monthly';
    String paymentMethod = initial?.paymentMethod ?? 'card';
    DateTime nextCharge = initial?.nextChargeAt ?? DateTime.now().add(const Duration(days: 30));
    DateTime startDate = initial?.startDate ?? DateTime.now();
    bool trialEnabled = initial?.trialEnabled ?? false;
    DateTime? trialEndsAt = initial?.trialEndsAt;

    final bindingController = TextEditingController(text: initial?.bindingMonths?.toString() ?? '');
    final portalController = TextEditingController(text: initial?.portalUrl ?? '');
    List<int> chargeReminderDays = List<int>.from(initial?.reminderBeforeChargeDays ?? const [14, 1]);
    chargeReminderDays = chargeReminderDays.toSet().toList()..sort();
    bool chargeRemindersEnabled = chargeReminderDays.isNotEmpty;
    bool trialReminderEnabled = initial?.reminderOnTrialEnd ?? true;
    if (!trialEnabled) {
      trialReminderEnabled = false;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        Future<void> pickDate({
          required DateTime initialDate,
          required ValueChanged<DateTime> onSelected,
        }) async {
            final picked = await showDatePicker(
            context: dialogContext,
            initialDate: initialDate,
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
              locale: Localizations.localeOf(dialogContext),
          );
          if (picked != null) {
            onSelected(picked);
          }
        }

        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> handlePickNextCharge() async {
              await pickDate(
                initialDate: nextCharge,
                onSelected: (d) => setLocalState(() => nextCharge = d),
              );
            }

            Future<void> handlePickStartDate() async {
              await pickDate(
                initialDate: startDate,
                onSelected: (d) => setLocalState(() => startDate = d),
              );
            }

            Future<void> handlePickTrialEnds() async {
              await pickDate(
                initialDate: trialEndsAt ?? DateTime.now().add(const Duration(days: 7)),
                onSelected: (d) => setLocalState(() => trialEndsAt = d),
              );
            }

            return AlertDialog(
              title: Text(context.l10n.translate(isEditing ? 'autogiro.form.editTitle' : 'autogiro.form.addTitle')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: serviceController,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.service')),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.amount')),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.category')),
                      items: [
                        DropdownMenuItem(value: 'Entertainment', child: Text(context.l10n.translate('category.entertainment'))),
                        DropdownMenuItem(value: 'Health', child: Text(context.l10n.translate('category.health'))),
                        DropdownMenuItem(value: 'Insurance', child: Text(context.l10n.translate('category.insurance'))),
                        DropdownMenuItem(value: 'Software', child: Text(context.l10n.translate('category.software'))),
                        DropdownMenuItem(value: 'Other', child: Text(context.l10n.translate('category.other'))),
                      ],
                      onChanged: (v) => setLocalState(() => category = v ?? category),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: interval,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.interval')),
                      items: [
                        DropdownMenuItem(value: 'weekly', child: Text(context.l10n.translate('interval.weekly'))),
                        DropdownMenuItem(value: 'monthly', child: Text(context.l10n.translate('interval.monthly'))),
                        DropdownMenuItem(value: 'quarterly', child: Text(context.l10n.translate('interval.quarterly'))),
                        DropdownMenuItem(value: 'yearly', child: Text(context.l10n.translate('interval.yearly'))),
                      ],
                      onChanged: (v) => setLocalState(() => interval = v ?? interval),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.paymentMethod')),
                      items: [
                        DropdownMenuItem(value: 'card', child: Text(context.l10n.translate('payment.card'))),
                        DropdownMenuItem(value: 'autogiro', child: Text(context.l10n.translate('payment.autogiro'))),
                        DropdownMenuItem(value: 'invoice', child: Text(context.l10n.translate('payment.invoice'))),
                      ],
                      onChanged: (v) => setLocalState(() => paymentMethod = v ?? paymentMethod),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.translate('autogiro.form.nextCharge')),
                      subtitle: Text(_formatDate(context, nextCharge)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: handlePickNextCharge,
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.translate('autogiro.form.startDate')),
                      subtitle: Text(_formatDate(context, startDate)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: handlePickStartDate,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bindingController,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.bindingMonths')),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: portalController,
                      decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.portal')),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.translate('autogiro.form.trial.title')),
                      value: trialEnabled,
                      onChanged: (value) => setLocalState(() {
                        trialEnabled = value;
                        if (!trialEnabled) {
                          trialEndsAt = null;
                          trialPriceController.text = '';
                          trialReminderEnabled = false;
                        } else {
                          trialReminderEnabled = true;
                        }
                      }),
                    ),
                    if (trialEnabled) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.translate('autogiro.form.trial.ends')),
                        subtitle: Text(trialEndsAt != null ? _formatDate(context, trialEndsAt!) : context.l10n.translate('common.inputs.selectDate')),
                        trailing: const Icon(Icons.calendar_today),
                        onTap: handlePickTrialEnds,
                      ),
                      TextField(
                        controller: trialPriceController,
                        decoration: InputDecoration(labelText: context.l10n.translate('autogiro.form.trial.price')),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.translate('autogiro.form.trial.reminderTitle')),
                        subtitle: Text(context.l10n.translate('autogiro.form.trial.reminderSubtitle')),
                        value: trialReminderEnabled,
                        onChanged: (value) => setLocalState(() => trialReminderEnabled = value),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.l10n.translate('autogiro.form.chargeReminders.title')),
                      subtitle: Text(context.l10n.translate('autogiro.form.chargeReminders.subtitle')),
                      value: chargeRemindersEnabled,
                      onChanged: (value) => setLocalState(() {
                        chargeRemindersEnabled = value;
                        if (chargeRemindersEnabled && chargeReminderDays.isEmpty) {
                          chargeReminderDays = [1];
                        }
                      }),
                    ),
                    if (chargeRemindersEnabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: () {
                            final options = <int>{...chargeReminderDays, 1, 3, 7, 14, 30}.toList()..sort();
                            return options.map((offset) {
                              final isSelected = chargeReminderDays.contains(offset);
                              return FilterChip(
                                label: Text(context.l10n.translate('autogiro.reminders.beforeDays', params: {'days': offset.toString()})),
                                selected: isSelected,
                                onSelected: (selected) => setLocalState(() {
                                  if (selected) {
                                    final next = {...chargeReminderDays, offset}.toList()..sort();
                                    chargeReminderDays = next;
                                  } else {
                                    final next = List<int>.from(chargeReminderDays)..remove(offset);
                                    if (next.isEmpty) {
                                      chargeRemindersEnabled = false;
                                    }
                                    chargeReminderDays = next;
                                  }
                                }),
                              );
                            }).toList();
                          }(),
                        ),
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: notesController,
                      decoration: InputDecoration(labelText: context.l10n.translate('common.labels.notes')),
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(context.l10n.translate('common.cancel')),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amount = _parseAmount(amountController.text);
                    if (serviceController.text.trim().isEmpty || amount == null) {
                      return;
                    }

                    final trialPrice = trialEnabled ? _parseAmount(trialPriceController.text) : null;
                    final bindingText = bindingController.text.trim();
                    final binding = bindingText.isEmpty ? null : int.tryParse(bindingText);
                    final sanitizedNotes = notesController.text.trim().isEmpty ? null : notesController.text.trim();
                    final sanitizedPortal = portalController.text.trim().isEmpty ? null : portalController.text.trim();
                      final normalizedReminderDays = chargeRemindersEnabled
                          ? (chargeReminderDays.toSet().toList()..sort())
                          : <int>[];

                    if (isEditing) {
                      final updated = initial!.copyWith(
                        serviceName: serviceController.text.trim(),
                        category: category,
                        amountPerPeriod: amount,
                        billingInterval: interval,
                        paymentMethod: paymentMethod,
                        nextChargeAt: nextCharge,
                        startDate: startDate,
                        trialEnabled: trialEnabled,
                        trialEndsAt: trialEnabled ? trialEndsAt : null,
                        trialPrice: trialEnabled ? (trialPrice ?? 0) : null,
                        notes: sanitizedNotes,
                        portalUrl: sanitizedPortal,
                        bindingMonths: binding,
                          reminderBeforeChargeDays: normalizedReminderDays,
                          reminderOnTrialEnd: trialEnabled ? trialReminderEnabled : false,
                      );
                      await AutoGiroService.updateAutoGiro(updated);
                    } else {
                      final now = DateTime.now();
                      final newGiro = AutoGiro(
                        id: _uuid.v4(),
                        ownerId: widget.user.id,
                        serviceName: serviceController.text.trim(),
                        category: category,
                        amountPerPeriod: amount,
                        billingInterval: interval,
                        paymentMethod: paymentMethod,
                        nextChargeAt: nextCharge,
                        startDate: startDate,
                        trialEnabled: trialEnabled,
                        trialEndsAt: trialEnabled ? trialEndsAt : null,
                        trialPrice: trialEnabled ? (trialPrice ?? 0) : null,
                        notes: sanitizedNotes,
                        portalUrl: sanitizedPortal,
                        bindingMonths: binding,
                        createdAt: now,
                        updatedAt: now,
                          reminderBeforeChargeDays: normalizedReminderDays,
                          reminderOnTrialEnd: trialEnabled ? trialReminderEnabled : false,
                      );
                      await AutoGiroService.createAutoGiro(newGiro);
                    }

                    if (mounted) {
                      Navigator.of(dialogContext).pop();
                      _loadGiros();
                    }
                  },
                  child: Text(context.l10n.translate(isEditing ? 'common.actions.update' : 'common.save')),
                ),
              ],
            );
          },
        );
      },
    );

    serviceController.dispose();
    amountController.dispose();
    notesController.dispose();
    trialPriceController.dispose();
    bindingController.dispose();
    portalController.dispose();
  }

  double _calculateMonthlyTotal() {
    double total = 0.0;
    for (final g in _giros) {
      switch (g.billingInterval) {
        case 'weekly':
          total += g.amountPerPeriod * 4;
          break;
        case 'monthly':
          total += g.amountPerPeriod;
          break;
        case 'quarterly':
          total += g.amountPerPeriod / 3;
          break;
        case 'yearly':
          total += g.amountPerPeriod / 12;
          break;
      }
    }
    return total;
  }

  String _intervalLabel(String interval, BuildContext context) {
    switch (interval) {
      case 'weekly': return context.l10n.translate('interval.weekly');
      case 'monthly': return context.l10n.translate('interval.monthly');
      case 'quarterly': return context.l10n.translate('interval.quarterly');
      case 'yearly': return context.l10n.translate('interval.yearly');
      default: return interval;
    }
  }

  String _formatDate(BuildContext context, DateTime date) => formatDateShortLocalized(context, date);

  double? _parseAmount(String raw) {
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }
}
