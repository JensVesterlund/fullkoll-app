import 'package:flutter/material.dart';
import '../i18n/app_localizations.dart';

class DevGuestBanner extends StatelessWidget {
  final Future<void> Function()? onLogout;

  const DevGuestBanner({super.key, this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.engineering, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.l10n.translate('dev.guest.mode') + ' – ' + context.l10n.translate('dev.guest.dataMayBeCleared'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (onLogout != null)
            TextButton(
              onPressed: () {
                onLogout!();
              },
              child: Text(context.l10n.translate('dev.guest.logout')),
            ),
        ],
      ),
    );
  }
}