import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services.dart';

typedef PermissionBuilder = Widget Function(BuildContext context, ShareAccess access);

class PermissionGuard extends StatefulWidget {
  final User user;
  final String resourceType;
  final String resourceId;
  final String requiredRole;
  final PermissionBuilder builder;
  final Widget? fallback;
  final String? ownerId;
  final Future<ShareAccess> Function()? loadOverride;

  const PermissionGuard({
    super.key,
    required this.user,
    required this.resourceType,
    required this.resourceId,
    required this.requiredRole,
    required this.builder,
    this.fallback,
    this.ownerId,
    this.loadOverride,
  });

  @override
  State<PermissionGuard> createState() => _PermissionGuardState();
}

class _PermissionGuardState extends State<PermissionGuard> {
  late Future<ShareAccess> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  @override
  void didUpdateWidget(covariant PermissionGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resourceId != widget.resourceId ||
        oldWidget.user.id != widget.user.id ||
        oldWidget.loadOverride != widget.loadOverride) {
      _future = _resolve();
    }
  }

  Future<ShareAccess> _loadAccess() => SharingService.getAccessForUser(
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        user: widget.user,
        ownerId: widget.ownerId,
      );

  Future<ShareAccess> _resolve() {
    if (widget.loadOverride != null) {
      return widget.loadOverride!();
    }
    return _loadAccess();
  }

  int _rank(String role) {
    switch (role) {
      case ShareRoles.owner:
        return 3;
      case ShareRoles.editor:
        return 2;
      case ShareRoles.viewer:
        return 1;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ShareAccess>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        final access = snapshot.data ?? const ShareAccess(effectiveRole: 'none');
        bool hasAccess;
        switch (widget.requiredRole) {
          case 'export':
            hasAccess = access.canExport;
            break;
          case 'share':
            hasAccess = access.canShare;
            break;
          case 'sensitive':
            // Conservative default: only owners may view sensitive data.
            hasAccess = access.isOwner;
            break;
          default:
            hasAccess = _rank(access.effectiveRole) >= _rank(widget.requiredRole);
            break;
        }

        if (!hasAccess) {
          return widget.fallback ?? const SizedBox.shrink();
        }

        return widget.builder(context, access);
      },
    );
  }
}