import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'utils/formatting.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'dart:convert';

import 'models.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets/dev_guest_banner.dart';
import 'components/sharing/share_dialog.dart';
import 'components/sharing/share_status_chip.dart';
import 'i18n/app_localizations.dart';
import 'utils/error_handling.dart';
import 'widgets/budget_chart.dart';
import 'widgets/offline_banner.dart';
import 'utils/offline_cache.dart';

const _uuid = Uuid();

class BudgetScreen extends StatefulWidget {
  final User user;
  final Future<void> Function()? onLogout;

  const BudgetScreen({super.key, required this.user, this.onLogout});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  List<Budget> _budgets = [];
  Budget? _selectedBudget;
  List<BudgetCategory> _categories = [];
  List<BudgetIncome> _incomes = [];
  Map<String, double> _spent = {};
  bool _isLoading = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  ShareAccess? _currentBudgetAccess;
  bool _isBudgetAccessLoading = false;
  bool _isProcessingExport = false;
  bool _isProcessingImport = false;

  bool get _canEditSelectedBudget {
    final budget = _selectedBudget;
    if (budget == null) return false;
    if (_currentBudgetAccess != null) {
      return _currentBudgetAccess!.canEdit;
    }
    return budget.ownerId == widget.user.id;
  }

  bool get _canShareSelectedBudget {
    final budget = _selectedBudget;
    if (budget == null) return false;
    if (_currentBudgetAccess != null) {
      return _currentBudgetAccess!.canShare;
    }
    return budget.ownerId == widget.user.id;
  }

  bool get _canExportSelectedBudget {
    final budget = _selectedBudget;
    if (budget == null) return false;
    if (_currentBudgetAccess != null) {
      return _currentBudgetAccess!.canExport;
    }
    return budget.ownerId == widget.user.id;
  }

  @override
  void initState() {
    super.initState();
    _loadBudgets();
  }

  Future<void> _loadBudgets() async {
    setState(() => _isLoading = true);
    try {
      _budgets = await BudgetService.getAllBudgets(widget.user.id, email: widget.user.email);
      if (_budgets.isNotEmpty) {
        _selectedBudget = _budgets.first;
        await _loadBudgetDetails();
        await _loadBudgetAccess();
      }
      setState(() => _isLoading = false);
      OfflineCache.writeJsonList('cache_budgets_${widget.user.id}', _budgets.map((e) => e.toJson()));
    } catch (e) {
      final cached = OfflineCache.readJsonList('cache_budgets_${widget.user.id}', (m) => Budget.fromJson(m));
      if (cached.isNotEmpty) {
        _budgets = cached;
        _selectedBudget = _budgets.first;
        await _loadBudgetDetails(fromCacheOnly: true);
        setState(() => _isLoading = false);
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadBudgetDetails({bool fromCacheOnly = false}) async {
    if (_selectedBudget == null) return;
    try {
      if (fromCacheOnly) throw Exception('force_cache');
      final categories = await BudgetService.getCategories(_selectedBudget!.id);
      final incomes = await BudgetService.getIncomes(_selectedBudget!.id);
      final spent = await BudgetService.getCategorySpent(_selectedBudget!.id, month: _selectedMonth);
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _incomes = incomes;
        _spent = spent;
      });
      OfflineCache.writeJsonList('cache_budget_categories_${_selectedBudget!.id}', _categories.map((e) => e.toJson()));
      OfflineCache.writeJsonList('cache_budget_incomes_${_selectedBudget!.id}', _incomes.map((e) => e.toJson()));
      // Store spent as simple map
      OfflineCache.writeJson('cache_budget_spent_${_selectedBudget!.id}_${_selectedMonth.toIso8601String().substring(0,7)}',
          {for (final e in _spent.entries) e.key: e.value});
    } catch (_) {
      // Try cache
      final cats = OfflineCache.readJsonList('cache_budget_categories_${_selectedBudget!.id}', (m) => BudgetCategory.fromJson(m));
      final incomes = OfflineCache.readJsonList('cache_budget_incomes_${_selectedBudget!.id}', (m) => BudgetIncome.fromJson(m));
      final spentMap = OfflineCache.readJson<Map<String, dynamic>>(
        'cache_budget_spent_${_selectedBudget!.id}_${_selectedMonth.toIso8601String().substring(0,7)}',
        (m) => m,
      );
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _incomes = incomes;
        _spent = {for (final e in (spentMap ?? const {}).entries) e.key: (e.value as num).toDouble()};
      });
    }
  }

  Future<void> _loadBudgetAccess() async {
    final budget = _selectedBudget;
    if (budget == null) return;
    setState(() => _isBudgetAccessLoading = true);
    try {
      final access = await SharingService.getAccessForUser(
        resourceType: 'budget',
        resourceId: budget.id,
        user: widget.user,
        ownerId: budget.ownerId,
      );
      if (!mounted) return;
      setState(() {
        _currentBudgetAccess = access;
        _isBudgetAccessLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isBudgetAccessLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.user.id == AuthService.guestUserId;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.translate('budget.title')),
        actions: [
          if (_selectedBudget != null && _canShareSelectedBudget && !_isBudgetAccessLoading)
            IconButton(
              tooltip: context.l10n.translate('common.actions.share'),
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                final budget = _selectedBudget;
                if (budget == null) return;
                await showDialog(
                  context: context,
                  builder: (_) => ShareDialog(
                    user: widget.user,
                    resourceType: 'budget',
                    resourceId: budget.id,
                    resourceName: '${context.l10n.translate('budget.title')} – ${budget.name}',
                    ownerId: budget.ownerId,
                  ),
                );
                await _loadBudgetAccess();
              },
            ),
          if (_budgets.isNotEmpty)
            DropdownButton<Budget>(
              value: _selectedBudget,
              underline: Container(),
              items: _budgets.map((b) => DropdownMenuItem(value: b, child: Text(b.name))).toList(),
              onChanged: (b) async {
                _selectedBudget = b;
                await _loadBudgetDetails();
                await _loadBudgetAccess();
              },
            ),
        ],
      ),
      floatingActionButton: Semantics(
        label: context.l10n.translate('common.actions.add'),
        button: true,
        child: FloatingActionButton(
          onPressed: () => _showAddBudgetDialog(),
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
                : _budgets.isEmpty
                    ? _buildEmptyState()
                    : CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.all(16),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                _buildBudgetHeader(),
                                const SizedBox(height: 16),
                                _buildMonthSelector(),
                                const SizedBox(height: 16),
                                _buildActionRow(context.l10n),
                                const SizedBox(height: 16),
                                _buildIncomeOverviewCard(),
                                const SizedBox(height: 16),
                                _buildIncomeSection(),
                                const SizedBox(height: 24),
                                BudgetChart(categories: _categories, spentAmounts: _spent),
                                const SizedBox(height: 24),
                                Text(context.l10n.translate('budget.categories'), style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 12),
                              ]),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            sliver: SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) => _buildCategoryCard(_categories[index]),
                                childCount: _categories.length,
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: Text(context.l10n.translate('budget.actions.addCategory')),
                                  onPressed: _canEditSelectedBudget ? () => _showAddCategoryDialog() : null,
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.receipt_long),
                                  label: Text(context.l10n.translate('budget.actions.logExpense')),
                                  onPressed: _canEditSelectedBudget ? () => _showAddTransactionDialog() : null,
                                ),
                              ]),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetHeader() {
    return Text(
      _selectedBudget!.name,
      style: Theme.of(context).textTheme.headlineSmall,
    );
  }

  Widget _buildMonthSelector() {
    final months = List.generate(12, (index) {
      final now = DateTime.now();
      return DateTime(now.year, now.month - index, 1);
    });
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(context.l10n.translate('budget.monthView'), style: Theme.of(context).textTheme.titleMedium),
        DropdownButton<DateTime>(
          value: _selectedMonth,
          items: months
              .map((month) => DropdownMenuItem(
                    value: month,
                    child: Text(formatMonthYearLocalized(context, month)),
                  ))
              .toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedMonth = value);
            _loadBudgetDetails();
          },
        ),
      ],
    );
  }

  Widget _buildActionRow(AppLocalizations l10n) {
    if (_selectedBudget == null) {
      return const SizedBox.shrink();
    }

    final exportButton = _canExportSelectedBudget
        ? ElevatedButton.icon(
            onPressed: _isProcessingExport ? null : _exportBudgetCsv,
            icon: const Icon(Icons.table_view),
            label: Text(l10n.translate('export.csv.button')),
          )
        : Tooltip(
            message: l10n.translate('export.denied.tooltip'),
            child: ElevatedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.table_view),
              label: Text(l10n.translate('export.csv.button')),
            ),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          exportButton,
          OutlinedButton.icon(
            onPressed: _canExportSelectedBudget && !_isProcessingExport
                ? () async {
                    final budget = _selectedBudget;
                    if (budget == null) return;
                    setState(() => _isProcessingExport = true);
                    try {
                      await ExportService.exportBudgetReportPdf(user: widget.user, budget: budget, month: _selectedMonth);
                      if (!mounted) return;
                      _showSnack(l10n.translate('export.pdf.success'));
                    } on StateError catch (error) {
                      if (!mounted) return;
                      final message = switch (error.message) {
                        'export_not_allowed' => l10n.translate('export.denied'),
                        'export_no_rows' => l10n.translate('export.empty'),
                        _ => l10n.translate('export.error', params: {'message': error.message}),
                      };
                      _showSnack(message);
                    } catch (error, stack) {
                      if (!mounted) return;
                      showFriendlyError(context, error, stack, userMessage: l10n.translate('errors.genericNetwork'), hint: 'budget_pdf');
                    } finally {
                      if (mounted) setState(() => _isProcessingExport = false);
                    }
                  }
                : null,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(l10n.translate('export.pdf.button')),
          ),
          OutlinedButton.icon(
            onPressed: _isProcessingImport ? null : _showBudgetImportSheet,
            icon: const Icon(Icons.file_upload),
            label: Text(l10n.translate('import.csv.button')),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeOverviewCard() {
    final monthlyIncome = _monthlyIncomeTotal;
    final yearlyIncome = _yearlyIncomeTotal;
    final monthlyBudget = _categories.fold<double>(0, (sum, c) => sum + c.limit);
    final spentThisMonth = _spent.values.fold<double>(0, (sum, value) => sum + value);
    final remaining = monthlyIncome - spentThisMonth;

    String formatCurrencyLocal(double value) => formatCurrencyLocalized(context, value, currency: 'SEK', decimalDigits: 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.translate('budget.overview.title'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryChip(context.l10n.translate('budget.overview.monthlyIncome'), formatCurrencyLocal(monthlyIncome), AppColors.primary),
                _buildSummaryChip(context.l10n.translate('budget.overview.yearlyIncome'), formatCurrencyLocal(yearlyIncome), AppColors.primary.withValues(alpha: 0.8)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSummaryChip(context.l10n.translate('budget.overview.budgeted'), formatCurrencyLocal(monthlyBudget), AppColors.warning),
                _buildSummaryChip(context.l10n.translate('budget.overview.spentThisMonth'), formatCurrencyLocal(spentThisMonth), AppColors.success),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              remaining >= 0
                  ? context.l10n.translate('budget.overview.remaining', params: {'amount': formatCurrencyLocal(remaining)})
                  : context.l10n.translate('budget.overview.overBy', params: {'amount': formatCurrencyLocal(remaining.abs())}),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: remaining >= 0 ? AppColors.success : AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildIncomeSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.l10n.translate('budget.income.title'), style: Theme.of(context).textTheme.titleMedium),
                TextButton.icon(
                  onPressed: _canEditSelectedBudget ? () => _showIncomeDialog() : null,
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.translate('budget.income.add')),
                ),
              ],
            ),
            if (_incomes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  context.l10n.translate('budget.income.empty'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            else
              ..._incomes.map((income) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_money),
                    title: Text(income.description.isEmpty ? context.l10n.translate('budget.income.item.default') : income.description),
                    subtitle: Text(
                      income.frequency == 'monthly'
                          ? '${context.l10n.translate('budget.freq.monthly')} • ${formatCurrencyLocalized(context, income.amount, currency: 'SEK', decimalDigits: 0)}'
                          : '${context.l10n.translate('budget.freq.yearly')} • ${formatCurrencyLocalized(context, income.amount, currency: 'SEK', decimalDigits: 0)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.translate('common.actions.edit'),
                          icon: const Icon(Icons.edit),
                          onPressed: _canEditSelectedBudget ? () => _showIncomeDialog(income: income) : null,
                        ),
                        IconButton(
                          tooltip: context.l10n.translate('common.actions.delete'),
                          icon: const Icon(Icons.delete),
                          onPressed: !_canEditSelectedBudget
                              ? null
                              : () async {
                                  await BudgetService.deleteIncome(income.id);
                                  if (mounted) {
                                    _loadBudgetDetails();
                                  }
                                },
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.account_balance_wallet, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(context.l10n.translate('budget.empty.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.l10n.translate('budget.empty.subtitle'), style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  Widget _buildCategoryCard(BudgetCategory c) {
    final spent = _spent[c.id] ?? 0.0;
    final percentage = c.limit == 0 ? 0.0 : (spent / c.limit) * 100;
    final color = percentage <= 80 ? AppColors.success : (percentage <= 100 ? AppColors.warning : AppColors.danger);
    final monthlyIncome = _monthlyIncomeTotal;
    final share = monthlyIncome > 0 ? (c.limit / monthlyIncome) * 100 : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(c.name, style: Theme.of(context).textTheme.titleMedium),
                Text('${formatCurrencyLocalized(context, spent, currency: 'SEK', decimalDigits: 0)} / ${formatCurrencyLocalized(context, c.limit, currency: 'SEK', decimalDigits: 0)}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: percentage / 100, backgroundColor: Colors.grey[200], color: color),
            const SizedBox(height: 4),
            Text(context.l10n.translate('budget.category.used', params: {'percent': percentage.toStringAsFixed(0)}), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
            if (share != null) ...[
              const SizedBox(height: 4),
              Text(context.l10n.translate('budget.category.shareOfIncome', params: {'percent': share.toStringAsFixed(0)}), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddBudgetDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('budget.dialog.create.title')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.create.name')),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('budget.dialog.create.cancel'))),
          ElevatedButton(onPressed: () async {
            if (nameController.text.isEmpty) return;
            final budget = Budget(id: _uuid.v4(), ownerId: widget.user.id, name: nameController.text, year: DateTime.now().year, createdAt: DateTime.now(), updatedAt: DateTime.now());
            await BudgetService.createBudget(budget);
            if (context.mounted) {
              Navigator.of(context).pop();
              _loadBudgets();
            }
          }, child: Text(context.l10n.translate('budget.dialog.create.submit'))),
        ],
      ),
    );
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    final limitController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('budget.dialog.category.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.category.name')),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: limitController,
              decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.category.limit')),
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('common.cancel'))),
          ElevatedButton(onPressed: () async {
            if (nameController.text.isEmpty || limitController.text.isEmpty) return;
            final cat = BudgetCategory(id: _uuid.v4(), budgetId: _selectedBudget!.id, name: nameController.text, limit: double.parse(limitController.text));
            await BudgetService.createCategory(cat);
            if (context.mounted) {
              Navigator.of(context).pop();
              _loadBudgetDetails();
            }
          }, child: Text(context.l10n.translate('budget.dialog.category.submit'))),
        ],
      ),
    );
  }

  Future<void> _showAddTransactionDialog() async {
    if (_categories.isEmpty || _selectedBudget == null) {
      _showSnack(context.l10n.translate('budget.dialog.tx.pickCategoryFirst'));
      return;
    }

    final descController = TextEditingController();
    final amountController = TextEditingController();
    String? selectedCategoryId = _categories.first.id;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.translate('budget.dialog.tx.title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedCategoryId,
                decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.tx.category')),
                items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                onChanged: (v) => selectedCategoryId = v,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.tx.description')),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).nextFocus(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                decoration: InputDecoration(labelText: context.l10n.translate('budget.dialog.tx.amount')),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(dialogContext).unfocus(),
              ),
            ],
          ),
        ),
        actions: [
            TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.translate('budget.dialog.tx.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selectedCategoryId == null) {
                _showSnack(context.l10n.translate('budget.dialog.tx.selectCategoryPrompt'));
                return;
              }

              final amount = _parseAmount(amountController.text);
                if (amount == null || amount <= 0) {
                  _showSnack(context.l10n.translate('budget.dialog.tx.invalidAmount'));
                return;
              }

              final tx = Transaction(
                id: _uuid.v4(),
                budgetId: _selectedBudget!.id,
                categoryId: selectedCategoryId!,
                type: 'expense',
                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
                amount: amount,
                date: DateTime.now(),
              );

              await BudgetService.createTransaction(tx);
              if (mounted) {
                Navigator.of(dialogContext).pop(true);
              }
            },
              child: Text(context.l10n.translate('budget.dialog.tx.submit')),
          ),
        ],
      ),
    );

    if (saved == true && mounted) {
      await _loadBudgetDetails();
      _showSnack(context.l10n.translate('budget.feedback.txSaved'));
    }
  }

  Future<void> _showIncomeDialog({BudgetIncome? income}) async {
    final isEditing = income != null;
    final descController = TextEditingController(text: income?.description ?? '');
    final amountController = TextEditingController(text: income != null ? income.amount.toStringAsFixed(0) : '');
    String frequency = income?.frequency ?? 'monthly';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: Text(context.l10n.translate(isEditing
                ? 'budget.income.dialog.title.edit'
                : 'budget.income.dialog.title.add')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descController,
                    decoration: InputDecoration(
                      labelText: context.l10n.translate('budget.income.dialog.descOptional'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: context.l10n.translate('budget.income.dialog.amount'),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: frequency,
                    decoration: InputDecoration(
                      labelText: context.l10n.translate('budget.income.dialog.frequency'),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text(context.l10n.translate('budget.income.dialog.monthly')),
                      ),
                      DropdownMenuItem(
                        value: 'yearly',
                        child: Text(context.l10n.translate('budget.income.dialog.yearly')),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() => frequency = value);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.translate('budget.income.dialog.cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = _parseAmount(amountController.text);
                  if (amount == null || amount <= 0) {
                    return;
                  }
                  if (isEditing) {
                    final updated = income!.copyWith(
                      description: descController.text,
                      amount: amount,
                      frequency: frequency,
                    );
                    await BudgetService.updateIncome(updated);
                  } else {
                    final newIncome = BudgetIncome(
                      id: _uuid.v4(),
                      budgetId: _selectedBudget!.id,
                      description: descController.text,
                      amount: amount,
                      frequency: frequency,
                      createdAt: DateTime.now(),
                    );
                    await BudgetService.createIncome(newIncome);
                  }
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _loadBudgetDetails();
                  }
                },
                child: Text(context.l10n.translate('budget.income.dialog.save')),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _exportBudgetCsv() async {
    final l10n = context.l10n;
    final budget = _selectedBudget;
    if (budget == null) {
      return;
    }

    setState(() => _isProcessingExport = true);
    try {
      await ExportService.exportBudgetTransactionsCsv(
        user: widget.user,
        budget: budget,
        month: _selectedMonth,
      );
      if (!mounted) return;
      _showSnack(l10n.translate('export.csv.success'));
    } on StateError catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'export_not_allowed' => l10n.translate('export.denied'),
        'export_no_rows' => l10n.translate('export.empty'),
        _ => l10n.translate('export.error', params: {'message': error.message}),
      };
      _showSnack(message);
    } catch (error, stack) {
      if (!mounted) return;
      showFriendlyError(context, error, stack, userMessage: l10n.translate('errors.genericNetwork'), hint: 'budget_export');
    } finally {
      if (mounted) {
        setState(() => _isProcessingExport = false);
      }
    }
  }

  Future<void> _showBudgetImportSheet() async {
    final l10n = context.l10n;
    final budget = _selectedBudget;
    if (budget == null) return;
    List<List<dynamic>>? rows;
    List<String> headers = [];
    final fieldMap = <String, String>{
      'date': '',
      'category': '',
      'type': '',
      'amount': '',
      'description': '',
    };
    String? error;

    List<String> _columns() => headers.isNotEmpty
        ? headers
        : (rows != null && rows!.isNotEmpty ? List<String>.generate(rows!.first.length, (i) => 'col_${i + 1}') : <String>[]);

    void preselectMappings() {
      if (headers.isEmpty) return;
      for (final h in headers) {
        final key = h.toLowerCase();
        if (key.contains('date') || key.contains('datum')) fieldMap['date'] = h;
        if (key.contains('category') || key.contains('kategori')) fieldMap['category'] = h;
        if (key.contains('type') || key.contains('typ')) fieldMap['type'] = h;
        if (key.contains('amount') || key.contains('belopp')) fieldMap['amount'] = h;
        if (key.contains('desc') || key.contains('beskriv')) fieldMap['description'] = h;
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
            // Build category name -> id map
            final categories = await BudgetService.getCategories(budget.id);
            final byName = {for (final c in categories) c.name.toLowerCase(): c.id};
            int imported = 0;
            for (final row in rows!.take(2000)) {
              try {
                final date = _parseDate(_cellAsString(row, fieldMap['date']!)) ?? DateTime.now();
                final type = (_cellAsString(row, fieldMap['type']!) ?? 'expense').toLowerCase();
                final amount = _parseAmountLocal(_cellAsString(row, fieldMap['amount']!)) ?? 0.0;
                final description = _cellAsString(row, fieldMap['description']!);
                final categoryLabel = (_cellAsString(row, fieldMap['category']!) ?? '').toLowerCase();
                String? categoryId = byName[categoryLabel];
                categoryId ??= categories.isNotEmpty ? categories.first.id : null;
                if (categoryId == null) continue;
                final tx = Transaction(
                  id: const Uuid().v4(),
                  budgetId: budget.id,
                  categoryId: categoryId,
                  type: type == 'income' ? 'income' : 'expense',
                  description: description?.trim().isEmpty == true ? null : description?.trim(),
                  amount: amount,
                  date: date,
                );
                await BudgetService.createTransaction(tx);
                imported++;
              } catch (_) {}
            }
            if (!mounted) return;
            Navigator.of(context).pop();
            await _loadBudgetDetails();
            _showSnack(l10n.translate('import.csv.success', params: {'count': imported}));
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
            final sample = rows!.take(5).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.translate('import.csv.preview'), style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                ...sample.map((r) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.list),
                      title: Text('${_cellAsString(r, fieldMap['amount']!)} • ${_cellAsString(r, fieldMap['category']!)}'),
                      subtitle: Text('${_cellAsString(r, fieldMap['date']!)} • ${_cellAsString(r, fieldMap['description']!)}'),
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

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  double? _parseAmount(String raw) {
    final normalized = raw.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  double get _monthlyIncomeTotal => _incomes.fold(0.0, (sum, income) => sum + income.monthlyAmount);

  double get _yearlyIncomeTotal => _incomes.fold(0.0, (sum, income) => sum + income.yearlyAmount);
}
