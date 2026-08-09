import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/administration/application/platform_administration_controller.dart';
import 'package:providentia/features/administration/domain/platform_administrator_models.dart';
import 'package:providentia/features/administration/presentation/platform_administrators_page.dart';

void main() {
  test(
    'controller loads, grants normalized email, and revision-revokes',
    () async {
      final transport = _FakePlatformAdministration();
      final controller = PlatformAdministrationController(transport);
      addTearDown(controller.dispose);

      await controller.load();
      await controller.grant(' NEXT@Example.com ');
      await controller.revoke(controller.snapshot.administrators.first);

      expect(transport.grantedEmails, <String>['next@example.com']);
      expect(transport.revokedRevisions, <int>[1]);
      expect(controller.snapshot.safeMessage, isNull);
      expect(controller.snapshot.loading, isFalse);
    },
  );

  test('controller rejects malformed email without transport', () async {
    final transport = _FakePlatformAdministration();
    final controller = PlatformAdministrationController(transport);
    addTearDown(controller.dispose);

    await controller.grant('not-an-email');

    expect(transport.grantedEmails, isEmpty);
    expect(controller.snapshot.safeMessage, contains('valid email'));
  });

  test('controller surfaces final-administrator conflict safely', () async {
    final transport = _FakePlatformAdministration(failRevoke: true);
    final controller = PlatformAdministrationController(transport);
    addTearDown(controller.dispose);
    await controller.load();

    await controller.revoke(controller.snapshot.administrators.single);

    expect(controller.snapshot.loading, isFalse);
    expect(controller.snapshot.safeMessage, contains('final active'));
    expect(controller.snapshot.administrators, hasLength(1));
  });

  test('unexpected transport failure cannot strand loading state', () async {
    final controller = PlatformAdministrationController(
      _UnexpectedPlatformAdministration(),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.snapshot.loading, isFalse);
    expect(controller.snapshot.safeMessage, contains('loaded safely'));
  });

  test(
    'auth loss clears privileged rows and defeats a late response',
    () async {
      final response = Completer<List<PlatformAdministrator>>();
      final controller = PlatformAdministrationController(
        _DeferredPlatformAdministration(response),
      );
      addTearDown(controller.dispose);
      final loading = controller.load();
      await Future<void>.delayed(Duration.zero);

      controller.clearSensitiveState();
      response.complete(<PlatformAdministrator>[
        PlatformAdministrator(
          id: 'late-administrator',
          email: 'late@example.com',
          status: PlatformAdministratorStatus.active,
          revision: 1,
          createdAt: DateTime.utc(2026, 8, 9),
        ),
      ]);
      await loading;

      expect(controller.snapshot.loading, isFalse);
      expect(controller.snapshot.administrators, isEmpty);
    },
  );

  test('self-revoke 403 clears rows and requests identity refresh', () async {
    var authorizationLosses = 0;
    final transport = _ForbiddenAfterSelfRevokeAdministration();
    final controller = PlatformAdministrationController(
      transport,
      onAuthorizationLost: () async {
        authorizationLosses++;
      },
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.revoke(controller.snapshot.administrators.first);
    await Future<void>.delayed(Duration.zero);

    expect(transport.revoked, isTrue);
    expect(authorizationLosses, 1);
    expect(controller.snapshot.loading, isFalse);
    expect(controller.snapshot.administrators, isEmpty);
    expect(controller.snapshot.safeMessage, isNull);
  });

  testWidgets(
    'administrator page grants, confirms revoke, and protects final active row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final transport = _FakePlatformAdministration()
        ..administrators.add(
          PlatformAdministrator(
            id: 'administrator-second-active',
            email: 'second@example.com',
            status: PlatformAdministratorStatus.active,
            revision: 2,
            createdAt: DateTime.utc(2026, 8, 2),
          ),
        );
      final controller = PlatformAdministrationController(transport);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: PlatformAdministratorsPage(controller: controller)),
      );
      await tester.pumpAndSettle();
      expect(find.text('admin@example.com'), findsOneWidget);
      expect(find.text('second@example.com'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('platform-administrator-email')),
        'NEXT@Example.com',
      );
      await tester.tap(find.byKey(const Key('grant-platform-administrator')));
      await tester.pumpAndSettle();
      expect(find.text('next@example.com'), findsOneWidget);

      await tester.tap(find.byTooltip('Revoke administrator').first);
      await tester.pumpAndSettle();
      expect(find.text('Revoke platform administrator?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(transport.revokedRevisions, isEmpty);

      await tester.tap(find.byTooltip('Revoke administrator').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
      await tester.pumpAndSettle();

      expect(transport.revokedRevisions, <int>[1]);
      expect(
        find.byTooltip('The final active administrator cannot be revoked'),
        findsOneWidget,
      );
    },
  );
}

final class _DeferredPlatformAdministration
    implements PlatformAdministrationPort {
  _DeferredPlatformAdministration(this.response);

  final Completer<List<PlatformAdministrator>> response;

  @override
  Future<List<PlatformAdministrator>> listAdministrators() => response.future;

  @override
  Future<PlatformAdministrator> grantAdministrator(String email) =>
      throw UnimplementedError();

  @override
  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  }) => throw UnimplementedError();
}

final class _ForbiddenAfterSelfRevokeAdministration
    implements PlatformAdministrationPort {
  var listCalls = 0;
  var revoked = false;

  final List<PlatformAdministrator> administrators = <PlatformAdministrator>[
    PlatformAdministrator(
      id: 'current-administrator',
      email: 'current@example.com',
      status: PlatformAdministratorStatus.active,
      revision: 1,
      createdAt: DateTime.utc(2026, 8, 1),
    ),
    PlatformAdministrator(
      id: 'remaining-administrator',
      email: 'remaining@example.com',
      status: PlatformAdministratorStatus.active,
      revision: 1,
      createdAt: DateTime.utc(2026, 8, 2),
    ),
  ];

  @override
  Future<List<PlatformAdministrator>> listAdministrators() async {
    listCalls++;
    if (listCalls > 1) {
      throw const PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.forbidden,
        safeMessage: 'Platform-administrator access is required.',
      );
    }
    return List<PlatformAdministrator>.of(administrators);
  }

  @override
  Future<PlatformAdministrator> grantAdministrator(String email) =>
      throw UnimplementedError();

  @override
  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  }) async {
    revoked = true;
    administrators.removeWhere((item) => item.id == administratorId);
  }
}

final class _UnexpectedPlatformAdministration
    implements PlatformAdministrationPort {
  @override
  Future<List<PlatformAdministrator>> listAdministrators() =>
      Future<List<PlatformAdministrator>>.error(Exception('unexpected'));

  @override
  Future<PlatformAdministrator> grantAdministrator(String email) =>
      Future<PlatformAdministrator>.error(Exception('unexpected'));

  @override
  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  }) => Future<void>.error(Exception('unexpected'));
}

final class _FakePlatformAdministration implements PlatformAdministrationPort {
  _FakePlatformAdministration({this.failRevoke = false});

  final bool failRevoke;
  final List<String> grantedEmails = <String>[];
  final List<int> revokedRevisions = <int>[];
  final List<PlatformAdministrator> administrators = <PlatformAdministrator>[
    PlatformAdministrator(
      id: 'administrator-one',
      email: 'admin@example.com',
      status: PlatformAdministratorStatus.active,
      revision: 1,
      createdAt: DateTime.utc(2026, 8, 1),
    ),
  ];

  @override
  Future<List<PlatformAdministrator>> listAdministrators() async =>
      List<PlatformAdministrator>.of(administrators);

  @override
  Future<PlatformAdministrator> grantAdministrator(String email) async {
    grantedEmails.add(email);
    final administrator = PlatformAdministrator(
      id: 'administrator-two',
      email: email,
      status: PlatformAdministratorStatus.pending,
      revision: 1,
      createdAt: DateTime.utc(2026, 8, 9),
    );
    administrators.add(administrator);
    return administrator;
  }

  @override
  Future<void> revokeAdministrator({
    required String administratorId,
    required int expectedRevision,
  }) async {
    if (failRevoke) {
      throw const PlatformAdministrationException(
        kind: PlatformAdministrationFailureKind.conflict,
        safeMessage:
            'The final active platform administrator cannot be revoked.',
      );
    }
    revokedRevisions.add(expectedRevision);
    administrators.removeWhere((item) => item.id == administratorId);
  }
}
