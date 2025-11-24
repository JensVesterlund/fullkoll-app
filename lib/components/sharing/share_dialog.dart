import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../models.dart';
import '../../services.dart';
import 'access_list.dart';

class ShareDialog extends StatefulWidget {
  final User user;
  final String resourceType;
  final String resourceId;
  final String? resourceName;
  final String? ownerId;

  const ShareDialog({
    super.key,
    required this.user,
    required this.resourceType,
    required this.resourceId,
    this.resourceName,
    this.ownerId,
  });

  @override
  State<ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<ShareDialog> {
  final TextEditingController _emailController = TextEditingController();
  String _selectedRole = ShareRoles.viewer;
  bool _isLoading = true;
  bool _isProcessing = false;
  List<ShareGrant> _grants = const [];
  Map<String, String> _labels = const {};
  String? _ownerEmail;
  bool _allowExportForInvite = false;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadAccess() async {
    setState(() {
      _isLoading = true;
      _isProcessing = false;
    });

    try {
      final owner = await SharingService.getOwnerEmail(
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
      );
      final grants = await SharingService.listGrants(
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
      );
      grants.sort((a, b) {
        int statusRank(String status) {
          switch (status) {
            case 'active':
              return 0;
            case 'pending':
              return 1;
            case 'revoked':
              return 2;
            default:
              return 3;
          }
        }

        final rankCompare = statusRank(a.status).compareTo(statusRank(b.status));
        if (rankCompare != 0) return rankCompare;
        return b.createdAt.compareTo(a.createdAt);
      });

      final labelMap = <String, String>{};
      for (final grant in grants) {
        labelMap[grant.id] = await SharingService.resolvePrincipalLabel(grant);
      }

      setState(() {
        _ownerEmail = owner;
        _grants = grants;
        _labels = labelMap;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.translate('share.load.error', params: {'message': error.toString()}))),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _invite() async {
    final l10n = context.l10n;
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.invite.emailRequired'))),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      await SharingService.invite(
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        fromUser: widget.user,
        email: email,
        role: _selectedRole,
        allowExport: _allowExportForInvite || _selectedRole == ShareRoles.editor,
      );
      _emailController.clear();
      setState(() {
        _selectedRole = ShareRoles.viewer;
        _allowExportForInvite = false;
      });
      await _loadAccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.invite.sent', params: {'email': email}))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.invite.error', params: {'message': error.toString()}))),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _updateRole(ShareGrant grant, String role) async {
    final l10n = context.l10n;
    setState(() => _isProcessing = true);
    try {
      await SharingService.updateRole(grant: grant, role: role, actor: widget.user);
      await _loadAccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.roles.updated'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.roles.error', params: {'message': error.toString()}))),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _revoke(ShareGrant grant) async {
    final l10n = context.l10n;
    setState(() => _isProcessing = true);
    try {
      await SharingService.revoke(grant, actor: widget.user);
      await _loadAccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.revoke.success'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.revoke.error', params: {'message': error.toString()}))),
      );
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _toggleExport(ShareGrant grant, bool allow) async {
    final l10n = context.l10n;
    setState(() => _isProcessing = true);
    try {
      await SharingService.setAllowExport(grant: grant, allowExport: allow, actor: widget.user);
      await _loadAccess();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allow
                ? l10n.translate('share.allowExport.enabledFeedback')
                : l10n.translate('share.allowExport.disabledFeedback'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('share.allowExport.error', params: {'message': error.toString()}))),
      );
      setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.resourceName ?? l10n.translate('share.dialog.title'),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.translate('common.actions.close'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(l10n.translate('share.dialog.description'), style: theme.textTheme.bodyMedium),
                const SizedBox(height: 24),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else
                  AccessList(
                    ownerLabel: _ownerEmail,
                    grants: _grants,
                    principalLabels: _labels,
                    isProcessing: _isProcessing,
                    onUpdateRole: _updateRole,
                    onRevoke: _revoke,
                    onToggleExport: _toggleExport,
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Text(l10n.translate('share.invite.title'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  enabled: !_isProcessing,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.translate('share.invite.emailLabel'),
                    hintText: 'namn@example.com',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedRole,
                        onChanged: _isProcessing ? null : (value) => setState(() => _selectedRole = value ?? ShareRoles.viewer),
                        items: [
                          DropdownMenuItem(value: ShareRoles.viewer, child: Text(l10n.translate('share.roles.viewerLabel'))),
                          DropdownMenuItem(value: ShareRoles.editor, child: Text(l10n.translate('share.roles.editorLabel'))),
                        ],
                        decoration: InputDecoration(labelText: l10n.translate('share.roles.label')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  value: _selectedRole == ShareRoles.editor ? true : _allowExportForInvite,
                  onChanged: _isProcessing || _selectedRole == ShareRoles.editor
                      ? null
                      : (value) => setState(() => _allowExportForInvite = value),
                  title: Text(l10n.translate('share.allowExport.switchLabel')),
                  subtitle: Text(l10n.translate('share.allowExport.switchHint')),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _invite,
                  icon: const Icon(Icons.send),
                  label: Text(l10n.translate('share.invite.submit')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}