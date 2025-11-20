import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PrivacyConsentScreen extends StatefulWidget {
  final String userEmail;
  final Future<void> Function() onAccept;

  const PrivacyConsentScreen({super.key, required this.userEmail, required this.onAccept});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _isProcessing = false;
  String? _error;

  Future<void> _handleAccept() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });
    try {
      await widget.onAccept();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Kunde inte spara godkännandet. Försök igen.';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final headline = widget.userEmail.isEmpty ? 'Välkommen!' : 'Hej ${widget.userEmail}!';

    return Scaffold(
      appBar: AppBar(title: const Text('Sekretesspolicy')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(headline, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              const Text(
                'Full Koll lagrar all data lokalt på din enhet med krypterat skydd. '
                'Vi delar aldrig innehåll med tredje part och du kan exportera eller radera information när som helst.',
              ),
              const SizedBox(height: 16),
              const Text(
                'För att fortsätta behöver vi ditt godkännande av sekretesspolicyn. '
                'Du kan läsa hela policyn innan du väljer att fortsätta.',
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _isProcessing ? null : _handleAccept,
                child: _isProcessing
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Jag godkänner'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/legal/privacy'),
                child: const Text('Läs fullständig policy'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
