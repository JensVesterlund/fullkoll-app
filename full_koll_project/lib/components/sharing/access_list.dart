import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../models.dart';

class AccessList extends StatelessWidget {
  final String? ownerLabel;
  final List<ShareGrant> grants;
  final Map<String, String> principalLabels;
  final bool isProcessing;
  final void Function(ShareGrant grant, String role) onUpdateRole;
  final void Function(ShareGrant grant) onRevoke;
  final void Function(ShareGrant grant, bool allowExport) onToggleExport;

  const AccessList({
    super.key,
    required this.grants,
    required this.principalLabels,
    required this.onUpdateRole,
    required this.onRevoke,
    required this.onToggleExport,
    this.ownerLabel,
    this.isProcessing = false,
  });

  String _roleLabel(String role) {
    switch (role) {
      case ShareRoles.owner:
        return 'sharing.role.owner';
      case ShareRoles.editor:
        return 'sharing.role.editor';
      default:
        return 'sharing.role.viewer';
    }
  }

  Color _statusColor(String status, ThemeData theme) {
    switch (status) {
      case 'active':
        return theme.colorScheme.primary;
      case 'pending':
        return theme.colorScheme.tertiary;
      case 'revoked':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final tiles = <Widget>[];

    if (ownerLabel != null && ownerLabel!.isNotEmpty) {
      tiles.add(
        ListTile(
          leading: const Icon(Icons.lock, color: Colors.black54),
          title: Text(ownerLabel!, style: theme.textTheme.bodyLarge),
          subtitle: Text('${l10n.translate(_roleLabel(ShareRoles.owner))} • ${l10n.translate('sharing.owner.fullAccess')}'),
        ),
      );
    }

    for (final grant in grants) {
      final label = principalLabels[grant.id] ?? grant.principal;
      tiles.add(
        ListTile(
          leading: Icon(
            grant.role == ShareRoles.editor ? Icons.edit_outlined : Icons.visibility_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(label, style: theme.textTheme.bodyLarge),
          subtitle: Text('${l10n.translate(_roleLabel(grant.role))} • ${l10n.translate(_statusKey(grant.status))}') ,
          trailing: isProcessing
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message: grant.role == ShareRoles.editor
                          ? l10n.translate('share.allowExport.always')
                          : (grant.allowExport
                              ? l10n.translate('share.allowExport.enabled')
                              : l10n.translate('share.allowExport.disabled')),
                      child: Switch.adaptive(
                        value: grant.role == ShareRoles.editor ? true : grant.allowExport,
                        activeColor: theme.colorScheme.primary,
                        onChanged: (!grant.isRevoked && grant.role != ShareRoles.editor)
                            ? (value) => onToggleExport(grant, value)
                            : null,
                      ),
                    ),
                    PopupMenuButton<String>(
                      enabled: !grant.isRevoked,
                      onSelected: (value) {
                        switch (value) {
                          case 'make_viewer':
                            onUpdateRole(grant, ShareRoles.viewer);
                            break;
                          case 'make_editor':
                            onUpdateRole(grant, ShareRoles.editor);
                            break;
                          case 'revoke':
                            onRevoke(grant);
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (grant.role != ShareRoles.viewer)
                          PopupMenuItem(value: 'make_viewer', child: Text(l10n.translate('share.roles.makeViewer'))),
                        if (grant.role != ShareRoles.editor)
                          PopupMenuItem(value: 'make_editor', child: Text(l10n.translate('share.roles.makeEditor'))),
                        const PopupMenuDivider(),
                        PopupMenuItem(value: 'revoke', child: Text(l10n.translate('share.roles.revoke'))),
                      ],
                      child: Chip(
                        backgroundColor: _statusColor(grant.status, theme).withValues(alpha: 0.12),
                        label: Text(
                          l10n.translate(_roleLabel(grant.role)),
                          style: theme.textTheme.bodySmall?.copyWith(color: _statusColor(grant.status, theme)),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }

    if (tiles.isEmpty) {
      tiles.add(
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.translate('sharing.empty.title')),
          subtitle: Text(l10n.translate('sharing.empty.subtitle')),
        ),
      );
    }

    return Column(children: tiles);
  }

  String _statusKey(String status) {
    switch (status) {
      case 'active':
        return 'sharing.status.active';
      case 'pending':
        return 'sharing.status.pending';
      case 'revoked':
        return 'sharing.status.revoked';
      default:
        return status;
    }
  }
}