import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'ocr_service.dart';
import 'i18n/app_localizations.dart';

class DevOcrScreen extends StatefulWidget {
  const DevOcrScreen({super.key});

  @override
  State<DevOcrScreen> createState() => _DevOcrScreenState();
}

class _DevOcrScreenState extends State<DevOcrScreen> {
  final TextEditingController _fileNameCtrl = TextEditingController(text: 'ica_kvitto_437kr.jpg');
  bool _isGiftCard = false;
  String _status = '';
  Map<String, String> _results = const {};
  bool _working = false;

  Future<void> _run() async {
    setState(() {
      _working = true;
      _status = 'Analys pågår...';
      _results = const {};
    });
    try {
      final bytes = Uint8List(0); // mock path: current OCR uses only the filename
      final fileName = _fileNameCtrl.text.trim();
      if (fileName.isEmpty) {
        setState(() {
          _status = 'Filnamn krävs';
          _working = false;
        });
        return;
      }
      if (_isGiftCard) {
        final res = await OcrService.analyzeGiftCard(bytes: bytes, fileName: fileName);
        setState(() {
          _results = {
            'brand': _fmt(res.brand.value, res.brand.confidence),
            'cardNumber': _fmt(res.cardNumber.value, res.cardNumber.confidence),
            'amount': _fmt(res.amount.value, res.amount.confidence),
            'expiresAt': _fmt(res.expiresAt.value, res.expiresAt.confidence),
          };
          _status = res.hasAnyData ? 'Klart' : 'Inget hittades';
        });
      } else {
        final res = await OcrService.analyzeReceipt(bytes: bytes, fileName: fileName);
        setState(() {
          _results = {
            'store': _fmt(res.store.value, res.store.confidence),
            'purchaseDate': _fmt(res.purchaseDate.value, res.purchaseDate.confidence),
            'amount': _fmt(res.amount.value, res.amount.confidence),
            'vat': _fmt(res.vat.value, res.vat.confidence),
            'currency': res.currency,
          };
          _status = res.hasAnyData ? 'Klart' : 'Inget hittades';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Fel: $e';
      });
    } finally {
      setState(() => _working = false);
    }
  }

  String _fmt(Object? v, double c) {
    if (v == null) return '-';
    return '$v (conf ${c.toStringAsFixed(2)})';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text('OCR-test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Snabbtest av mockad OCR utifrån filnamn', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fileNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Filnamn som hint till OCR',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Kvitto')),
                    ButtonSegment(value: true, label: Text('Presentkort')),
                  ],
                  selected: {_isGiftCard},
                  onSelectionChanged: (s) => setState(() => _isGiftCard = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _working ? null : _run,
              icon: const Icon(Icons.text_snippet_outlined),
              label: const Text('Kör analys'),
            ),
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: ListView(
                    children: _results.entries
                        .map((e) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      e.key,
                                      style: Theme.of(context).textTheme.labelLarge,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(e.value)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
