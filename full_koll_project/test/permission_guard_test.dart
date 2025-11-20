import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:full_koll/components/sharing/permission_guard.dart';
import 'package:full_koll/models.dart';

void main() {
  final stubUser = User(
    id: 'u1',
    email: 'test@example.com',
    createdAt: DateTime.now(),
    lastLoginAt: DateTime.now(),
    reminderDefaults: ReminderDefaults(),
    notificationPrefs: const NotificationPrefs(),
  );

  testWidgets('PermissionGuard renders builder when role sufficient', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PermissionGuard(
          user: stubUser,
          resourceType: 'receipt',
          resourceId: 'r1',
          requiredRole: ShareRoles.viewer,
          loadOverride: () async => const ShareAccess(effectiveRole: ShareRoles.editor),
          builder: (context, access) => Text('allowed-${access.effectiveRole}'),
          fallback: const Text('denied'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('allowed'), findsOneWidget);
    expect(find.text('denied'), findsNothing);
  });

  testWidgets('PermissionGuard renders fallback when role insufficient', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PermissionGuard(
          user: stubUser,
          resourceType: 'receipt',
          resourceId: 'r1',
          requiredRole: ShareRoles.editor,
          loadOverride: () async => const ShareAccess(effectiveRole: ShareRoles.viewer),
          builder: (context, access) => const Text('should-not-render'),
          fallback: const Text('denied'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('denied'), findsOneWidget);
    expect(find.text('should-not-render'), findsNothing);
  });
}