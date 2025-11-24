import 'package:flutter/material.dart';
import '../utils/formatting.dart';

import '../models.dart';

class BudgetChart extends StatefulWidget {
  final List<BudgetCategory> categories;
  final Map<String, double> spentAmounts;

  const BudgetChart({
    super.key,
    required this.categories,
    required this.spentAmounts,
  });

  @override
  State<BudgetChart> createState() => _BudgetChartState();
}

class _BudgetChartState extends State<BudgetChart> {
  String _signature = '';
  List<_BudgetBar> _bars = const [];
  double _maxValue = 0;

  @override
  void initState() {
    super.initState();
    _rebuildCache(useSetState: false);
  }

  @override
  void didUpdateWidget(covariant BudgetChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSignature = _buildSignature();
    if (nextSignature != _signature) {
      _rebuildCache(signatureOverride: nextSignature);
    }
  }

  void _rebuildCache({String? signatureOverride, bool useSetState = true}) {
    final bars = <_BudgetBar>[];
    double maxValue = 0;
    for (final category in widget.categories) {
      final spent = widget.spentAmounts[category.id] ?? 0;
      bars.add(_BudgetBar(label: category.name, spent: spent, limit: category.limit));
      final bound = category.limit > 0 ? category.limit : spent;
      if (bound > maxValue) {
        maxValue = bound;
      }
      if (spent > maxValue) {
        maxValue = spent;
      }
    }
    void assign() {
      _bars = bars;
      _maxValue = maxValue == 0 ? 1 : maxValue;
      _signature = signatureOverride ?? _buildSignature();
    }

    if (!useSetState || !mounted) {
      assign();
    } else {
      setState(assign);
    }
  }

  String _buildSignature() {
    final catPart = widget.categories.map((c) => '${c.id}:${c.limit}:${c.name.hashCode}').join('|');
    final spentPart = widget.spentAmounts.entries.map((e) => '${e.key}:${e.value.toStringAsFixed(2)}').toList()
      ..sort();
    return '$catPart::${spentPart.join('|')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_bars.isEmpty) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _bars.map((bar) => _buildRow(context, bar)).toList(),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _BudgetBar bar) {
    final theme = Theme.of(context);
    final spentFraction = (bar.spent / _maxValue).clamp(0.0, 1.0);
    final limitFraction = (bar.limit / _maxValue).clamp(0.0, 1.0);
    final overBudget = bar.limit > 0 && bar.spent > bar.limit;
    final progressColor = overBudget ? theme.colorScheme.error : theme.colorScheme.primary;

    final semanticsLabel = '${bar.label}: '
        '${formatCurrencyLocalized(context, bar.spent, currency: 'SEK', decimalDigits: 0)} '
        'av ${formatCurrencyLocalized(context, bar.limit, currency: 'SEK', decimalDigits: 0)}';
    return Semantics(
      label: semanticsLabel,
      slider: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(bar.label, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: 12),
                Text(
                  '${formatCurrencyLocalized(context, bar.spent, currency: 'SEK', decimalDigits: 0)} / ${formatCurrencyLocalized(context, bar.limit, currency: 'SEK', decimalDigits: 0)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: limitFraction,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: spentFraction,
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: progressColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetBar {
  final String label;
  final double spent;
  final double limit;

  const _BudgetBar({required this.label, required this.spent, required this.limit});
}