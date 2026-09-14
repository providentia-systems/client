import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/data_governance/application/data_export_ports.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_export_artifact.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_controller.dart';
import 'package:providentia/features/data_governance/presentation/data_governance_page.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

void main() {
  for (final result in DataExportSaveResult.values) {
    testWidgets('actual export page requires explicit save and handles ${result.name}', (tester) async {
      final repository = _Repository();
      final saver = _Saver(result: result);
      final controller = DataGovernanceController(_service(repository), exportSaver: saver);
      await tester.binding.setSurfaceSize(const Size(1100, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(home: DataGovernancePage(controller: controller)));
      await tester.pumpAndSettle();
      final download = find.byKey(const Key('download-export-$_requestId'));
      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();
      expect(repository.retrievals, 1);
      expect(controller.notice, DataGovernanceNotice.exportReady);
      expect(controller.readyExportRequestId, _requestId);
      expect(saver.saves, 0);
      final artifact = repository.last!;
      final bytes = artifact.bytes;
      final save = find.byKey(const Key('save-data-export'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(saver.saves, 1);
      expect(controller.notice, switch (result) {
        DataExportSaveResult.saved => DataGovernanceNotice.exportSaved,
        DataExportSaveResult.handedToBrowser => DataGovernanceNotice.exportHandedToBrowser,
        DataExportSaveResult.cancelled => DataGovernanceNotice.exportDiscarded,
      });
      expect(controller.readyExportRequestId, isNull);
      expect(artifact.disposed, isTrue);
      expect(bytes.every((value) => value == 0), isTrue);
      expect(find.textContaining('synthetic-sensitive-payload'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final dispose in [false, true]) {
    test('late download after ${dispose ? 'disposal' : 'account switch'} cannot expose bytes', () async {
      final pending = Completer<DataExportArtifact>();
      final repository = _Repository(pending: pending);
      final saver = _Saver();
      final controller = DataGovernanceController(_service(repository), exportSaver: saver);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final download = controller.download(_request());
      await controller.download(_request());
      expect(repository.retrievals, 1);
      if (dispose) { controller.dispose(); } else { controller.clearSensitiveState(); }
      final previous = notifications;
      final artifact = _artifact();
      final bytes = artifact.bytes;
      pending.complete(artifact);
      await download;
      expect(controller.readyExportRequestId, isNull);
      expect(notifications, previous);
      expect(bytes.every((value) => value == 0), isTrue);
      expect(saver.clears, greaterThan(0));
      if (!dispose) { controller.dispose(); }
    });
  }
  test('discard and failing native save remove private memory and preserve safe notices', () async {
    final repository = _Repository();
    final saver = _Saver(error: StateError('synthetic-sensitive-payload /private/path'));
    final controller = DataGovernanceController(_service(repository), exportSaver: saver);
    addTearDown(controller.dispose);
    await controller.download(_request());
    final first = repository.last!;
    controller.discardExport();
    expect(first.disposed, isTrue);
    expect(controller.notice, DataGovernanceNotice.exportDiscarded);
    await controller.saveExport();
    expect(saver.saves, 0);
    await controller.download(_request());
    await controller.saveExport();
    expect(repository.last!.disposed, isTrue);
    expect(controller.status, DataGovernanceViewStatus.failure);
    expect(controller.notice, DataGovernanceNotice.unavailable);
  });
  test('unsupported platform fails closed without keeping downloaded content', () async {
    final repository = _Repository();
    final controller = DataGovernanceController(_service(repository));
    addTearDown(controller.dispose);
    await controller.download(_request());
    await controller.saveExport();
    expect(controller.notice, DataGovernanceNotice.unavailable);
    expect(repository.last!.disposed, isTrue);
  });
  testWidgets('artifact expiry clears a ready download before save', (tester) async {
    final repository = _Repository(lifetime: const Duration(milliseconds: 10));
    final controller = DataGovernanceController(_service(repository), exportSaver: _Saver());
    addTearDown(controller.dispose);
    await controller.download(_request());
    await tester.pump(const Duration(milliseconds: 20));
    expect(repository.last!.disposed, isTrue);
    expect(controller.readyExportRequestId, isNull);
    expect(controller.notice, DataGovernanceNotice.exportDiscarded);
  });
  for (final kind in DataGovernanceFailureKind.values) {
    test('download classifies ${kind.name} without raw details', () async {
      final controller = DataGovernanceController(_service(_Repository(error: DataGovernanceRepositoryException(kind))));
      addTearDown(controller.dispose);
      await controller.download(_request());
      expect(controller.status, DataGovernanceViewStatus.failure);
      expect(controller.notice.name, kind.name);
      expect(controller.readyExportRequestId, isNull);
    });
  }
  test('service rejects foreign home, erasure and invalidated session before retrieval', () {
    final repository = _Repository();
    final service = _service(repository);
    expect(() => service.retrieveExport(_request(homeId: _otherHome), isCurrent: () => true), throwsA(isA<DataGovernanceCapabilityException>()));
    expect(() => service.retrieveExport(_request(erasure: true), isCurrent: () => true), throwsA(isA<DataGovernanceCapabilityException>()));
    expect(() => service.retrieveExport(_request(), isCurrent: () => false), throwsA(isA<DataGovernanceCapabilityException>()));
    expect(repository.retrievals, 0);
  });
}

DataGovernanceService _service(_Repository repository) => DataGovernanceService(repository: repository, capabilities: DataGovernanceCapabilities.fromEffectivePermissions(authenticated: true, effectiveHomePermissions: const {HomePermissions.dataExport}), activeHomeId: _home);
DataGovernanceRequest _request({String? homeId, bool erasure = false}) => DataGovernanceRequest(id: _requestId, kind: erasure ? DataGovernanceRequestKind.accountErasure : homeId == null ? DataGovernanceRequestKind.accountExport : DataGovernanceRequestKind.homeExport, scope: homeId == null ? DataGovernanceScope.account : DataGovernanceScope.home, homeId: homeId, status: DataGovernanceRequestStatus.completed, revision: 7, downloadEligible: true, artifactExpiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)), retainedDataDisclosure: []);
DataExportArtifact _artifact({Duration lifetime = const Duration(hours: 1)}) => DataExportArtifact(requestId: _requestId, scope: DataGovernanceScope.account, expiresAt: DateTime.now().toUtc().add(lifetime), bytes: Uint8List.fromList('synthetic-sensitive-payload'.codeUnits));

final class _Repository implements DataGovernanceRepository, DataExportRepository {
  _Repository({this.pending, this.error, this.lifetime = const Duration(hours: 1)});
  final Completer<DataExportArtifact>? pending;
  final Object? error;
  final Duration lifetime;
  int retrievals = 0;
  DataExportArtifact? last;
  @override
  Future<DataExportArtifact> retrieveExport(DataGovernanceRequest request, {required bool Function() isCurrent}) async {
    retrievals++;
    expect(isCurrent(), isTrue);
    if (error case final Object error) { throw error; }
    if (pending case final pending?) { return pending.future; }
    return last = _artifact(lifetime: lifetime);
  }
  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() async => [_request()];
  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({required String homeId}) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('Unexpected mutation: ${invocation.memberName}');
}
final class _Saver implements DataExportSaver {
  _Saver({this.result = DataExportSaveResult.saved, this.error});
  final DataExportSaveResult result;
  final Object? error;
  int saves = 0;
  int clears = 0;
  @override
  Future<DataExportSaveResult> save(DataExportArtifact artifact) async {
    expect(artifact.bytes, isNotEmpty);
    saves++;
    if (error case final Object error) { throw error; }
    return result;
  }
  @override
  Future<void> clearTemporaryState() async { clears++; }
}
const _home = '11111111-1111-4111-8111-111111111111';
const _otherHome = '22222222-2222-4222-8222-222222222222';
const _requestId = '33333333-3333-4333-8333-333333333333';
