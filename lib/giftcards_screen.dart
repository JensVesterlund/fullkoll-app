import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'utils/formatting.dart';

import 'barcode_parser.dart';
import 'models.dart';
import 'document_storage.dart';
import 'services/auth_supabase.dart';
import 'services/storage_service.dart';
import 'services.dart';
import 'theme.dart';
import 'ocr_service.dart';
import 'widgets/barcode_scanner_sheet.dart';
import 'widgets/dev_guest_banner.dart';
import 'widgets/offline_banner.dart';
import 'widgets/document_uploader.dart';
import 'components/sharing/permission_guard.dart';
import 'components/sharing/share_dialog.dart';
import 'components/sharing/share_status_chip.dart';
import 'i18n/app_localizations.dart';
import 'utils/error_handling.dart';
import 'utils/offline_cache.dart';

const _uuid = Uuid();

enum _GiftCardScanSource { camera, gallery }

class GiftCardsScreen extends StatefulWidget {
  final User user;
  final Future<void> Function()? onLogout;

  const GiftCardsScreen({super.key, required this.user, this.onLogout});

  @override
  State<GiftCardsScreen> createState() => _GiftCardsScreenState();
}

class _GiftCardsScreenState extends State<GiftCardsScreen> {
  List<GiftCard> _cards = [];
  bool _isLoading = true;
  bool _isProcessingExport = false;
  final Map<String, DateTime> _revealUntil = {};
  final Map<String, String?> _pinCache = {};

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  Future<void> _loadCards() async {
    setState(() => _isLoading = true);
    try {
      _cards = await GiftCardService.getAllGiftCards(widget.user.id, email: widget.user.email);
      setState(() => _isLoading = false);
      OfflineCache.writeJsonList('cache_giftcards_${widget.user.id}', _cards.map((e) => e.toJson()));
    } catch (e) {
      final cached = OfflineCache.readJsonList('cache_giftcards_${widget.user.id}', (m) => GiftCard.fromJson(m));
      if (cached.isNotEmpty) {
        _cards = cached;
        setState(() => _isLoading = false);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<List<GiftCardTransaction>> _loadCardTransactions(String cardId) => GiftCardService.getTransactions(cardId);

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.user.id == AuthService.guestUserId;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('giftcards.title'))),
      floatingActionButton: Semantics(
        label: l10n.translate('giftcards.form.addTitle'),
        button: true,
        child: FloatingActionButton(
          onPressed: () => _showAddCardDialog(),
          child: const Icon(Icons.add),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (isGuest) DevGuestBanner(onLogout: widget.onLogout),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _cards.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _cards.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return _buildActionRow(context.l10n);
                          }
                          return _buildCardItem(_cards[i - 1]);
                        },
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
        Icon(Icons.card_giftcard, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(context.l10n.translate('giftcards.empty.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.l10n.translate('giftcards.empty.subtitle'), style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  Widget _buildCardItem(GiftCard c) {
    final status = c.computedStatus;
    Color statusColor;
    String statusKey;
    switch (status) {
      case 'expiring':
        statusColor = AppColors.warning;
        statusKey = 'giftcards.status.expiring';
        break;
      case 'used':
        statusColor = Colors.grey;
        statusKey = 'giftcards.status.used';
        break;
      case 'expired':
        statusColor = AppColors.danger;
        statusKey = 'giftcards.status.expired';
        break;
      default:
        statusColor = AppColors.success;
        statusKey = 'giftcards.status.active';
    }

    final amountText = formatCurrencyLocalized(context, c.currentBalance, currency: c.currency, decimalDigits: 0);
    return Card(
      child: ListTile(
        leading: Icon(Icons.card_giftcard, color: statusColor),
        title: Text(c.brand),
        subtitle: Text(context.l10n.translate('giftcards.list.subtitle', params: {
          'amount': amountText,
          'masked': c.maskedCardNumber,
        })),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(context.l10n.translate(statusKey), style: TextStyle(color: statusColor, fontWeight: FontWeight.w600)),
        ),
        onTap: () => _showCardDetails(c),
      ),
    );
  }

  Widget _buildActionRow(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ElevatedButton.icon(
            onPressed: _isProcessingExport ? null : _exportGiftCardsCsv,
            icon: const Icon(Icons.table_view),
            label: Text(l10n.translate('export.csv.button')),
          ),
        ),
      );

  Future<void> _exportGiftCardsCsv() async {
    final l10n = context.l10n;
    setState(() => _isProcessingExport = true);
    try {
      await ExportService.exportGiftCardsCsv(user: widget.user);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.translate('export.csv.success'))));
    } on StateError catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'export_not_allowed' => l10n.translate('export.denied'),
        'export_no_rows' => l10n.translate('export.empty'),
        _ => l10n.translate('export.error', params: {'message': error.message}),
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error, stack) {
      if (!mounted) return;
      showFriendlyError(context, error, stack, userMessage: l10n.translate('errors.genericNetwork'), hint: 'giftcards_export');
    } finally {
      if (mounted) {
        setState(() => _isProcessingExport = false);
      }
    }
  }

  void _showCardDetails(GiftCard c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => FutureBuilder<List<GiftCardTransaction>>(
        future: _loadCardTransactions(c.id),
        builder: (context, snapshot) {
          final txs = snapshot.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.brand, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 4),
                          ShareStatusChip(resourceType: 'giftcard', resourceId: c.id),
                        ],
                      ),
                    ),
                    PermissionGuard(
                      user: widget.user,
                      resourceType: 'giftcard',
                      resourceId: c.id,
                      ownerId: c.ownerId,
                      requiredRole: ShareRoles.editor,
                      builder: (context, access) => IconButton(
                        tooltip: context.l10n.translate('common.actions.share'),
                        icon: const Icon(Icons.ios_share),
                        onPressed: () async {
                          await showDialog(
                            context: context,
                            builder: (_) => ShareDialog(
                              user: widget.user,
                              resourceType: 'giftcard',
                              resourceId: c.id,
                              resourceName: context.l10n.translate('giftcards.shareDialog.title', params: {'brand': c.brand}),
                              ownerId: c.ownerId,
                            ),
                          );
                        },
                      ),
                      fallback: const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDetailRow(context.l10n.translate('giftcards.detail.category'), c.category),
                _buildDetailRow(context.l10n.translate('giftcards.detail.balance'), '${c.currentBalance.toStringAsFixed(0)} ${c.currency}'),
                _buildDetailRow(context.l10n.translate('giftcards.detail.initialBalance'), '${c.initialBalance.toStringAsFixed(0)} ${c.currency}'),
                _buildSensitiveCardNumberRow(c),
                if (c.expiresAt != null) _buildDetailRow(context.l10n.translate('giftcards.detail.expiresAt'), _formatDate(context, c.expiresAt!)),
                if (c.notes != null) ...[const SizedBox(height: 16), Text(context.l10n.translate('common.labels.notes'), style: Theme.of(context).textTheme.labelLarge), Text(c.notes!)],
                const SizedBox(height: 24),
                Text(context.l10n.translate('giftcards.reminders.title'), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _buildGiftCardReminderSummary(c),
                const SizedBox(height: 24),
                Text(context.l10n.translate('giftcards.transactions.title'), style: Theme.of(context).textTheme.titleMedium),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
                else if (txs.isEmpty)
                  Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(context.l10n.translate('giftcards.transactions.empty'), style: Theme.of(context).textTheme.bodySmall))
                else
                  ...txs.map((tx) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.remove_circle, size: 20),
                        title: Text('-${tx.amount.toStringAsFixed(0)} ${c.currency}'),
                        subtitle: Text('${_formatDate(context, tx.date)} • ${tx.channel}'),
                      )),
                const SizedBox(height: 24),
                PermissionGuard(
                  user: widget.user,
                  resourceType: 'giftcard',
                  resourceId: c.id,
                  ownerId: c.ownerId,
                  requiredRole: ShareRoles.viewer,
                  builder: (context, access) {
                    final canEdit = access.canEdit;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: Text(context.l10n.translate('common.actions.edit')),
                          onPressed: canEdit
                              ? () async {
                                  Navigator.of(context).pop();
                                  await _showEditCardDialog(c);
                                }
                              : null,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.remove_circle),
                          label: Text(context.l10n.translate('giftcards.actions.use')),
                          onPressed: canEdit ? () => _showUseCardDialog(c) : null,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.delete),
                          label: Text(context.l10n.translate('common.actions.delete')),
                          onPressed: canEdit
                              ? () async {
                                  await GiftCardService.deleteGiftCard(c.id);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    _loadCards();
                                  }
                                }
                              : null,
                        ),
                      ],
                    );
                  },
                ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  bool _isRevealed(String cardId) {
    final until = _revealUntil[cardId];
    if (until == null) return false;
    if (DateTime.now().isBefore(until)) return true;
    _revealUntil.remove(cardId);
    return false;
  }

  Widget _buildSensitiveCardNumberRow(GiftCard c) {
    final revealed = _isRevealed(c.id);
    final numberText = revealed ? c.cardNumber : c.maskedCardNumber;
    final pin = revealed ? _pinCache[c.id] : null;
    final l10n = context.l10n;

    Future<void> handleReveal() async {
      final ok = await SensitiveAuth.ensureUnlocked(context, widget.user);
      if (!ok) return;
      String? pinValue;
      try {
        pinValue = await GiftCardService.revealPin(user: widget.user, cardId: c.id);
      } catch (_) {}
      setState(() {
        _pinCache[c.id] = pinValue;
        _revealUntil[c.id] = DateTime.now().add(const Duration(seconds: 60));
      });
      // Schedule auto-hide update just after TTL
      Future.delayed(const Duration(seconds: 61), () {
        if (!mounted) return;
        if (!_isRevealed(c.id)) setState(() {});
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('giftcards.detail.cardNumber'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        numberText,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PermissionGuard(
                      user: widget.user,
                      resourceType: 'giftcard',
                      resourceId: c.id,
                      ownerId: c.ownerId,
                      requiredRole: 'sensitive',
                      fallback: const SizedBox.shrink(),
                      builder: (ctx, access) => OutlinedButton.icon(
                        icon: Icon(revealed ? Icons.visibility_off : Icons.visibility),
                        label: Text(revealed ? l10n.translate('sensitive.hide') : l10n.translate('sensitive.show60')),
                        onPressed: revealed
                            ? () => setState(() => _revealUntil.remove(c.id))
                            : handleReveal,
                      ),
                    ),
                  ],
                ),
                if (pin != null && pin.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('PIN:', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(width: 6),
                      Text(pin, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGiftCardReminderSummary(GiftCard card) {
    if (!card.remindersEnabled) {
      return Text(context.l10n.translate('giftcards.reminders.offSummary'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]));
    }

    if (card.expiresAt == null) {
      return Text(context.l10n.translate('giftcards.reminders.needExpiry'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]));
    }

    final now = DateTime.now();
    final expires = card.expiresAt!;
    final rows = <Widget>[];

    for (final offset in const [30, 7]) {
      final scheduled = DateTime(expires.year, expires.month, expires.day).subtract(Duration(days: offset));
      final normalized = DateTime(scheduled.year, scheduled.month, scheduled.day, 9);
      final isFuture = normalized.isAfter(now);
      rows.add(Row(
        children: [
          Icon(isFuture ? Icons.schedule : Icons.check_circle, size: 16, color: isFuture ? AppColors.primary : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.translate('giftcards.reminders.row', params: {
                'days': offset,
                'date': _formatDate(context, normalized),
                'sent': isFuture ? '' : ' ${context.l10n.translate('common.labels.sent')}',
              }),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ));
      rows.add(const SizedBox(height: 6));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  void _showAddCardDialog() => _showCardFormDialog();

  Future<void> _showEditCardDialog(GiftCard card) => _showCardFormDialog(existing: card);

  Future<void> _showCardFormDialog({GiftCard? existing}) async {
    final isEdit = existing != null;
    GiftCard? draft = existing;
    String? resolvedPin;

    if (isEdit) {
      final latest = await GiftCardService.getGiftCard(existing!.id);
      draft = latest ?? existing;
      // For security, do not prefill existing PIN. Require re-entry to change.
      resolvedPin = '';
    }

    final brandController = TextEditingController(text: draft?.brand ?? '');
    final cardNumberController = TextEditingController(text: draft?.cardNumber ?? '');
    final pinController = TextEditingController(text: resolvedPin ?? '');
    final balanceController = TextEditingController(
      text: isEdit ? draft!.initialBalance.toStringAsFixed(2) : '',
    );
    final currentBalanceController = TextEditingController(
      text: isEdit ? draft!.currentBalance.toStringAsFixed(2) : '',
    );

    String category = draft?.category ?? 'Entertainment';
    DateTime? expiresAt = draft?.expiresAt;
    String entryMode = 'manual';
    GiftCardOcrResult? ocrResult;
    bool isAnalyzing = false;
    String? ocrFeedback;
    DocumentUploadState documentState = const DocumentUploadState();
    bool brandConfirmed = true;
    bool cardNumberConfirmed = true;
    bool balanceConfirmed = true;
    bool expiresConfirmed = true;
    bool remindersEnabled = draft?.remindersEnabled ?? false;

    final initialDocument = draft?.documents.isNotEmpty == true ? draft!.documents.first : null;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) {
          final l10n = context.l10n;
          InputDecoration withOcrDecoration(String label, OcrSuggestion<dynamic>? suggestion, bool isConfirmed) {
            final showWarning = suggestion != null && suggestion.value != null && !suggestion.isConfident && !isConfirmed;
            return InputDecoration(
              labelText: label,
              helperText: showWarning ? l10n.translate('ocr.warning.unconfident') : null,
              helperStyle: showWarning
                  ? Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning)
                  : null,
              suffixIcon: showWarning ? const Icon(Icons.info_outline, color: AppColors.warning) : null,
            );
          }

          Widget buildUncertainHint(String fieldName, VoidCallback onConfirm) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.translate('ocr.warning.field', params: {'field': fieldName}),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton(onPressed: onConfirm, child: Text(l10n.translate('common.actions.confirm'))),
                ],
              ),
            );
          }

          Future<_GiftCardScanSource?> selectScanSource() async {
            return showModalBottomSheet<_GiftCardScanSource>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.camera_alt_outlined),
                      title: Text(l10n.translate('common.inputs.camera')),
                      onTap: () => Navigator.of(sheetContext).pop(_GiftCardScanSource.camera),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(l10n.translate('common.inputs.pickImage')),
                      onTap: () => Navigator.of(sheetContext).pop(_GiftCardScanSource.gallery),
                    ),
                  ],
                ),
              ),
            );
          }

          Future<void> applyOcr(Uint8List bytes, String fileName) async {
            setLocalState(() {
              entryMode = 'scan';
                isAnalyzing = true;
              ocrFeedback = null;
            });

            try {
              final result = await OcrService.analyzeGiftCard(bytes: bytes, fileName: fileName);

              if (!result.hasAnyData) {
                setLocalState(() {
                  isAnalyzing = false;
                  ocrResult = null;
                  brandConfirmed = true;
                  cardNumberConfirmed = true;
                  balanceConfirmed = true;
                  expiresConfirmed = true;
                  ocrFeedback = l10n.translate('ocr.feedback.none');
                });
                return;
              }

              if (result.brand.value != null) {
                brandController.text = result.brand.value!;
              }
              if (result.cardNumber.value != null) {
                cardNumberController.text = result.cardNumber.value!;
              }
              if (result.amount.value != null) {
                final formatted = result.amount.value!.toStringAsFixed(2);
                balanceController.text = formatted;
                currentBalanceController.text = formatted;
              }
              if (result.expiresAt.value != null) {
                expiresAt = result.expiresAt.value!;
              }

                setLocalState(() {
                isAnalyzing = false;
                ocrResult = result;
                brandConfirmed = result.brand.value == null ? true : result.brand.isConfident;
                cardNumberConfirmed = result.cardNumber.value == null ? true : result.cardNumber.isConfident;
                balanceConfirmed = result.amount.value == null ? true : result.amount.isConfident;
                expiresConfirmed = result.expiresAt.value == null ? true : result.expiresAt.isConfident;
                  ocrFeedback = l10n.translate('ocr.feedback.populated');
              });
            } catch (_) {
                setLocalState(() {
                isAnalyzing = false;
                ocrResult = null;
                brandConfirmed = true;
                cardNumberConfirmed = true;
                balanceConfirmed = true;
                expiresConfirmed = true;
                  ocrFeedback = l10n.translate('ocr.feedback.none');
              });
            }
          }

          Future<void> startScan() async {
            final source = await selectScanSource();
            if (source == null) return;

            final picker = ImagePicker();
            XFile? file;
            try {
              file = await picker.pickImage(
                source: source == _GiftCardScanSource.camera ? ImageSource.camera : ImageSource.gallery,
                imageQuality: 85,
              );
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.translate('errors.cameraUnavailable'))),
                );
              }
              return;
            }

            if (file == null) return;

            final bytes = await file.readAsBytes();
            await applyOcr(bytes, file.name);
          }

          Future<void> startBarcodeScan() async {
            final raw = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (_) => BarcodeScannerSheet(
                title: l10n.translate('giftcards.form.scan.sheetTitle'),
                description: l10n.translate('giftcards.form.scan.sheetDescription'),
              ),
            );

            if (raw == null) return;

            final parsed = BarcodeParser.parseGiftCard(raw);

            setLocalState(() {
              entryMode = 'scan';
              ocrResult = null;
              ocrFeedback = parsed.hasAny
                  ? l10n.translate('giftcards.scan.success')
                  : l10n.translate('giftcards.scan.unknown');

              if (parsed.brand != null) {
                brandController.text = parsed.brand!;
                brandConfirmed = true;
              }
              if (parsed.cardNumber != null) {
                cardNumberController.text = parsed.cardNumber!;
                cardNumberConfirmed = true;
              }
              if (parsed.pin != null) {
                pinController.text = parsed.pin!;
              }
              if (parsed.balance != null) {
                final formatted = parsed.balance!.toStringAsFixed(2);
                balanceController.text = formatted;
                currentBalanceController.text = formatted;
                balanceConfirmed = true;
              }
              if (parsed.expiresAt != null) {
                expiresAt = parsed.expiresAt!;
                expiresConfirmed = true;
              }
            });

            if (!parsed.hasAny && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.translate('giftcards.scan.unsupported'))),
              );
            }
          }

          return AlertDialog(
            title: Text(isEdit ? l10n.translate('giftcards.form.editTitle') : l10n.translate('giftcards.form.addTitle')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ToggleButtons(
                    isSelected: ['scan', 'manual'].map((mode) => entryMode == mode).toList(),
                    borderRadius: BorderRadius.circular(8),
                    onPressed: (index) {
                      setLocalState(() {
                        entryMode = index == 0 ? 'scan' : 'manual';
                        if (entryMode == 'manual') {
                          brandConfirmed = true;
                          cardNumberConfirmed = true;
                          balanceConfirmed = true;
                          expiresConfirmed = true;
                          ocrResult = null;
                          ocrFeedback = null;
                        }
                      });
                    },
                    children: [
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l10n.translate('common.entry.scan'))),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(l10n.translate('common.entry.manual'))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (entryMode == 'scan') ...[
                    ElevatedButton.icon(
                      icon: const Icon(Icons.document_scanner_outlined),
                      onPressed: isAnalyzing ? null : startScan,
                      label: Text(l10n.translate('giftcards.form.actions.startOcr')),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: isAnalyzing ? null : startBarcodeScan,
                      label: Text(l10n.translate('giftcards.form.actions.scanCode')),
                    ),
                    const SizedBox(height: 12),
                    if (isAnalyzing)
                      Row(
                        children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 12),
                          Expanded(child: Text(l10n.translate('giftcards.form.status.analyzing'))),
                        ],
                      ),
                    if (!isAnalyzing && ocrFeedback != null)
                      Text(ocrFeedback!, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: brandController,
                    decoration: withOcrDecoration(l10n.translate('giftcards.form.brand'), ocrResult?.brand, brandConfirmed),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onChanged: (_) {
                      if (!brandConfirmed) {
                        setLocalState(() => brandConfirmed = true);
                      }
                    },
                  ),
                  if (((ocrResult?.brand)?.hasValue ?? false) && !(((ocrResult?.brand)?.isConfident ?? true)) && !brandConfirmed)
                    buildUncertainHint(l10n.translate('giftcards.form.brand').toLowerCase(), () => setLocalState(() => brandConfirmed = true)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: cardNumberController,
                    decoration: withOcrDecoration(l10n.translate('giftcards.form.cardNumber'), ocrResult?.cardNumber, cardNumberConfirmed),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    onChanged: (_) {
                      if (!cardNumberConfirmed) {
                        setLocalState(() => cardNumberConfirmed = true);
                      }
                    },
                  ),
                  if (((ocrResult?.cardNumber)?.hasValue ?? false) && !(((ocrResult?.cardNumber)?.isConfident ?? true)) && !cardNumberConfirmed)
                    buildUncertainHint(l10n.translate('giftcards.form.cardNumber').toLowerCase(), () => setLocalState(() => cardNumberConfirmed = true)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: pinController,
                    decoration: InputDecoration(
                      labelText: isEdit ? l10n.translate('giftcards.form.pinReset') : l10n.translate('giftcards.form.pinOptional'),
                    ),
                    textInputAction: TextInputAction.next,
                    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  ),
                  const SizedBox(height: 16),
                  if (isEdit) ...[
                    TextField(
                      controller: balanceController,
                      decoration: withOcrDecoration(l10n.translate('giftcards.form.initialBalance'), ocrResult?.amount, balanceConfirmed),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                      onChanged: (_) {
                        if (!balanceConfirmed) {
                          setLocalState(() => balanceConfirmed = true);
                        }
                      },
                    ),
                    if (((ocrResult?.amount)?.hasValue ?? false) && !(((ocrResult?.amount)?.isConfident ?? true)) && !balanceConfirmed)
                      buildUncertainHint(l10n.translate('giftcards.form.initialBalance').toLowerCase(), () => setLocalState(() => balanceConfirmed = true)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: currentBalanceController,
                      decoration: InputDecoration(labelText: l10n.translate('giftcards.form.currentBalance')),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                    ),
                    const SizedBox(height: 16),
                  ] else ...[
                    TextField(
                      controller: balanceController,
                      decoration: withOcrDecoration(l10n.translate('giftcards.form.balance'), ocrResult?.amount, balanceConfirmed),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (_) {
                        if (!balanceConfirmed) {
                          setLocalState(() => balanceConfirmed = true);
                        }
                      },
                    ),
                    if (((ocrResult?.amount)?.hasValue ?? false) && !(((ocrResult?.amount)?.isConfident ?? true)) && !balanceConfirmed)
                      buildUncertainHint(l10n.translate('giftcards.form.balance').toLowerCase(), () => setLocalState(() => balanceConfirmed = true)),
                    const SizedBox(height: 16),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      l10n.translate('giftcards.form.expiresAt'),
                      style: (((ocrResult?.expiresAt)?.hasValue ?? false) && !(((ocrResult?.expiresAt)?.isConfident ?? true)) && !expiresConfirmed)
                          ? Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.warning)
                          : Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      expiresAt != null ? _formatDate(context, expiresAt!) : l10n.translate('common.inputs.selectDate'),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (expiresAt != null)
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: l10n.translate('common.actions.clearDate'),
                            onPressed: () => setLocalState(() {
                              expiresAt = null;
                              remindersEnabled = false;
                              expiresConfirmed = true;
                            }),
                          ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () async {
                            final initialDate = expiresAt ?? DateTime.now().add(const Duration(days: 30));
                             final picked = await showDatePicker(
                              context: context,
                              initialDate: initialDate,
                              firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                              lastDate: DateTime.now().add(const Duration(days: 3650)),
                               locale: Localizations.localeOf(context),
                            );
                            if (picked != null) {
                              setLocalState(() {
                                expiresAt = picked;
                                expiresConfirmed = true;
                                if (!remindersEnabled) {
                                  remindersEnabled = true;
                                }
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  if (((ocrResult?.expiresAt)?.hasValue ?? false) && !(((ocrResult?.expiresAt)?.isConfident ?? true)) && !expiresConfirmed)
                    buildUncertainHint(l10n.translate('giftcards.form.expiresAt').toLowerCase(), () => setLocalState(() => expiresConfirmed = true)),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.translate('giftcards.form.reminders.title')),
                    subtitle: Text(
                      expiresAt == null
                          ? l10n.translate('giftcards.form.reminders.hintMissing')
                          : l10n.translate('giftcards.form.reminders.hintEnabled'),
                    ),
                    value: remindersEnabled,
                    onChanged: (value) {
                      if (expiresAt == null && value) {
                        _showSnack(l10n.translate('giftcards.form.reminders.needDate'));
                        return;
                      }
                      setLocalState(() => remindersEnabled = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: InputDecoration(labelText: l10n.translate('giftcards.form.category')),
                    items: ['Entertainment', 'Shopping', 'Food', 'Sports', 'Other'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => category = v!,
                  ),
                  const SizedBox(height: 16),
                  DocumentUploader(
                    uploadLabel: isEdit ? l10n.translate('giftcards.form.upload.update') : l10n.translate('giftcards.form.upload.new'),
                    initialUrl: initialDocument?.url ?? draft?.imageUrl,
                    initialFileName: initialDocument?.name,
                    onChanged: (state) => documentState = state,
                    onOcr: applyOcr,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.translate('common.cancel'))),
              ElevatedButton(
                onPressed: () async {
                  final brand = brandController.text.trim();
                  final cardNumber = cardNumberController.text.trim();
                  if (brand.isEmpty) {
                    _showSnack(l10n.translate('errors.required', params: {'field': l10n.translate('giftcards.form.brand')}));
                    return;
                  }
                  if (cardNumber.isEmpty) {
                    _showSnack(l10n.translate('errors.required', params: {'field': l10n.translate('giftcards.form.cardNumber')}));
                    return;
                  }

                  if (isEdit) {
                    final initialBalance = _parseAmount(balanceController.text);
                    final currentBalance = _parseAmount(currentBalanceController.text);
                    if (initialBalance == null || initialBalance < 0) {
                      _showSnack(l10n.translate('errors.minValue', params: {'field': l10n.translate('giftcards.form.initialBalance'), 'min': '0'}));
                      return;
                    }
                    if (currentBalance == null || currentBalance < 0) {
                      _showSnack(l10n.translate('errors.minValue', params: {'field': l10n.translate('giftcards.form.currentBalance'), 'min': '0'}));
                      return;
                    }

                    final document = await _resolveGiftCardDocument(
                      state: documentState,
                      ownerId: draft!.ownerId,
                      existingDocuments: draft!.documents,
                    );

                    final normalizedStatus = currentBalance <= 0
                        ? 'used'
                        : (expiresAt != null && expiresAt!.isBefore(DateTime.now()) ? 'expired' : 'active');

                    final updatedDocuments = document != null
                        ? [document]
                        : (documentState.removeExisting ? const <GiftCardDocument>[] : draft!.documents);
                    final updatedImageUrl = document != null
                        ? document.url
                        : (documentState.removeExisting ? null : draft!.imageUrl);

                    final updated = draft!.copyWith(
                      brand: brand,
                      category: category,
                      expiresAt: expiresAt,
                      cardNumber: cardNumber,
                      pin: pinController.text.trim().isEmpty ? null : pinController.text.trim(),
                      initialBalance: initialBalance,
                      currentBalance: currentBalance,
                      status: normalizedStatus,
                      imageUrl: updatedImageUrl,
                      documents: updatedDocuments,
                      remindersEnabled: remindersEnabled,
                    );

                    await GiftCardService.updateGiftCard(updated);
                  } else {
                    final balance = _parseAmount(balanceController.text);
                    if (balance == null || balance <= 0) {
                      _showSnack('Ange ett giltigt saldo.');
                      return;
                    }
                    final now = DateTime.now();
                    final document = await _resolveGiftCardDocument(
                      state: documentState,
                      ownerId: widget.user.id,
                        existingDocuments: const <GiftCardDocument>[],
                    );
                    final card = GiftCard(
                      id: _uuid.v4(),
                      ownerId: widget.user.id,
                      brand: brand,
                      category: category,
                      cardNumber: cardNumber,
                      pin: pinController.text.trim().isEmpty ? null : pinController.text.trim(),
                      initialBalance: balance,
                      currentBalance: balance,
                      expiresAt: expiresAt,
                      createdAt: now,
                      updatedAt: now,
                      imageUrl: document?.url,
                      documents: document != null ? [document] : const <GiftCardDocument>[],
                      remindersEnabled: remindersEnabled,
                    );
                    await GiftCardService.createGiftCard(card);
                  }

                  if (mounted) {
                    Navigator.of(dialogContext).pop();
                    await _loadCards();
                    _showSnack(isEdit ? l10n.translate('giftcards.feedback.updated') : l10n.translate('giftcards.feedback.saved'));
                  }
                },
                child: Text(isEdit ? l10n.translate('common.actions.update') : l10n.translate('common.save')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showUseCardDialog(GiftCard card) async {
    final amountController = TextEditingController();

    final used = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.translate('giftcards.useDialog.title')),
        content: TextField(
          controller: amountController,
          decoration: InputDecoration(labelText: context.l10n.translate('giftcards.useDialog.amountLabel')),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.translate('common.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = _parseAmount(amountController.text);
              if (amount == null || amount <= 0) {
                _showSnack(context.l10n.translate('errors.invalidAmount'));
                return;
              }

              final latestCard = await GiftCardService.getGiftCard(card.id) ?? card;
              if (amount > latestCard.currentBalance) {
                _showSnack(context.l10n.translate('giftcards.useDialog.amountTooHigh'));
                return;
              }

              final tx = GiftCardTransaction(
                id: _uuid.v4(),
                giftCardId: card.id,
                date: DateTime.now(),
                amount: amount,
                channel: 'butik',
              );

              await GiftCardService.addTransaction(tx, latestCard);
              if (mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: Text(context.l10n.translate('giftcards.actions.use')),
          ),
        ],
      ),
    );

    if (used == true && mounted) {
      Navigator.of(context).pop();
      await _loadCards();
      _showSnack(context.l10n.translate('giftcards.feedback.balanceUpdated'));
    }
  }

  String _formatDate(BuildContext context, DateTime date) => formatDateShortLocalized(context, date);

  double? _parseAmount(String raw) {
    final normalized = raw
        .trim()
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll(',', '.');
    if (normalized.isEmpty || normalized == '-' || normalized == '.') {
      return null;
    }
    return double.tryParse(normalized);
  }

  Future<GiftCardDocument?> _resolveGiftCardDocument({
    required DocumentUploadState state,
    required String ownerId,
    List<GiftCardDocument> existingDocuments = const <GiftCardDocument>[],
  }) async {
    if (state.pendingFile != null) {
      final sbUser = SupabaseAuthAdapter.currentAppUserSync();
      // Remove all existing local documents
      for (final doc in existingDocuments) {
        if (doc.url.startsWith('secure://')) {
          await DocumentStorage.deleteDocument(doc.url);
        }
      }

      if (sbUser != null) {
        // Upload to Supabase Storage 'documents' bucket
        final signedUrl = await StorageService().upload(
          file: state.pendingFile!.bytes,
          bucket: 'documents',
          folder: ownerId,
          fileName: state.pendingFile!.fileName,
        );
        return GiftCardDocument(
          id: const Uuid().v4(),
          name: state.pendingFile!.fileName,
          url: signedUrl,
          mimeType: state.pendingFile!.mimeType,
          size: state.pendingFile!.bytes.length,
          uploadedAt: DateTime.now(),
        );
      } else {
        // Local secure-storage fallback
        final stored = await DocumentStorage.saveDocument(
          ownerId: ownerId,
          module: 'giftcards',
          originalName: state.pendingFile!.fileName,
          mimeType: state.pendingFile!.mimeType,
          bytes: state.pendingFile!.bytes,
        );
        return GiftCardDocument(
          id: stored.id,
          name: stored.name,
          url: stored.url,
          mimeType: stored.mimeType,
          size: stored.size,
          uploadedAt: stored.createdAt,
        );
      }
    }

    if (state.removeExisting) {
      for (final doc in existingDocuments) {
        if (doc.url.startsWith('secure://')) {
          await DocumentStorage.deleteDocument(doc.url);
        }
      }
      return null;
    }

    return existingDocuments.isNotEmpty ? existingDocuments.first : null;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
