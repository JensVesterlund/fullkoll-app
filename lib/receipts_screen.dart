import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

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
import 'widgets/placeholder_views.dart';
import 'utils/debouncer.dart';
import 'utils/error_handling.dart';
import 'utils/formatting.dart';
import 'utils/offline_cache.dart';

const _uuid = Uuid();

const Map<String, List<String>> _budgetCategoryKeywords = {
  'mat': ['ica', 'coop', 'hemköp', 'hemkop', 'wil', 'lidl', 'pressbyrån', 'pressbyran', 'city gross', 'mathem', 'maxi', 'axfood', 'hemköp', 'daglivs'],
  'transport': ['sl', 'uber', 'bolt', 'taxi', 'sj', 'mtr', 'shell', 'circle k', 'preem', 'okq8', 'qstar', 'bensin', 'flygbuss', 'flixbus', 'flygtaxi'],
  'nöje': ['spotify', 'netflix', 'disney', 'viaplay', 'hbomax', 'hbo', 'sf', 'bio', 'ticketmaster', 'game', 'steam', 'cinema', 'konsert', 'eventim'],
  'boende': ['ikea', 'bauhaus', 'clas ohlson', 'jula', 'hornbach', 'byggmax', 'plantagen', 'elgiganten home', 'hemtex', 'möbel', 'mobel', 'k-rauta', 'k-rauta', 'mio'],
  'kläder': ['h&m', 'hm', 'zara', 'kappahl', 'lindex', 'arket', 'cos', 'stadium', 'foot locker', 'dressmann', 'weekday', 'gina tricot'],
  'hälsa': ['apotek', 'vitamin', 'life', 'gym', 'fitness', 'friskis', 'wellness', 'vård', 'vard', 'läkar', 'lakar', 'naprapat'],
  'teknik': ['apple', 'elgiganten', 'mediamarkt', 'media markt', 'netonnet', 'webhallen', 'komplett', 'teknikmagasinet', 'kjell'],
  'resor': ['sas', 'norwegian', 'ryanair', 'tui', 'sj', 'vy', 'flyg', 'hotell', 'hotel', 'booking', 'airbnb', 'expedia', 'apollo', 'fritidsresor'],
};

const Map<String, String> _receiptCategoryToBudgetName = {
  'Electronics': 'Övrigt',
  'Clothes': 'Kläder',
  'Home': 'Boende',
  'Food': 'Mat',
  'Other': 'Övrigt',
};

enum _ReceiptScanSource { camera, gallery }

class ReceiptsScreen extends StatefulWidget {
  final User user;
  final Future<void> Function()? onLogout;

  const ReceiptsScreen({super.key, required this.user, this.onLogout});

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  List<Receipt> _receipts = [];
  List<Receipt> _allReceipts = [];
  bool _isLoading = true;
  String? _loadError;
  List<Budget> _budgets = [];
  Budget? _primaryBudget;
  Map<String, List<BudgetCategory>> _categoriesByBudget = {};
  bool _isProcessingExport = false;
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _searchDebouncer = Debouncer();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadReceipts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebouncer.dispose();
    super.dispose();
  }

  Future<void> _loadReceipts() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final receipts = await ReceiptService.getAllReceipts(widget.user.id, email: widget.user.email);
      final budgets = await BudgetService.getAllBudgets(widget.user.id, email: widget.user.email);
      final categoriesByBudget = <String, List<BudgetCategory>>{};
      for (final budget in budgets) {
        categoriesByBudget[budget.id] = await BudgetService.getCategories(budget.id);
      }
      if (!mounted) return;
      setState(() {
        _allReceipts = receipts;
        _receipts = _filterReceipts(receipts, _searchQuery);
        _budgets = budgets;
        _categoriesByBudget = categoriesByBudget;
        _primaryBudget = budgets.isNotEmpty ? budgets.first : null;
        _isLoading = false;
      });
      // Cache for offline use
      OfflineCache.writeJsonList('cache_receipts_${widget.user.id}', _allReceipts.map((e) => e.toJson()));
      OfflineCache.writeJsonList('cache_budgets_${widget.user.id}', _budgets.map((e) => e.toJson()));
      final catsPayload = <String, dynamic>{
        for (final entry in _categoriesByBudget.entries)
          entry.key: entry.value.map((c) => c.toJson()).toList(),
      };
      OfflineCache.writeJson('cache_budget_cats_${widget.user.id}', catsPayload);
    } catch (error) {
      if (!mounted) return;
      final cachedReceipts = OfflineCache.readJsonList('cache_receipts_${widget.user.id}', (m) => Receipt.fromJson(m));
      final cachedBudgets = OfflineCache.readJsonList('cache_budgets_${widget.user.id}', (m) => Budget.fromJson(m));
      final cachedCatsMap = OfflineCache.readJson<Map<String, dynamic>>('cache_budget_cats_${widget.user.id}', (m) => m);
      if (cachedReceipts.isNotEmpty || cachedBudgets.isNotEmpty) {
        final categoriesByBudget = <String, List<BudgetCategory>>{};
        if (cachedCatsMap != null) {
          for (final entry in cachedCatsMap.entries) {
            final list = (entry.value as List?) ?? const [];
            categoriesByBudget[entry.key] = list
                .map((e) => BudgetCategory.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList();
          }
        }
        setState(() {
          _allReceipts = cachedReceipts;
          _receipts = _filterReceipts(cachedReceipts, _searchQuery);
          _budgets = cachedBudgets;
          _categoriesByBudget = categoriesByBudget;
          _primaryBudget = cachedBudgets.isNotEmpty ? cachedBudgets.first : null;
          _isLoading = false;
          _loadError = null;
        });
      } else {
        setState(() {
          _loadError = error.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<Receipt> _filterReceipts(List<Receipt> source, String query) {
    if (query.isEmpty) {
      return List<Receipt>.from(source);
    }
    final q = query;
    return source.where((receipt) {
      final haystack = [
        receipt.store,
        receipt.category,
        receipt.notes ?? '',
        receipt.currency,
      ].join(' ').toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  void _handleSearchChanged(String value) {
    _searchDebouncer(() {
      if (!mounted) return;
      final query = value.trim().toLowerCase();
      setState(() {
        _searchQuery = query;
        _receipts = _filterReceipts(_allReceipts, _searchQuery);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isGuest = widget.user.id == AuthService.guestUserId;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('receipts.title'))),
      floatingActionButton: Semantics(
        label: l10n.translate('receipts.form.addTitle'),
        button: true,
        child: FloatingActionButton(
          onPressed: () => _showReceiptDialog(),
          tooltip: l10n.translate('receipts.form.addTitle'),
          child: const Icon(Icons.add),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          if (isGuest) DevGuestBanner(onLogout: widget.onLogout),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadReceipts,
              child: _buildContent(context, l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppLocalizations l10n) {
    if (_isLoading) {
      return _buildScrollablePlaceholder(
        Padding(
          padding: const EdgeInsets.only(top: 96),
          child: LoadingPlaceholder(message: l10n.translate('common.status.loading')),
        ),
      );
    }

    if (_loadError != null) {
      return _buildScrollablePlaceholder(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ErrorPlaceholder(
            message: l10n.translate('common.status.error'),
            onRetry: _loadReceipts,
            retryLabel: l10n.translate('common.actions.retry'),
          ),
        ),
      );
    }

    if (_receipts.isEmpty) {
      if (_allReceipts.isEmpty) {
        return _buildScrollablePlaceholder(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: EmptyPlaceholder(
              icon: Icons.receipt_long,
              title: l10n.translate('receipts.empty.heading'),
              description: l10n.translate('receipts.empty.description'),
              primaryLabel: l10n.translate('receipts.empty.cta'),
              onPrimaryPressed: _showReceiptDialog,
            ),
          ),
        );
      }

      return _buildScrollablePlaceholder(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: EmptyPlaceholder(
            icon: Icons.search_off,
            title: l10n.translate('receipts.search.emptyTitle'),
            description: l10n.translate('receipts.search.emptyDescription'),
            primaryLabel: l10n.translate('receipts.search.clear'),
            onPrimaryPressed: () {
              _searchController.clear();
              _handleSearchChanged('');
            },
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _receipts.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildSearchField(l10n);
        }
        if (index == 1) {
          return _buildActionRow(context, l10n);
        }
        final receipt = _receipts[index - 2];
        return _buildReceiptCard(context, l10n, receipt);
      },
    );
  }

  Widget _buildScrollablePlaceholder(Widget child) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 32),
          child,
          const SizedBox(height: 32),
        ],
      );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Inga kvitton', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Tryck på + för att lägga till ditt första kvitto', style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  Widget _buildReceiptCard(BuildContext context, AppLocalizations l10n, Receipt r) {
    final badge = r.statusBadge;
    final badgeColor = badge == 'ok' ? AppColors.success : (badge == 'dueSoon' ? AppColors.warning : AppColors.danger);
    final badgeTextKey = badge == 'ok'
        ? 'receipts.badge.ok'
        : (badge == 'dueSoon' ? 'receipts.badge.dueSoon' : 'receipts.badge.passed');
    final budgetCategoryLabel = _categoryNameForId(r.budgetCategoryId, budgetId: r.budgetId);
    final subtitleParts = [
      _formatDateLocalized(context, r.purchaseDate),
      '${r.amount.toStringAsFixed(0)} ${r.currency}',
      budgetCategoryLabel ?? r.category,
    ];
    if (budgetCategoryLabel != null) {
      subtitleParts.add(l10n.translate('receipts.list.budgetLinked'));
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReceiptDetails(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.receipt_long, color: AppColors.primary.withValues(alpha: 0.9)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.store,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitleParts.join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.translate(badgeTextKey),
                      style: TextStyle(color: badgeColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ShareStatusChip(resourceType: 'receipt', resourceId: r.id),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          ElevatedButton.icon(
            onPressed: _isProcessingExport ? null : _exportReceiptsCsv,
            icon: const Icon(Icons.table_view),
            label: Text(l10n.translate('export.csv.button')),
          ),
          OutlinedButton.icon(
            onPressed: _showImportDialog,
            icon: const Icon(Icons.file_upload),
            label: Text(l10n.translate('import.csv.button')),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TextField(
        controller: _searchController,
        onChanged: _handleSearchChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          labelText: l10n.translate('receipts.search.label'),
          hintText: l10n.translate('receipts.search.hint'),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.translate('receipts.search.clear'),
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _handleSearchChanged('');
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _exportReceiptsCsv() async {
    final l10n = context.l10n;
    setState(() => _isProcessingExport = true);
    try {
      await ExportService.exportReceiptsCsv(user: widget.user);
      if (!mounted) return;
      _showGlobalSnack(context, l10n.translate('export.csv.success'));
    } on StateError catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'export_not_allowed' => l10n.translate('export.denied'),
        'export_no_rows' => l10n.translate('export.empty'),
        _ => l10n.translate('export.error', params: {'message': error.message}),
      };
      _showGlobalSnack(context, message);
    } catch (error, stack) {
      if (!mounted) return;
      showFriendlyError(context, error, stack, userMessage: l10n.translate('errors.genericNetwork'), hint: 'receipts_export');
    } finally {
      if (mounted) {
        setState(() => _isProcessingExport = false);
      }
    }
  }

  Future<void> _exportReceiptPdf(Receipt receipt) async {
    final l10n = context.l10n;
    setState(() => _isProcessingExport = true);
    try {
      await ExportService.exportReceiptPdf(user: widget.user, receipt: receipt);
      if (!mounted) return;
      _showGlobalSnack(context, l10n.translate('export.pdf.success'));
    } on StateError catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'export_not_allowed' => l10n.translate('export.denied'),
        'export_no_rows' => l10n.translate('export.empty'),
        _ => l10n.translate('export.error', params: {'message': error.message}),
      };
      _showGlobalSnack(context, message);
    } catch (error, stack) {
      if (!mounted) return;
      showFriendlyError(context, error, stack, userMessage: l10n.translate('errors.genericNetwork'), hint: 'receipt_pdf');
    } finally {
      if (mounted) {
        setState(() => _isProcessingExport = false);
      }
    }
  }

  Future<void> _showImportDialog() async {
    final l10n = context.l10n;
    // Local state for the bottom sheet
    List<List<dynamic>>? rows;
    List<String> headers = [];
    final fieldMap = <String, String>{ // field -> column
      'date': '',
      'store': '',
      'category': '',
      'amount': '',
      'currency': '',
      'notes': '',
    };

    String? error;
    int previewCount = 5;

    List<String> _columns() => headers.isNotEmpty
        ? headers
        : (rows != null && rows!.isNotEmpty ? List<String>.generate(rows!.first.length, (i) => 'col_${i + 1}') : <String>[]);

    void preselectMappings() {
      if (headers.isEmpty) return;
      for (final h in headers) {
        final key = h.toLowerCase();
        if (key.contains('date') || key.contains('datum')) fieldMap['date'] = h;
        if (key.contains('store') || key.contains('butik')) fieldMap['store'] = h;
        if (key.contains('category') || key.contains('kategori')) fieldMap['category'] = h;
        if (key.contains('amount') || key.contains('belopp')) fieldMap['amount'] = h;
        if (key.contains('currency') || key.contains('valuta')) fieldMap['currency'] = h;
        if (key.contains('note') || key.contains('anteck')) fieldMap['notes'] = h;
      }
    }

    String? _cellAsString(List<dynamic> row, String col) {
      if (headers.isEmpty) {
        final idx = int.tryParse(col.replaceAll('col_', ''));
        if (idx == null) return null;
        final i0 = idx - 1;
        if (i0 < 0 || i0 >= row.length) return null;
        return row[i0]?.toString();
      } else {
        final index = headers.indexOf(col);
        if (index == -1 || index >= row.length) return null;
        return row[index]?.toString();
      }
    }

    DateTime? _parseDate(String? raw) {
      if (raw == null || raw.trim().isEmpty) return null;
      final txt = raw.trim();
      for (final fmt in ['yyyy-MM-dd', 'yyyy/MM/dd', 'dd/MM/yyyy', 'dd-MM-yyyy', 'MM/dd/yyyy']) {
        try {
          return DateFormat(fmt).parseStrict(txt);
        } catch (_) {}
      }
      return DateTime.tryParse(txt);
    }

    double? _parseAmountLocal(String? raw) {
      if (raw == null) return null;
      final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
      return double.tryParse(normalized);
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setSheet) {
          Future<void> pickCsv() async {
            error = null;
            try {
              final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
              if (result == null || result.files.isEmpty) return;
              final file = result.files.first;
              if (file.bytes == null) {
                throw StateError('no_bytes');
              }
              final content = utf8.decode(file.bytes!);
              final converter = const CsvToListConverter(eol: '\n');
              final parsed = converter.convert(content);
              if (parsed.isEmpty) {
                throw StateError('empty');
              }
              // Detect header row: if all cells are strings
              final first = parsed.first;
              final allStrings = first.every((c) => c is String);
              headers = allStrings ? first.cast<String>() : <String>[];
              rows = allStrings ? parsed.skip(1).toList() : parsed;
              preselectMappings();
              setSheet(() {});
            } catch (e) {
              error = e.toString();
              setSheet(() {});
            }
          }

          Future<void> doImport() async {
            if (rows == null || rows!.isEmpty) return;
            final colMap = Map<String, String>.from(fieldMap);
            int imported = 0;
            for (final row in rows!.take(1000)) {
              try {
                final date = _parseDate(_cellAsString(row, colMap['date']!)) ?? DateTime.now();
                final store = _cellAsString(row, colMap['store']!) ?? 'Butik';
                final category = _cellAsString(row, colMap['category']!) ?? 'Other';
                final amount = _parseAmountLocal(_cellAsString(row, colMap['amount']!)) ?? 0.0;
                final currency = _cellAsString(row, colMap['currency']!) ?? 'SEK';
                final notes = _cellAsString(row, colMap['notes']!);
                final receipt = Receipt(
                  id: const Uuid().v4(),
                  ownerId: widget.user.id,
                  store: store,
                  purchaseDate: date,
                  amount: amount,
                  currency: currency,
                  category: category,
                  remindersEnabled: false,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await ReceiptService.createReceipt(notes != null && notes.isNotEmpty ? receipt.copyWith(notes: notes) : receipt);
                imported++;
              } catch (_) {}
            }
            if (mounted) {
              Navigator.of(context).pop();
              await _loadReceipts();
              _showGlobalSnack(context, l10n.translate('import.csv.success', params: {'count': imported}));
            }
          }

          Widget mappingControls() {
            final cols = _columns();
            List<Widget> dropdowns = [];
            fieldMap.forEach((field, current) {
              dropdowns.add(Row(
                children: [
                  SizedBox(width: 120, child: Text(field.toUpperCase())),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: current.isNotEmpty ? current : null,
                      items: cols.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setSheet(() => fieldMap[field] = v ?? ''),
                      decoration: const InputDecoration(isDense: true, labelText: ''),
                    ),
                  ),
                ],
              ));
              dropdowns.add(const SizedBox(height: 8));
            });
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: dropdowns);
          }

          Widget preview() {
            if (rows == null || rows!.isEmpty) return const SizedBox.shrink();
            final sample = rows!.take(previewCount).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('import.csv.preview'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...sample.map((r) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long),
                      title: Text('${_cellAsString(r, fieldMap['store']!)} – ${_cellAsString(r, fieldMap['amount']!)} ${_cellAsString(r, fieldMap['currency']!)}'),
                      subtitle: Text('${_cellAsString(r, fieldMap['date']!)} • ${_cellAsString(r, fieldMap['category']!)}'),
                    )),
              ],
            );
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16, top: 16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(l10n.translate('import.csv.title'), style: Theme.of(context).textTheme.titleLarge),
                        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close))
                      ],
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(onPressed: pickCsv, icon: const Icon(Icons.upload_file), label: Text(l10n.translate('import.csv.pick'))),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.redAccent)),
                    ],
                    const SizedBox(height: 12),
                    if (rows != null) ...[
                      Text(l10n.translate('import.csv.mapFields'), style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      mappingControls(),
                      const SizedBox(height: 12),
                      preview(),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(onPressed: doImport, icon: const Icon(Icons.playlist_add), label: Text(l10n.translate('import.csv.import'))),
                    ],
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  void _showReceiptDetails(Receipt r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.store, style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        ShareStatusChip(resourceType: 'receipt', resourceId: r.id),
                      ],
                    ),
                  ),
                  PermissionGuard(
                    user: widget.user,
                    resourceType: 'receipt',
                    resourceId: r.id,
                    ownerId: r.ownerId,
                    requiredRole: ShareRoles.editor,
                    builder: (context, access) => IconButton(
                      tooltip: l10n.translate('common.actions.share'),
                      icon: const Icon(Icons.ios_share),
                      onPressed: () async {
                        await showDialog(
                          context: context,
                          builder: (_) => ShareDialog(
                            user: widget.user,
                            resourceType: 'receipt',
                            resourceId: r.id,
                            resourceName: l10n.translate('receipts.shareDialog.title', params: {'store': r.store}),
                            ownerId: r.ownerId,
                          ),
                        );
                      },
                    ),
                    fallback: const SizedBox.shrink(),
                  ),
                ],
              ),
              if (r.archived) ...[
                const SizedBox(height: 12),
                _buildArchivedBanner(context, l10n),
              ],
              const SizedBox(height: 16),
              PermissionGuard(
                user: widget.user,
                resourceType: 'receipt',
                resourceId: r.id,
                ownerId: r.ownerId,
                requiredRole: 'export',
                builder: (context, access) => OutlinedButton.icon(
                  onPressed: () => _exportReceiptPdf(r),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(l10n.translate('export.pdf.button')),
                ),
                fallback: Tooltip(
                  message: l10n.translate('export.denied.tooltip'),
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(l10n.translate('export.pdf.button')),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow(l10n.translate('receipts.detail.purchaseDate'), _formatDate(r.purchaseDate)),
              _buildDetailRow(l10n.translate('receipts.detail.amount'), '${r.amount.toStringAsFixed(0)} ${r.currency}'),
              _buildDetailRow(l10n.translate('receipts.detail.category'), r.category),
              if (r.returnDeadline != null)
                _buildDetailRow(l10n.translate('receipts.detail.deadline.return'), _formatDate(r.returnDeadline!)),
              if (r.exchangeDeadline != null)
                _buildDetailRow(l10n.translate('receipts.detail.deadline.exchange'), _formatDate(r.exchangeDeadline!)),
              if (r.warrantyExpires != null)
                _buildDetailRow(l10n.translate('receipts.detail.deadline.warranty'), _formatDate(r.warrantyExpires!)),
              if (r.notes != null) ...[
                const SizedBox(height: 16),
                Text(l10n.translate('common.labels.notes'), style: Theme.of(context).textTheme.labelLarge),
                Text(r.notes!),
              ],
              const SizedBox(height: 16),
              Text(l10n.translate('receipts.detail.reminders'), style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              _buildReceiptReminderSummary(context, l10n, r),
              const SizedBox(height: 24),
              PermissionGuard(
                user: widget.user,
                resourceType: 'receipt',
                resourceId: r.id,
                ownerId: r.ownerId,
                requiredRole: ShareRoles.viewer,
                builder: (context, access) {
                  final canEdit = access.canEdit;
                  return Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: Text(l10n.translate('common.actions.edit')),
                          onPressed: canEdit
                              ? () {
                                  Navigator.of(context).pop();
                                  _showReceiptDialog(receipt: r);
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete),
                          label: Text(l10n.translate('common.actions.delete')),
                          onPressed: canEdit
                              ? () async {
                                  await ReceiptService.deleteReceipt(r.id);
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                    _loadReceipts();
                                    _showGlobalSnack(context, l10n.translate('common.feedback.deleted'));
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
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

  Widget _buildArchivedBanner(BuildContext context, AppLocalizations l10n) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.translate('common.warning.archived'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _buildReceiptReminderSummary(BuildContext context, AppLocalizations l10n, Receipt receipt) {
    if (!receipt.remindersEnabled) {
      return Text(
        l10n.translate('receipts.reminders.off'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
      );
    }

    final deadlines = <String, DateTime>{
      if (receipt.returnDeadline != null) 'returnDeadline': receipt.returnDeadline!,
      if (receipt.exchangeDeadline != null) 'exchangeDeadline': receipt.exchangeDeadline!,
      if (receipt.warrantyExpires != null) 'warrantyExpires': receipt.warrantyExpires!,
      if (receipt.refundDeadline != null) 'refundDeadline': receipt.refundDeadline!,
    };

    if (deadlines.isEmpty) {
      return Text(
        l10n.translate('receipts.reminders.missing'),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
      );
    }

    final now = DateTime.now();
    final children = <Widget>[];
    deadlines.forEach((key, deadline) {
      children.add(Text(_deadlineLabel(l10n, key), style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)));
      for (final offset in const [7, 1]) {
        final scheduled = deadline.subtract(Duration(days: offset));
        final isFuture = scheduled.isAfter(now);
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(isFuture ? Icons.schedule : Icons.check_circle, size: 16, color: isFuture ? AppColors.primary : AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${l10n.translate('receipts.reminders.offset', params: {'days': offset == 7 ? 7 : 1})} • ${_formatDate(scheduled)}'
                  '${isFuture ? '' : ' ${l10n.translate('receipts.reminders.sentSuffix')}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ));
      }
      children.add(const SizedBox(height: 8));
    });

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  String _deadlineLabel(AppLocalizations l10n, String key) {
    switch (key) {
      case 'returnDeadline':
        return l10n.translate('receipts.detail.deadline.return');
      case 'exchangeDeadline':
        return l10n.translate('receipts.detail.deadline.exchange');
      case 'warrantyExpires':
        return l10n.translate('receipts.detail.deadline.warranty');
      case 'refundDeadline':
        return l10n.translate('receipts.detail.deadline.refund');
      default:
        return l10n.translate('common.labels.deadline');
    }
  }

   Future<void> _showReceiptDialog({Receipt? receipt}) async {
     final isEditing = receipt != null;
     final storeController = TextEditingController(text: receipt?.store ?? '');
     final amountController = TextEditingController(text: receipt != null ? receipt.amount.toStringAsFixed(2) : '');
     final notesController = TextEditingController(text: receipt?.notes ?? '');
     DateTime purchaseDate = receipt?.purchaseDate ?? DateTime.now();
     DateTime? returnDeadline = receipt?.returnDeadline;
     DateTime? exchangeDeadline = receipt?.exchangeDeadline;
     DateTime? warrantyExpires = receipt?.warrantyExpires;
     String category = receipt?.category ?? 'Electronics';

     String entryMode = 'manual';
     ReceiptOcrResult? ocrResult;
     bool isAnalyzing = false;
     String? ocrFeedback;
     final existingImageUrl = receipt?.imageUrl;
     DocumentUploadState documentState = const DocumentUploadState();
     bool storeConfirmed = receipt != null;
     bool amountConfirmed = receipt != null;
     bool dateConfirmed = receipt != null;
     bool autoLinkToBudget = receipt == null ? true : receipt.budgetId != null;
     String? selectedBudgetId = autoLinkToBudget ? (receipt?.budgetId ?? _primaryBudget?.id) : null;
     String? selectedBudgetCategoryId = autoLinkToBudget ? receipt?.budgetCategoryId : null;
     bool budgetSelectionTouched = receipt?.budgetId != null && receipt?.budgetCategoryId != null;
     String? budgetSuggestionLabel;
      bool remindersEnabled = receipt?.remindersEnabled ?? true;
      bool isSaving = false;
      String? storeError;
      String? amountError;
      bool isFormValid = storeController.text.trim().isNotEmpty && _parseAmount(amountController.text) != null;

     await showDialog(
       context: context,
       builder: (context) {
         return StatefulBuilder(
         builder: (context, setLocalState) {
           final l10n = context.l10n;
           void updateValidity() {
             final trimmedStore = storeController.text.trim();
             final parsedAmount = _parseAmount(amountController.text);
             String? newStoreError;
             String? newAmountError;

             if (trimmedStore.isEmpty) {
               newStoreError = l10n.translate('receipts.form.storeRequired');
             }

             if (parsedAmount == null || parsedAmount <= 0) {
               newAmountError = l10n.translate('receipts.form.invalidAmount');
             }

             setLocalState(() {
               storeError = newStoreError;
               amountError = newAmountError;
               isFormValid = newStoreError == null && newAmountError == null;
             });
           }
              void refreshBudgetSuggestion() {
                if (_budgets.isEmpty || budgetSelectionTouched || !autoLinkToBudget) {
                  return;
                }
                final suggestion = _suggestBudgetLink(
                  storeName: storeController.text,
                  manualCategory: category,
                );
                setLocalState(() {
                  if (suggestion != null) {
                    selectedBudgetId = suggestion.budget.id;
                    selectedBudgetCategoryId = suggestion.category.id;
                    budgetSuggestionLabel = l10n.translate(suggestion.reason.key, params: suggestion.reason.params);
                  } else {
                    budgetSuggestionLabel = null;
                  }
                });
              }

              List<BudgetCategory> categoriesForBudget(String? budgetId) {
                if (budgetId == null) return const <BudgetCategory>[];
                return _categoriesByBudget[budgetId] ?? const <BudgetCategory>[];
              }

             Future<void> pickDate({required DateTime initial, required ValueChanged<DateTime> onSelected}) async {
                 final picked = await showDatePicker(
                 context: context,
                 initialDate: initial,
                 firstDate: DateTime(2000),
                 lastDate: DateTime(2100),
                   locale: Localizations.localeOf(context),
               );
               if (picked != null) {
                 onSelected(picked);
                 setLocalState(() {});
               }
             }

              String formatShort(DateTime? date) =>
                  date == null ? l10n.translate('common.inputs.selectDate') : formatDateShortLocalized(context, date);

              InputDecoration withOcrDecoration(String label, OcrSuggestion<dynamic>? suggestion, bool isConfirmed, {String? errorText}) {
               final showWarning =
                   suggestion != null && suggestion.value != null && !suggestion.isConfident && !isConfirmed;
               return InputDecoration(
                 labelText: label,
                  helperText: showWarning ? l10n.translate('ocr.warning.unconfident') : null,
                 helperStyle: showWarning
                     ? Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning)
                     : null,
                 suffixIcon: showWarning ? const Icon(Icons.info_outline, color: AppColors.warning) : null,
                  errorText: errorText,
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

             Future<_ReceiptScanSource?> selectScanSource() async {
               return showModalBottomSheet<_ReceiptScanSource>(
                 context: context,
                 builder: (sheetContext) => SafeArea(
                   child: Column(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       ListTile(
                         leading: const Icon(Icons.camera_alt_outlined),
                        title: Text(l10n.translate('receipts.form.scan.camera')),
                         onTap: () => Navigator.of(sheetContext).pop(_ReceiptScanSource.camera),
                       ),
                       ListTile(
                         leading: const Icon(Icons.photo_library_outlined),
                        title: Text(l10n.translate('receipts.form.scan.gallery')),
                         onTap: () => Navigator.of(sheetContext).pop(_ReceiptScanSource.gallery),
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
                  final result = await OcrService.analyzeReceipt(bytes: bytes, fileName: fileName);

                  if (!result.hasAnyData) {
                    setLocalState(() {
                      isAnalyzing = false;
                      ocrResult = null;
                      storeConfirmed = true;
                      amountConfirmed = true;
                      dateConfirmed = true;
                      ocrFeedback = l10n.translate('ocr.feedback.none');
                    });
                    return;
                  }

                  if (result.store.value != null) {
                    storeController.text = result.store.value!;
                  }
                  if (result.amount.value != null) {
                    amountController.text = result.amount.value!.toStringAsFixed(2);
                  }
                  if (result.purchaseDate.value != null) {
                    purchaseDate = result.purchaseDate.value!;
                  }
                   if (result.vat.value != null) {
                     final vatLabel = l10n.translate('receipts.form.vatLabel');
                     final vatPrefix = result.vat.isConfident ? '' : '⚠️ ';
                     final vatLine = '$vatPrefix$vatLabel: ${result.vat.value!.toStringAsFixed(2)} ${result.currency}';
                    if (!notesController.text.contains(vatLine)) {
                      notesController.text = notesController.text.isEmpty ? vatLine : '${notesController.text}\n$vatLine';
                    }
                  }

                  setLocalState(() {
                    isAnalyzing = false;
                    ocrResult = result;
                    storeConfirmed = result.store.value == null ? true : result.store.isConfident;
                    amountConfirmed = result.amount.value == null ? true : result.amount.isConfident;
                    dateConfirmed = result.purchaseDate.value == null ? true : result.purchaseDate.isConfident;
                     ocrFeedback = l10n.translate('ocr.feedback.populated');
                  });
                  refreshBudgetSuggestion();
                  updateValidity();
                } catch (_) {
                  setLocalState(() {
                    isAnalyzing = false;
                    ocrResult = null;
                    storeConfirmed = true;
                    amountConfirmed = true;
                    dateConfirmed = true;
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
                    source: source == _ReceiptScanSource.camera ? ImageSource.camera : ImageSource.gallery,
                    imageQuality: 85,
                  );
                 } catch (_) {
                   if (mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text(l10n.translate('receipts.form.errors.cameraUnavailable'))),
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
                    title: l10n.translate('receipts.form.scan.sheetTitle'),
                    description: l10n.translate('receipts.form.scan.sheetDescription'),
                  ),
                );

                if (raw == null) return;

                final parsed = BarcodeParser.parseReceipt(raw);
                setLocalState(() {
                  entryMode = 'scan';
                  ocrResult = null;
                  ocrFeedback = parsed.hasAny
                      ? l10n.translate('receipts.form.scanSuccess')
                      : l10n.translate('receipts.form.scanUnknown');

                  if (parsed.store != null) {
                    storeController.text = parsed.store!;
                    storeConfirmed = true;
                  }
                  if (parsed.amount != null) {
                    amountController.text = parsed.amount!.toStringAsFixed(2);
                    amountConfirmed = true;
                  }
                  if (parsed.purchaseDate != null) {
                    purchaseDate = parsed.purchaseDate!;
                    dateConfirmed = true;
                  }
                });
                refreshBudgetSuggestion();
                updateValidity();

                if (!parsed.hasAny && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.translate('receipts.form.scanUnsupported'))),
                  );
                }
              }

             return AlertDialog(
               title: Text(isEditing ? l10n.translate('receipts.form.editTitle') : l10n.translate('receipts.form.addTitle')),
               content: AnimatedPadding(
                 duration: const Duration(milliseconds: 180),
                 curve: Curves.easeOut,
                 padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                 child: SingleChildScrollView(
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
                              storeConfirmed = true;
                              amountConfirmed = true;
                              dateConfirmed = true;
                              ocrResult = null;
                              ocrFeedback = null;
                            }
                          });
                        },
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.translate('common.entry.scan')),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.translate('common.entry.manual')),
                          ),
                        ],
                      ),
                     const SizedBox(height: 16),
                     if (entryMode == 'scan') ...[
                        ElevatedButton.icon(
                          icon: const Icon(Icons.document_scanner_outlined),
                          onPressed: isAnalyzing ? null : startScan,
                          label: Text(l10n.translate('receipts.form.actions.startOcr')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: isAnalyzing ? null : startBarcodeScan,
                          label: Text(l10n.translate('receipts.form.actions.scanCode')),
                        ),
                       const SizedBox(height: 12),
                        if (isAnalyzing)
                          Row(
                            children: [
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Expanded(child: Text(l10n.translate('receipts.form.status.analyzing'))),
                            ],
                          ),
                       if (!isAnalyzing && ocrFeedback != null)
                         Text(ocrFeedback!, style: Theme.of(context).textTheme.bodySmall),
                       const SizedBox(height: 12),
                     ],
                      TextField(
                        controller: storeController,
                        decoration: withOcrDecoration(
                          l10n.translate('receipts.form.store'),
                          ocrResult?.store,
                          storeConfirmed,
                          errorText: storeError,
                        ),
                        onChanged: (_) {
                          if (!storeConfirmed) {
                            setLocalState(() => storeConfirmed = true);
                          }
                          refreshBudgetSuggestion();
                          updateValidity();
                        },
                      ),
                      if (((ocrResult?.store)?.hasValue ?? false) && !(((ocrResult?.store)?.isConfident ?? true)) && !storeConfirmed)
                        buildUncertainHint(l10n.translate('receipts.form.store').toLowerCase(), () => setLocalState(() => storeConfirmed = true)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: amountController,
                        decoration: withOcrDecoration(
                          l10n.translate('receipts.form.amount'),
                          ocrResult?.amount,
                          amountConfirmed,
                          errorText: amountError,
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) {
                          if (!amountConfirmed) {
                            setLocalState(() => amountConfirmed = true);
                          }
                          refreshBudgetSuggestion();
                          updateValidity();
                        },
                      ),
                      if (((ocrResult?.amount)?.hasValue ?? false) && !(((ocrResult?.amount)?.isConfident ?? true)) && !amountConfirmed)
                        buildUncertainHint(l10n.translate('receipts.form.amount').toLowerCase(), () => setLocalState(() => amountConfirmed = true)),
                     const SizedBox(height: 16),
                       DropdownButtonFormField<String>(
                         value: category,
                         decoration: InputDecoration(labelText: l10n.translate('receipts.form.category')),
                         items: ['Electronics', 'Clothes', 'Home', 'Food', 'Other']
                             .map((c) => DropdownMenuItem(value: c, child: Text(l10n.translate('receipts.form.category.$c'))))
                             .toList(),
                         onChanged: (v) {
                           category = v!;
                           refreshBudgetSuggestion();
                         },
                       ),
                     const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l10n.translate('receipts.form.purchaseDate'),
                          style: (((ocrResult?.purchaseDate)?.hasValue ?? false) && !(((ocrResult?.purchaseDate)?.isConfident ?? true)) && !dateConfirmed)
                              ? Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.warning)
                              : Theme.of(context).textTheme.titleSmall,
                        ),
                        subtitle: Text(formatShort(purchaseDate)),
                        trailing: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          tooltip: l10n.translate('common.actions.pickDate'),
                          onPressed: () => pickDate(
                            initial: purchaseDate,
                            onSelected: (d) {
                              purchaseDate = d;
                              dateConfirmed = true;
                            },
                          ),
                        ),
                      ),
                      if (((ocrResult?.purchaseDate)?.hasValue ?? false) && !(((ocrResult?.purchaseDate)?.isConfident ?? true)) && !dateConfirmed)
                        buildUncertainHint(l10n.translate('receipts.form.purchaseDate').toLowerCase(), () => setLocalState(() => dateConfirmed = true)),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('receipts.form.returnDeadline')),
                        subtitle: Text(formatShort(returnDeadline)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (returnDeadline != null)
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: l10n.translate('common.actions.clearDate'),
                                onPressed: () {
                                  returnDeadline = null;
                                  setLocalState(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today),
                              tooltip: l10n.translate('common.actions.pickDate'),
                              onPressed: () => pickDate(initial: returnDeadline ?? DateTime.now(), onSelected: (d) => returnDeadline = d),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('receipts.form.exchangeDeadline')),
                        subtitle: Text(formatShort(exchangeDeadline)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (exchangeDeadline != null)
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: l10n.translate('common.actions.clearDate'),
                                onPressed: () {
                                  exchangeDeadline = null;
                                  setLocalState(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today),
                              tooltip: l10n.translate('common.actions.pickDate'),
                              onPressed: () => pickDate(initial: exchangeDeadline ?? DateTime.now(), onSelected: (d) => exchangeDeadline = d),
                            ),
                          ],
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('receipts.form.warrantyExpires')),
                        subtitle: Text(formatShort(warrantyExpires)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (warrantyExpires != null)
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: l10n.translate('common.actions.clearDate'),
                                onPressed: () {
                                  warrantyExpires = null;
                                  setLocalState(() {});
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.calendar_today),
                              tooltip: l10n.translate('common.actions.pickDate'),
                              onPressed: () => pickDate(initial: warrantyExpires ?? DateTime.now(), onSelected: (d) => warrantyExpires = d),
                            ),
                          ],
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.translate('receipts.form.reminders')),
                        subtitle: Text(l10n.translate('receipts.form.reminders.subtitle')),
                        value: remindersEnabled,
                        onChanged: (value) => setLocalState(() => remindersEnabled = value),
                      ),
                      const SizedBox(height: 16),
                      DocumentUploader(
                        uploadLabel: l10n.translate('receipts.form.uploadLabel'),
                        initialUrl: existingImageUrl,
                        onChanged: (state) => documentState = state,
                        onOcr: applyOcr,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: notesController,
                        decoration: InputDecoration(labelText: l10n.translate('receipts.form.notes')),
                        maxLines: 3,
                      ),
                      if (_budgets.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(l10n.translate('receipts.form.budgetLink.title'), style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(l10n.translate('receipts.form.budgetLink.auto')),
                          subtitle: Text(l10n.translate('receipts.form.budgetLink.hint')),
                          value: autoLinkToBudget,
                          onChanged: (value) {
                            if (value == null) return;
                            if (value) {
                              setLocalState(() {
                                autoLinkToBudget = true;
                                budgetSelectionTouched = false;
                                budgetSuggestionLabel = null;
                              });
                              refreshBudgetSuggestion();
                            } else {
                              setLocalState(() {
                                autoLinkToBudget = false;
                                selectedBudgetId = null;
                                selectedBudgetCategoryId = null;
                                budgetSelectionTouched = true;
                                budgetSuggestionLabel = l10n.translate('receipts.form.budgetLink.none');
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: autoLinkToBudget ? selectedBudgetId : null,
                          decoration: InputDecoration(labelText: l10n.translate('receipts.form.budgetLink.budgetLabel')),
                          items: _budgets.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                          onChanged: autoLinkToBudget
                              ? (value) {
                                  setLocalState(() {
                                    selectedBudgetId = value;
                                    budgetSelectionTouched = true;
                                    if (value == null) {
                                      selectedBudgetCategoryId = null;
                                      budgetSuggestionLabel = null;
                                    } else {
                                      final cats = categoriesForBudget(value);
                                      selectedBudgetCategoryId = cats.isNotEmpty ? cats.first.id : null;
                                      final budgetName = _budgets.firstWhere((b) => b.id == value).name;
                                      budgetSuggestionLabel = l10n.translate('receipts.form.budgetLink.manualBudget', params: {'name': budgetName});
                                    }
                                  });
                                }
                              : null,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: autoLinkToBudget &&
                                  categoriesForBudget(selectedBudgetId).any((c) => c.id == selectedBudgetCategoryId)
                              ? selectedBudgetCategoryId
                              : null,
                          decoration: InputDecoration(labelText: l10n.translate('receipts.form.budgetLink.categoryLabel')),
                          items: categoriesForBudget(selectedBudgetId)
                              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: autoLinkToBudget
                              ? (value) {
                                  setLocalState(() {
                                    selectedBudgetCategoryId = value;
                                    budgetSelectionTouched = true;
                                    if (value == null) {
                                      budgetSuggestionLabel = null;
                                    } else {
                                      final catList = categoriesForBudget(selectedBudgetId);
                                      final cat = catList.where((c) => c.id == value).toList();
                                      if (cat.isNotEmpty) {
                                        budgetSuggestionLabel = l10n.translate('receipts.form.budgetLink.manualCategory', params: {'name': cat.first.name});
                                      }
                                    }
                                  });
                                }
                              : null,
                        ),
                        if (budgetSuggestionLabel != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              budgetSuggestionLabel!,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.translate('common.actions.cancel'))),
                  ElevatedButton(
                    onPressed: isSaving || !isFormValid
                        ? null
                        : () async {
                            updateValidity();
                            if (!isFormValid) return;
                            setLocalState(() => isSaving = true);
                            try {
                              final amount = _parseAmount(amountController.text)!;
                              final now = DateTime.now();
                              final imageUrl = await _resolveReceiptDocument(
                                state: documentState,
                                ownerId: widget.user.id,
                                existingUrl: existingImageUrl,
                              );
                              String? budgetIdToSave;
                              String? budgetCategoryIdToSave;
                              if (autoLinkToBudget) {
                                budgetIdToSave = selectedBudgetId;
                                budgetCategoryIdToSave = selectedBudgetCategoryId;
                                if (_budgets.isNotEmpty &&
                                    (!budgetSelectionTouched || budgetIdToSave == null || budgetCategoryIdToSave == null)) {
                                  final suggestion = _suggestBudgetLink(
                                    storeName: storeController.text,
                                    manualCategory: category,
                                  );
                                  if (suggestion != null) {
                                    budgetIdToSave ??= suggestion.budget.id;
                                    budgetCategoryIdToSave ??= suggestion.category.id;
                                    budgetSuggestionLabel = l10n.translate(suggestion.reason.key, params: suggestion.reason.params);
                                  }
                                }
                              }

                              if (isEditing) {
                                final updated = receipt!.copyWith(
                                  store: storeController.text.trim(),
                                  amount: amount,
                                  category: category,
                                  purchaseDate: purchaseDate,
                                  returnDeadline: returnDeadline,
                                  exchangeDeadline: exchangeDeadline,
                                  warrantyExpires: warrantyExpires,
                                  remindersEnabled: remindersEnabled,
                                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                  imageUrl: imageUrl,
                                  budgetId: budgetIdToSave,
                                  budgetCategoryId: budgetCategoryIdToSave,
                                );
                                await ReceiptService.updateReceipt(updated);
                              } else {
                                final newReceipt = Receipt(
                                  id: _uuid.v4(),
                                  ownerId: widget.user.id,
                                  store: storeController.text.trim(),
                                  purchaseDate: purchaseDate,
                                  amount: amount,
                                  category: category,
                                  returnDeadline: returnDeadline,
                                  exchangeDeadline: exchangeDeadline,
                                  warrantyExpires: warrantyExpires,
                                  remindersEnabled: remindersEnabled,
                                  notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                                  createdAt: now,
                                  updatedAt: now,
                                  imageUrl: imageUrl,
                                  budgetId: budgetIdToSave,
                                  budgetCategoryId: budgetCategoryIdToSave,
                                );
                                await ReceiptService.createReceipt(newReceipt);
                              }

                              if (context.mounted) {
                                Navigator.of(context).pop();
                                await _loadReceipts();
                                _showGlobalSnack(
                                  context,
                                  l10n.translate(isEditing ? 'receipts.form.feedback.updated' : 'receipts.form.feedback.saved'),
                                );
                              }
                            } catch (error) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.translate('receipts.form.errors.generic'))),
                                );
                              }
                            } finally {
                              if (context.mounted) {
                                setLocalState(() => isSaving = false);
                              }
                            }
                          },
                    child: isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(isEditing ? l10n.translate('common.actions.update') : l10n.translate('receipts.form.submit')),
                  ),
                ],
             );
           },
         );
       },
     );
   }

   double? _parseAmount(String raw) {
     final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
     return double.tryParse(normalized);
   }

  Future<String?> _resolveReceiptDocument({
    required DocumentUploadState state,
    required String ownerId,
    String? existingUrl,
  }) async {
    if (state.pendingFile != null) {
      final sbUser = SupabaseAuthAdapter.currentAppUserSync();
      if (sbUser != null) {
        // Upload to Supabase Storage -> 'receipts' bucket
        final signedUrl = await StorageService().upload(
          file: state.pendingFile!.bytes,
          bucket: 'receipts',
          folder: ownerId,
          fileName: state.pendingFile!.fileName,
        );
        // If previous was a locally stored document, clean it up.
        if (existingUrl != null && existingUrl.startsWith('secure://')) {
          await DocumentStorage.deleteDocument(existingUrl);
        }
        return signedUrl;
      } else {
        // Local secure-storage fallback
        final stored = await DocumentStorage.saveDocument(
          ownerId: ownerId,
          module: 'receipts',
          originalName: state.pendingFile!.fileName,
          mimeType: state.pendingFile!.mimeType,
          bytes: state.pendingFile!.bytes,
        );
        if (existingUrl != null && existingUrl != stored.url) {
          await DocumentStorage.deleteDocument(existingUrl);
        }
        return stored.url;
      }
    }

    if (state.removeExisting && existingUrl != null) {
      // Best-effort cleanup for locally stored documents
      if (existingUrl.startsWith('secure://')) {
        await DocumentStorage.deleteDocument(existingUrl);
      }
      return null;
    }

    return existingUrl;
  }

  _SuggestedBudgetLink? _suggestBudgetLink({
    required String storeName,
    required String manualCategory,
  }) {
    if (_budgets.isEmpty) {
      return null;
    }

    final prioritizedBudgets = _prioritizedBudgets();
    if (prioritizedBudgets.isEmpty) {
      return null;
    }

    final normalizedStore = storeName.trim().toLowerCase();
    if (normalizedStore.isNotEmpty) {
      for (final entry in _budgetCategoryKeywords.entries) {
        final keywords = entry.value;
        for (final keyword in keywords) {
          if (normalizedStore.contains(keyword)) {
            final match = _matchCategoryAcrossBudgets(
              entry.key,
              prioritizedBudgets,
              (category, budget) => _SuggestionReason(
                key: 'receipts.form.budgetLink.reason.storeMatch',
                params: {
                  'category': category.name,
                  'budget': budget.name,
                },
              ),
            );
            if (match != null) return match;
          }
        }
      }
    }

    final mappedManual = _receiptCategoryToBudgetName[manualCategory] ?? manualCategory;
    final manualMatch = _matchCategoryAcrossBudgets(
      mappedManual,
      prioritizedBudgets,
      (category, budget) => _SuggestionReason(
        key: 'receipts.form.budgetLink.reason.categoryMatch',
        params: {
          'category': category.name,
          'budget': budget.name,
        },
      ),
    );
    if (manualMatch != null) {
      return manualMatch;
    }

    final fallbackBudget = _selectedBudgetForSuggestion();
    if (fallbackBudget == null) {
      return null;
    }

    final fallbackCategories = _categoriesByBudget[fallbackBudget.id] ?? const <BudgetCategory>[];
    if (fallbackCategories.isEmpty) {
      return null;
    }

    return _SuggestedBudgetLink(
      budget: fallbackBudget,
      category: fallbackCategories.first,
      reason: _SuggestionReason(
        key: 'receipts.form.budgetLink.reason.fallback',
        params: {
          'category': fallbackCategories.first.name,
          'budget': fallbackBudget.name,
        },
      ),
    );
  }

  Budget? _selectedBudgetForSuggestion() {
    if (_primaryBudget != null) {
      final categories = _categoriesByBudget[_primaryBudget!.id] ?? const <BudgetCategory>[];
      if (categories.isNotEmpty) {
        return _primaryBudget;
      }
    }

    for (final budget in _budgets) {
      final categories = _categoriesByBudget[budget.id] ?? const <BudgetCategory>[];
      if (categories.isNotEmpty) {
        return budget;
      }
    }
    return null;
  }

  List<Budget> _prioritizedBudgets() {
    if (_budgets.isEmpty) {
      return const <Budget>[];
    }

    if (_primaryBudget == null) {
      return List<Budget>.from(_budgets);
    }

    final primary = _budgets.firstWhere(
      (b) => b.id == _primaryBudget!.id,
      orElse: () => _primaryBudget!,
    );

    final others = _budgets.where((b) => b.id != primary.id);
    return [primary, ...others];
  }

  _SuggestedBudgetLink? _matchCategoryAcrossBudgets(
    String rawCategory,
    List<Budget> prioritizedBudgets,
    _SuggestionReason Function(BudgetCategory category, Budget budget) reasonBuilder,
  ) {
    if (rawCategory.trim().isEmpty) {
      return null;
    }

    for (final budget in prioritizedBudgets) {
      final categories = _categoriesByBudget[budget.id] ?? const <BudgetCategory>[];
      final match = _matchCategoryByName(rawCategory, categories);
      if (match != null) {
        return _SuggestedBudgetLink(
          budget: budget,
          category: match,
          reason: reasonBuilder(match, budget),
        );
      }
    }
    return null;
  }

  BudgetCategory? _matchCategoryByName(String rawName, List<BudgetCategory> categories) {
    final normalized = _normalize(rawName);
    for (final category in categories) {
      if (_normalize(category.name) == normalized) {
        return category;
      }
    }
    return null;
  }

  String _normalize(String input) => input.trim().toLowerCase();

  String? _categoryNameForId(String? categoryId, {String? budgetId}) {
    if (categoryId == null) {
      return null;
    }

    final candidateBudgetIds = <String>{
      if (budgetId != null) budgetId,
      if (_primaryBudget != null) _primaryBudget!.id,
    };
    candidateBudgetIds.addAll(_categoriesByBudget.keys);

    for (final id in candidateBudgetIds) {
      final categories = _categoriesByBudget[id];
      if (categories == null) {
        continue;
      }
      for (final category in categories) {
        if (category.id == categoryId) {
          return category.name;
        }
      }
    }

    return null;
  }

  String _formatDateLocalized(BuildContext context, DateTime date) => formatDateShortLocalized(context, date);

  String _formatDate(DateTime date) => DateFormat('d MMM yyyy', 'sv-SE').format(date);

  void _showGlobalSnack(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SuggestedBudgetLink {
  final Budget budget;
  final BudgetCategory category;
  final _SuggestionReason reason;

  _SuggestedBudgetLink({required this.budget, required this.category, required this.reason});
}

class _SuggestionReason {
  final String key;
  final Map<String, String> params;

  const _SuggestionReason({required this.key, this.params = const {}});
}
