import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'i18n/app_localizations.dart';
import 'utils/formatting.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'services.dart';
import 'theme.dart';
import 'widgets/dev_guest_banner.dart';
import 'components/sharing/share_dialog.dart';

const _uuid = Uuid();

class SplitScreen extends StatefulWidget {
  final User user;
  final Future<void> Function()? onLogout;

  const SplitScreen({super.key, required this.user, this.onLogout});

  @override
  State<SplitScreen> createState() => _SplitScreenState();
}

class _SplitScreenState extends State<SplitScreen> {
  List<SplitGroup> _groups = [];
  SplitGroup? _selectedGroup;
  List<Participant> _participants = [];
  List<Expense> _expenses = [];
  List<SplitAccessGrant> _accessGrants = [];
  List<Settlement> _settlements = [];
  bool _isLoading = true;
  ShareAccess? _currentGroupAccess;
  bool _isGroupAccessLoading = false;
  String? _groupOwnerEmail;
  Map<String, String> _accessGrantLabels = {};

  bool get _canEditGroup {
    final group = _selectedGroup;
    if (group == null) return false;
    if (_currentGroupAccess != null) {
      return _currentGroupAccess!.canEdit;
    }
    return group.creatorId == widget.user.id;
  }

  bool get _canShareGroup {
    final group = _selectedGroup;
    if (group == null) return false;
    if (_currentGroupAccess != null) {
      return _currentGroupAccess!.canShare;
    }
    return group.creatorId == widget.user.id;
  }

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() => _isLoading = true);
    _groups = await SplitService.getAllSplitGroups(widget.user.id, email: widget.user.email);
    if (_groups.isNotEmpty) {
      _selectedGroup = _groups.first;
      await _loadGroupDetails();
      await _loadGroupAccess();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadGroupDetails() async {
    if (_selectedGroup == null) return;
    final participants = await SplitService.getParticipants(_selectedGroup!.id);
    final expenses = await SplitService.getExpenses(_selectedGroup!.id);
    final accessGrants = await SplitService.getAccessGrants(_selectedGroup!.id);
    final settlements = await SplitService.getSettlements(_selectedGroup!.id);
    final labelMap = <String, String>{};
    for (final grant in accessGrants) {
      if (grant.principal.contains('@')) {
        labelMap[grant.id] = grant.principal;
      } else {
        final user = await UserService.getById(grant.principal);
        labelMap[grant.id] = user?.email ?? context.l10n.translate('split.owner.unknown');
      }
    }
    setState(() {
      _participants = participants;
      _expenses = expenses;
      _accessGrants = accessGrants;
      _settlements = settlements;
      _accessGrantLabels = labelMap;
    });
  }

  Future<void> _loadGroupAccess() async {
    final group = _selectedGroup;
    if (group == null) return;
    setState(() => _isGroupAccessLoading = true);
    try {
      final ownerEmail = await SharingService.getOwnerEmail(
        resourceType: 'split_group',
        resourceId: group.id,
      );
      final access = await SharingService.getAccessForUser(
        resourceType: 'split_group',
        resourceId: group.id,
        user: widget.user,
        ownerId: group.creatorId,
      );
      if (!mounted) return;
      setState(() {
        _currentGroupAccess = access;
        _isGroupAccessLoading = false;
        _groupOwnerEmail = ownerEmail;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isGroupAccessLoading = false);
    }
  }

  Future<void> _confirmRemoveParticipant(Participant participant) async {
    final hasExpenses = _expenses.any((e) => e.paidBy == participant.id || e.sharedWith.contains(participant.id));
    if (hasExpenses) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.translate('split.remove.cannotTitle')),
          content: Text(context.l10n.translate('split.remove.cannotBody')),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('common.ok'))),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.l10n.translate('split.remove.tooltip')),
            content: Text('${participant.name}?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.l10n.translate('common.cancel'))),
              ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: Text(context.l10n.translate('common.delete'))),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await SplitService.deleteParticipant(participant.id);
    await _loadGroupDetails();
  }

  String _formatGrantSubtitle(SplitAccessGrant grant) {
    final l10n = context.l10n;
    final roleLabel = switch (grant.role) {
      'editor' => l10n.translate('sharing.role.editor'),
      'owner' => l10n.translate('sharing.role.owner'),
      _ => l10n.translate('sharing.role.viewer'),
    };
    final statusLabel = switch (grant.status) {
      'accepted' => l10n.translate('sharing.status.active'),
      'revoked' => l10n.translate('sharing.status.revoked'),
      _ => l10n.translate('sharing.status.pending'),
    };
    return '$roleLabel • $statusLabel';
  }

  String _participantName(String id) {
    for (final p in _participants) {
      if (p.id == id) return p.name;
    }
    return context.l10n.translate('split.owner.unknown');
  }

  Future<void> _toggleSettlementReminder(Settlement settlement, bool enable) async {
    try {
      final updated = await SplitService.toggleSettlementReminder(settlement: settlement, enable: enable);
      if (!mounted) return;
      setState(() {
        final index = _settlements.indexWhere((s) => s.id == settlement.id);
        if (index != -1) {
          _settlements[index] = updated;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enable ? context.l10n.translate('split.reminder.enabled') : context.l10n.translate('split.reminder.disabled'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.translate('split.reminder.updateError'))),
      );
    }
  }

  Widget _buildSettlementCard(Settlement settlement) {
    final payerName = _participantName(settlement.payerId);
    final receiverName = _participantName(settlement.receiverId);
    final theme = Theme.of(context);
    final isSettled = settlement.status == 'settled';
    final reminderActive = settlement.reminderJobId != null;
    final canModify = _canEditGroup;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$payerName → $receiverName',
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatCurrencyLocalized(context, settlement.amount, currency: 'SEK', decimalDigits: 0),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isSettled
                  ? context.l10n.translate('split.settlement.status.settled')
                  : context.l10n.translate('split.settlement.status.pending'),
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.translate('split.settlement.reminder.title')),
              subtitle: Text(context.l10n.translate('split.settlement.reminder.subtitle')),
              value: reminderActive,
              onChanged: isSettled || !canModify ? null : (value) => _toggleSettlementReminder(settlement, value),
            ),
            Text(
              '${context.l10n.translate('split.createdOn')}: ${formatDateShortLocalized(context, settlement.createdAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGrantAction(SplitAccessGrant grant, String action) async {
    switch (action) {
      case 'role_viewer':
        await SplitService.updateAccessGrant(grant.copyWith(role: 'viewer'));
        break;
      case 'role_editor':
        await SplitService.updateAccessGrant(grant.copyWith(role: 'editor'));
        break;
      case 'mark_accept':
        await SplitService.updateAccessGrant(grant.copyWith(status: 'accepted', respondedAt: DateTime.now()));
        break;
      case 'mark_pending':
        await SplitService.updateAccessGrant(grant.copyWith(status: 'pending', respondedAt: null));
        break;
      case 'revoke':
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Återkalla behörighet'),
                content: Text('Vill du återkalla åtkomst för ${grant.principal}?'),
                actions: [
                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Avbryt')),
                  ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Återkalla')),
                ],
              ),
            ) ??
            false;
        if (!confirmed) return;
        await SplitService.updateAccessGrant(grant.copyWith(status: 'revoked', respondedAt: DateTime.now()));
        break;
    }

    await _loadGroupDetails();
  }

  void _showInviteDialog() {
    if (_selectedGroup == null) return;
    final emailController = TextEditingController();
    String role = 'viewer';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.translate('split.invite.title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                decoration: InputDecoration(labelText: context.l10n.translate('split.invite.email')),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: role,
                decoration: InputDecoration(labelText: context.l10n.translate('split.invite.role')),
                items: [
                  DropdownMenuItem(value: 'viewer', child: Text(context.l10n.translate('split.invite.role.viewer'))),
                  DropdownMenuItem(value: 'editor', child: Text(context.l10n.translate('split.invite.role.editor'))),
                ],
                onChanged: (value) => setDialogState(() {
                  role = value ?? 'viewer';
                }),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('split.invite.cancel'))),
            ElevatedButton(
              onPressed: () async {
                if (emailController.text.trim().isEmpty) return;
                final grant = SplitAccessGrant(
                  id: _uuid.v4(),
                  splitGroupId: _selectedGroup!.id,
                  principal: emailController.text.trim(),
                  role: role,
                  status: 'pending',
                  invitedAt: DateTime.now(),
                );
                await SplitService.createAccessGrant(grant);
                Navigator.of(context).pop();
                if (!mounted) return;
                await _loadGroupDetails();
              },
              child: Text(context.l10n.translate('split.invite.send')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = widget.user.id == AuthService.guestUserId;
    final lockedParticipantIds = _expenses.fold<Set<String>>(<String>{}, (acc, expense) {
      acc.add(expense.paidBy);
      acc.addAll(expense.sharedWith);
      return acc;
    });
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('split.title')),
        actions: [
          if (_selectedGroup != null && _canShareGroup && !_isGroupAccessLoading)
            IconButton(
              tooltip: l10n.translate('common.actions.share'),
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                final group = _selectedGroup;
                if (group == null) return;
                await showDialog(
                  context: context,
                  builder: (_) => ShareDialog(
                    user: widget.user,
                    resourceType: 'split_group',
                    resourceId: group.id,
                    resourceName: '${l10n.translate('split.title')} – ${group.title}',
                    ownerId: group.creatorId,
                  ),
                );
                await _loadGroupDetails();
                await _loadGroupAccess();
              },
            ),
          if (_groups.isNotEmpty)
            DropdownButton<SplitGroup>(
              value: _selectedGroup,
              underline: Container(),
              items: _groups.map((g) => DropdownMenuItem(value: g, child: Text(g.title))).toList(),
              onChanged: (g) async {
                _selectedGroup = g;
                await _loadGroupDetails();
                await _loadGroupAccess();
              },
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddGroupDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (isGuest) DevGuestBanner(onLogout: widget.onLogout),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _groups.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(_selectedGroup!.title, style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 16),
                          Text(l10n.translate('split.participants'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ..._participants.map((p) {
                            final canRemove = _canEditGroup && !lockedParticipantIds.contains(p.id);
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(child: Text(p.name.isNotEmpty ? p.name[0].toUpperCase() : '?')),
                                title: Text(p.name),
                                subtitle: Text(p.contact.isEmpty ? 'Ingen kontakt' : p.contact),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatCurrencyLocalized(context, p.balance, currency: 'SEK', decimalDigits: 0),
                                      style: TextStyle(fontWeight: FontWeight.w600, color: p.balance >= 0 ? AppColors.success : AppColors.danger),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.person_remove_alt_1_outlined, size: 20),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                       tooltip: canRemove
                                           ? l10n.translate('split.remove.tooltip')
                                           : (_canEditGroup ? l10n.translate('split.remove.locked') : l10n.translate('split.remove.unauthorized')),
                                       onPressed: canRemove ? () => _confirmRemoveParticipant(p) : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person_add),
                            label: Text(l10n.translate('split.addParticipant')),
                            onPressed: _canEditGroup ? () => _showAddParticipantDialog() : null,
                          ),
                          const SizedBox(height: 24),
                          Text(l10n.translate('split.sharing'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                           Card(
                             child: ListTile(
                               leading: const Icon(Icons.verified_user, color: AppColors.primary),
                                title: Text(_groupOwnerEmail ?? l10n.translate('split.owner.unknown')),
                                subtitle: Text(l10n.translate('split.owner.primary')),
                                trailing: Chip(label: Text(l10n.translate('sharing.role.owner')), backgroundColor: AppColors.primary.withValues(alpha: 0.1)),
                             ),
                           ),
                          if (_accessGrants.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(l10n.translate('sharing.empty.subtitle'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                            )
                          else
                            ..._accessGrants.map((grant) => Card(
                                  child: ListTile(
                                    leading: Icon(
                                      grant.role == 'editor' ? Icons.mode_edit_outline : Icons.visibility_outlined,
                                      color: grant.role == 'editor' ? AppColors.primary : Colors.blueGrey,
                                    ),
                                      title: Text(_accessGrantLabels[grant.id] ?? grant.principal),
                                    subtitle: Text(_formatGrantSubtitle(grant)),
                                     trailing: PopupMenuButton<String>(
                                       tooltip: _canEditGroup ? l10n.translate('sharing.roles.label') : l10n.translate('sharing.accessDenied'),
                                       enabled: _canEditGroup,
                                       onSelected: _canEditGroup ? (value) => _handleGrantAction(grant, value) : null,
                                      itemBuilder: (context) => [
                                         PopupMenuItem(value: 'role_viewer', child: Text(l10n.translate('share.roles.makeViewer'))),
                                         PopupMenuItem(value: 'role_editor', child: Text(l10n.translate('share.roles.makeEditor'))),
                                         if (grant.status != 'accepted') PopupMenuItem(value: 'mark_accept', child: Text('Accept')),
                                         if (grant.status == 'accepted') PopupMenuItem(value: 'mark_pending', child: Text('Pending')),
                                        const PopupMenuDivider(),
                                         PopupMenuItem(value: 'revoke', child: Text(l10n.translate('share.roles.revoke'))),
                                      ],
                                    ),
                                  ),
                                )),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.share_outlined),
                            label: Text(l10n.translate('split.inviteByEmail')),
                            onPressed: _canEditGroup ? () => _showInviteDialog() : null,
                          ),
                          const SizedBox(height: 16),
                          Text(l10n.translate('split.expenses'), style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          ..._expenses.map((e) {
                            final payer = _participants.firstWhere((p) => p.id == e.paidBy);
                            return Card(
                              child: ListTile(
                                leading: Icon(Icons.receipt, color: AppColors.primary),
                                title: Text(e.description ?? l10n.translate('split.expense.default')),
                                subtitle: Text(l10n.translate('split.expense.paidBy', params: {'name': payer.name})),
                                trailing: Text(
                                  formatCurrencyLocalized(context, e.amount, currency: 'SEK', decimalDigits: 0),
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.add),
                            label: Text(l10n.translate('split.addExpense')),
                            onPressed: _canEditGroup ? () => _showAddExpenseDialog() : null,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.calculate),
                            label: Text(l10n.translate('split.generateSettlements')),
                            onPressed: _canEditGroup ? () => _generateSettlements() : null,
                          ),
                          if (_settlements.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(l10n.translate('split.settlements'), style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            ..._settlements.map(_buildSettlementCard),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.people, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(context.l10n.translate('split.empty.title'), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(context.l10n.translate('split.empty.subtitle'), style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  void _showAddGroupDialog() {
    final titleController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('split.new.title')),
        content: TextField(controller: titleController, decoration: InputDecoration(labelText: context.l10n.translate('split.new.name'))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('split.new.cancel'))),
          ElevatedButton(onPressed: () async {
            if (titleController.text.isEmpty) return;
            final group = SplitGroup(id: _uuid.v4(), title: titleController.text, creatorId: widget.user.id, createdAt: DateTime.now());
            await SplitService.createSplitGroup(group);
            if (context.mounted) {
              Navigator.of(context).pop();
              _loadGroups();
            }
          }, child: Text(context.l10n.translate('split.new.create'))),
        ],
      ),
    );
  }

  void _showAddParticipantDialog() {
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('split.addParticipant')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: InputDecoration(labelText: context.l10n.translate('split.new.name'))),
            const SizedBox(height: 16),
            TextField(controller: contactController, decoration: const InputDecoration(labelText: 'Kontakt (email/telefon)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('common.cancel'))),
          ElevatedButton(onPressed: () async {
            if (nameController.text.isEmpty) return;
            final p = Participant(id: _uuid.v4(), splitGroupId: _selectedGroup!.id, name: nameController.text, contact: contactController.text);
            await SplitService.createParticipant(p);
            if (context.mounted) {
              Navigator.of(context).pop();
              _loadGroupDetails();
            }
          }, child: Text(context.l10n.translate('common.actions.add'))),
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
    if (_participants.isEmpty) return;
    final descController = TextEditingController();
    final amountController = TextEditingController();
    String? paidBy = _participants.first.id;
    List<String> sharedWith = _participants.map((p) => p.id).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.translate('split.expense.add.title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: descController, decoration: InputDecoration(labelText: context.l10n.translate('split.expense.add.description'))),
                const SizedBox(height: 16),
                TextField(controller: amountController, decoration: InputDecoration(labelText: context.l10n.translate('split.expense.add.amount')), keyboardType: TextInputType.number),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: paidBy,
                  decoration: InputDecoration(labelText: context.l10n.translate('split.expense.add.paidBy')),
                  items: _participants.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setDialogState(() => paidBy = v),
                ),
                const SizedBox(height: 16),
                Text(context.l10n.translate('split.expense.add.sharedBy'), style: Theme.of(context).textTheme.labelLarge),
                ..._participants.map((p) => CheckboxListTile(
                  title: Text(p.name),
                  value: sharedWith.contains(p.id),
                  onChanged: (v) => setDialogState(() {
                    if (v == true) {
                      sharedWith.add(p.id);
                    } else {
                      sharedWith.remove(p.id);
                    }
                  }),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('common.cancel'))),
            ElevatedButton(onPressed: () async {
              if (amountController.text.isEmpty || paidBy == null || sharedWith.isEmpty) return;
              final expense = Expense(id: _uuid.v4(), splitGroupId: _selectedGroup!.id, paidBy: paidBy!, description: descController.text, amount: double.parse(amountController.text), sharedWith: sharedWith, createdAt: DateTime.now());
              await SplitService.createExpense(expense);
              if (context.mounted) {
                Navigator.of(context).pop();
                _loadGroupDetails();
              }
            }, child: Text(context.l10n.translate('split.expense.add.add'))),
          ],
        ),
      ),
    );
  }

  Future<void> _generateSettlements() async {
    final settlements = await SplitService.generateSettlements(_selectedGroup!.id);
    if (!mounted) return;
    await _loadGroupDetails();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.translate('split.settlement.title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: settlements.map((s) {
              final payer = _participants.firstWhere((p) => p.id == s.payerId);
              final receiver = _participants.firstWhere((p) => p.id == s.receiverId);
              return ListTile(
                title: Text(context.l10n.translate('split.settlement.pay', params: {'payer': payer.name, 'receiver': receiver.name})),
                trailing: Text(formatCurrencyLocalized(context, s.amount, currency: 'SEK', decimalDigits: 0), style: const TextStyle(fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ),
        ),
        actions: [
          ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.translate('common.ok'))),
        ],
      ),
    );
  }
}
