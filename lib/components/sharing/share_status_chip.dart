import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../services.dart';

class ShareStatusChip extends StatefulWidget {
  const ShareStatusChip({
    super.key,
    required this.resourceType,
    required this.resourceId,
  });

  final String resourceType;
  final String resourceId;

  @override
  State<ShareStatusChip> createState() => _ShareStatusChipState();
}

class _ShareStatusChipState extends State<ShareStatusChip> {
  late Future<int> _futureCount;

  @override
  void initState() {
    super.initState();
    _futureCount = _loadCount();
  }

  Future<int> _loadCount() async {
    final grants = await SharingService.listGrants(
      resourceType: widget.resourceType,
      resourceId: widget.resourceId,
    );
    return grants.where((g) => g.status == 'active').length;
  }

  @override
  void didUpdateWidget(covariant ShareStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceId != widget.resourceId || oldWidget.resourceType != widget.resourceType) {
      _futureCount = _loadCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<int>(
      future: _futureCount,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final count = snapshot.data ?? 0;
        if (count <= 0) {
          return const SizedBox.shrink();
        }
        return Chip(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          avatar: const Icon(Icons.people_alt, size: 18),
          label: Text(l10n.translate('common.sharing.sharedWith', params: {'count': count})),
        );
      },
    );
  }
}