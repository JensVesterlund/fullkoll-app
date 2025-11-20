import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'i18n/app_localizations.dart';

class DevI18nScreen extends StatefulWidget {
  const DevI18nScreen({super.key});

  @override
  State<DevI18nScreen> createState() => _DevI18nScreenState();
}

class _DevI18nScreenState extends State<DevI18nScreen> {
  Map<String, String> _sv = const {};
  Map<String, String> _en = const {};
  bool _loading = true;
  bool _highlightMissing = AppLocalizations.debugHighlightMissing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rawSv = await rootBundle.loadString('assets/i18n/sv-SE.json');
      final rawEn = await rootBundle.loadString('assets/i18n/en-US.json');
      final sanitizedSv = rawSv
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
          .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1')
          .replaceAll(RegExp(r',(?=\s*[}\]])'), '');
      final sanitizedEn = rawEn
          .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
          .replaceAll(RegExp(r'([^:])//.*$', multiLine: true), r'$1')
          .replaceAll(RegExp(r',(?=\s*[}\]])'), '');
      final sv = Map<String, String>.from(json.decode(sanitizedSv) as Map);
      final en = Map<String, String>.from(json.decode(sanitizedEn) as Map);
      setState(() {
        _sv = sv;
        _en = en;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _missingInEn {
    final missing = <String>[];
    for (final key in _sv.keys) {
      if (!_en.containsKey(key)) missing.add(key);
    }
    missing.sort();
    return missing;
  }

  Map<String, _NamespaceCoverage> get _coverageByNamespace {
    final map = <String, _NamespaceCoverage>{};
    for (final key in _sv.keys) {
      final ns = key.contains('.') ? key.split('.').first : 'root';
      map.putIfAbsent(ns, () => _NamespaceCoverage());
      map[ns]!.sv++;
      if (_en.containsKey(key)) map[ns]!.en++;
    }
    return map;
  }

  double get _coverageTotal {
    if (_sv.isEmpty) return 1.0;
    int en = 0;
    for (final key in _sv.keys) {
      if (_en.containsKey(key)) en++;
    }
    return en / _sv.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('i18n diagnostics (dev only)'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _CoverageCard(
                          title: 'Total coverage',
                          value: (_coverageTotal * 100).toStringAsFixed(1) + '%',
                          good: _coverageTotal >= 0.99,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Highlight [MISSING:*] red'),
                                Switch(
                                  value: _highlightMissing,
                                  onChanged: (v) {
                                    setState(() {
                                      _highlightMissing = v;
                                      AppLocalizations.debugHighlightMissing = v;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Coverage by namespace', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _coverageByNamespace.entries.map((e) {
                        final cov = e.value;
                        final pct = cov.sv == 0 ? 1.0 : cov.en / cov.sv;
                        return _CoveragePill(namespace: e.key, pct: pct);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Missing keys in en-US (${_missingInEn.length})', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _missingInEn.isEmpty
                        ? const Center(child: Text('No missing keys. ✅'))
                        : ListView.separated(
                            itemCount: _missingInEn.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final key = _missingInEn[i];
                              final ns = key.split('.').first;
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.error_outline, color: Colors.red),
                                title: Text(key),
                                subtitle: Text('ns: $ns'),
                                trailing: const Text('en-US missing'),
                              );
                            },
                          ),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    Text('Terminology (commented in i18n files)', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 4),
                    const Text('Kvitton → Receipts; Presentkort → Gift Cards; Budget → Budget; Kostnadsdelning → Cost Split; Autogiro → Subscriptions / Direct Debits; Påminnelse → Reminder; Utgångsdatum → Expiry Date; Balans → Balance; Belopp → Amount; Giltig till → Valid until; Delning → Sharing; Roller → Roles; Visare/Redaktör/Ägare → Viewer/Editor/Owner; Exportera/Importera → Export/Import; Radera → Delete; Spara → Save; Redigera → Edit; Ångra → Undo; Arkiverad → Archived; Återställ lösenord → Reset password; Skanna → Scan; Filuppladdning → File upload'),
                  ],
                ],
              ),
            ),
    );
  }
}

class _CoverageCard extends StatelessWidget {
  final String title;
  final String value;
  final bool good;
  const _CoverageCard({required this.title, required this.value, required this.good});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            Row(
              children: [
                Icon(good ? Icons.check_circle : Icons.error, color: good ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CoveragePill extends StatelessWidget {
  final String namespace;
  final double pct;
  const _CoveragePill({required this.namespace, required this.pct});

  @override
  Widget build(BuildContext context) {
    final color = pct >= 0.99 ? Colors.green : (pct >= 0.95 ? Colors.orange : Colors.red);
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(namespace),
          const SizedBox(width: 8),
          Text('${(pct * 100).toStringAsFixed(0)}%'),
        ],
      ),
    );
  }
}

class _NamespaceCoverage {
  int sv = 0;
  int en = 0;
}
