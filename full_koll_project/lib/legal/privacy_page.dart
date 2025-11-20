import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('legal.privacy.title'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          children: [
            Text(l10n.translate('legal.privacy.heading'), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(
              l10n.translate('legal.privacy.version'),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            _Section(
              title: l10n.translate('legal.privacy.sections.dataStored.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.dataStored.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.why.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.why.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.legal.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.legal.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.retention.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.retention.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.export.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.export.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.sharing.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.sharing.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.deletion.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.deletion.paragraphs')],
            ),
            _Section(
              title: l10n.translate('legal.privacy.sections.contact.title'),
              paragraphs: [l10n.translate('legal.privacy.sections.contact.paragraphs')],
            ),
            const SizedBox(height: 40),
            TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: Text(l10n.translate('common.back')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<String> paragraphs;

  const _Section({required this.title, required this.paragraphs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...paragraphs.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(p, style: theme.textTheme.bodyMedium),
              )),
        ],
      ),
    );
  }
}