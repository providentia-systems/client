import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_controller.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_page.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

void main() {
  testWidgets('permission-derived capabilities hide denied home actions', (
    tester,
  ) async {
    final repository = _PageRepository();
    final controller = _controller(
      repository,
      permissions: const <String>{HomePermissions.dataExport},
    );

    await tester.pumpWidget(
      MaterialApp(home: DataGovernancePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('account-export')), findsOneWidget);
    expect(find.byKey(const Key('account-erase')), findsOneWidget);
    expect(find.byKey(const Key('selected-home-export')), findsOneWidget);
    expect(find.byKey(const Key('selected-home-erase')), findsNothing);
    expect(repository.calls, <String>['account-list', 'home-list']);
  });

  testWidgets('erasure remains disabled until ERASE is entered exactly', (
    tester,
  ) async {
    final repository = _PageRepository();
    final controller = _controller(
      repository,
      permissions: const <String>{HomePermissions.dataErasure},
    );
    await tester.pumpWidget(
      MaterialApp(home: DataGovernancePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selected-home-erase')));
    await tester.pumpAndSettle();
    FilledButton submit = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-erasure')),
    );
    expect(submit.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('erasure-confirmation-input')),
      'erase',
    );
    await tester.pump();
    submit = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-erasure')),
    );
    expect(submit.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('erasure-confirmation-input')),
      'ERASE',
    );
    await tester.pump();
    submit = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-erasure')),
    );
    expect(submit.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('confirm-erasure')));
    await tester.pumpAndSettle();

    expect(repository.calls, contains('home-erasure:$_homeId'));
    expect(find.text('Your request has been queued.'), findsOneWidget);
  });

  testWidgets('raw failures never reach rendered UI', (tester) async {
    const privateDetail =
        'PRIVATE worker stack, export storage path, and household fact';
    final repository = _PageRepository(listFailure: Exception(privateDetail));
    final controller = _controller(repository, permissions: const <String>{});

    await tester.pumpWidget(
      MaterialApp(home: DataGovernancePage(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Data requests are temporarily unavailable.'),
      findsOneWidget,
    );
    expect(find.textContaining(privateDetail), findsNothing);
  });

  test(
    'late governance completion cannot notify after controller disposal',
    () async {
      final accountList = Completer<List<DataGovernanceRequest>>();
      final repository = _PageRepository(accountList: accountList);
      final controller = _controller(repository, permissions: const <String>{});
      var notifications = 0;
      controller.addListener(() => notifications++);

      final pending = controller.load();
      expect(notifications, 1);
      controller.dispose();
      accountList.complete(const <DataGovernanceRequest>[]);
      await pending;

      expect(notifications, 1);
      expect(controller.accountRequests, isEmpty);
    },
  );
}

DataGovernanceController _controller(
  DataGovernanceRepository repository, {
  required Set<String> permissions,
}) => DataGovernanceController(
  DataGovernanceService(
    repository: repository,
    capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
      authenticated: true,
      effectiveHomePermissions: permissions,
    ),
    activeHomeId: _homeId,
  ),
);

final class _PageRepository implements DataGovernanceRepository {
  _PageRepository({this.listFailure, this.accountList});

  final Object? listFailure;
  final Completer<List<DataGovernanceRequest>>? accountList;
  final List<String> calls = <String>[];

  @override
  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  }) async {
    calls.add('cancel');
  }

  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() async {
    calls.add('account-list');
    if (listFailure case final Object error) {
      throw error;
    }
    if (accountList case final pending?) return pending.future;
    return const <DataGovernanceRequest>[];
  }

  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  }) async {
    calls.add('home-list');
    return const <DataGovernanceRequest>[];
  }

  @override
  Future<DataGovernanceRequest> requestAccountErasure() async {
    calls.add('account-erasure');
    return _request(
      kind: DataGovernanceRequestKind.accountErasure,
      scope: DataGovernanceScope.account,
    );
  }

  @override
  Future<DataGovernanceRequest> requestAccountExport() async {
    calls.add('account-export');
    return _request(
      kind: DataGovernanceRequestKind.accountExport,
      scope: DataGovernanceScope.account,
    );
  }

  @override
  Future<DataGovernanceRequest> requestHomeErasure({
    required String homeId,
  }) async {
    calls.add('home-erasure:$homeId');
    return _request(
      kind: DataGovernanceRequestKind.homeErasure,
      scope: DataGovernanceScope.home,
    );
  }

  @override
  Future<DataGovernanceRequest> requestHomeExport({
    required String homeId,
  }) async {
    calls.add('home-export:$homeId');
    return _request(
      kind: DataGovernanceRequestKind.homeExport,
      scope: DataGovernanceScope.home,
    );
  }
}

DataGovernanceRequest _request({
  required DataGovernanceRequestKind kind,
  required DataGovernanceScope scope,
}) => DataGovernanceRequest(
  id: _requestId,
  kind: kind,
  scope: scope,
  status: DataGovernanceRequestStatus.queued,
  revision: 1,
  retainedDataDisclosure: const <RetainedDataDisclosure>[],
  homeId: scope == DataGovernanceScope.home ? _homeId : null,
);

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _requestId = '01912345-6789-7abc-8def-1123456789ab';
