import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/data_governance/application/data_governance_service.dart';
import 'package:providentia/features/data_governance/domain/data_governance_models.dart';
import 'package:providentia/features/homes/domain/home_models.dart';

void main() {
  test('capabilities are derived fail-closed from effective permissions', () {
    final signedOut = DataGovernanceCapabilities.fromEffectivePermissions(
      authenticated: false,
      effectiveHomePermissions: HomePermissions.owner,
    );
    expect(signedOut.allowed, isEmpty);

    final accountOnly = DataGovernanceCapabilities.fromEffectivePermissions(
      authenticated: true,
      effectiveHomePermissions: const <String>{},
    );
    expect(accountOnly.allows(DataGovernanceCapability.accountExport), isTrue);
    expect(accountOnly.allows(DataGovernanceCapability.homeExport), isFalse);
    expect(
      accountOnly.allows(DataGovernanceCapability.homeRequestsRead),
      isFalse,
    );

    final export = DataGovernanceCapabilities.fromEffectivePermissions(
      authenticated: true,
      effectiveHomePermissions: const <String>{HomePermissions.dataExport},
    );
    expect(export.allows(DataGovernanceCapability.homeExport), isTrue);
    expect(export.allows(DataGovernanceCapability.homeRequestsRead), isTrue);
    expect(export.allows(DataGovernanceCapability.cancelHomeRequest), isTrue);
    expect(export.allows(DataGovernanceCapability.homeErasure), isFalse);

    final erase = DataGovernanceCapabilities.fromEffectivePermissions(
      authenticated: true,
      effectiveHomePermissions: const <String>{HomePermissions.dataErasure},
    );
    expect(erase.allows(DataGovernanceCapability.homeErasure), isTrue);
    expect(erase.allows(DataGovernanceCapability.homeExport), isFalse);
  });

  test('only an exact explicit phrase creates erasure confirmation', () {
    expect(ErasureConfirmation.tryCreate('ERASE'), isNotNull);
    for (final value in <String>['erase', ' ERASE', 'ERASE ', 'DELETE', '']) {
      expect(ErasureConfirmation.tryCreate(value), isNull, reason: value);
    }
  });

  test(
    'service gates commands and passes typed erasure confirmation',
    () async {
      final repository = _RecordingRepository();
      final service = DataGovernanceService(
        repository: repository,
        capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
          authenticated: true,
          effectiveHomePermissions: const <String>{
            HomePermissions.dataExport,
            HomePermissions.dataErasure,
          },
        ),
        activeHomeId: _homeId,
      );
      final confirmation = ErasureConfirmation.tryCreate('ERASE')!;

      await service.requestAccountExport();
      await service.requestAccountErasure(confirmation: confirmation);
      await service.requestHomeExport();
      await service.requestHomeErasure(confirmation: confirmation);
      await service.listAccountRequests();
      await service.listHomeRequests();
      await service.cancel(_request(scope: DataGovernanceScope.home));

      expect(repository.calls, <String>[
        'account-export',
        'account-erasure',
        'home-export:$_homeId',
        'home-erasure:$_homeId',
        'account-list',
        'home-list:$_homeId',
        'cancel:$_requestId:3',
      ]);
    },
  );

  test(
    'denied and cross-home commands fail before repository access',
    () async {
      final repository = _RecordingRepository();
      final denied = DataGovernanceService(
        repository: repository,
        capabilities: DataGovernanceCapabilities.denied,
        activeHomeId: _homeId,
      );
      await expectLater(
        denied.requestAccountExport(),
        throwsA(isA<DataGovernanceCapabilityException>()),
      );

      final allowed = DataGovernanceService(
        repository: repository,
        capabilities: DataGovernanceCapabilities.fromEffectivePermissions(
          authenticated: true,
          effectiveHomePermissions: const <String>{HomePermissions.dataExport},
        ),
        activeHomeId: _homeId,
      );
      await expectLater(
        allowed.cancel(
          _request(scope: DataGovernanceScope.home, homeId: _otherHomeId),
        ),
        throwsA(isA<DataGovernanceCapabilityException>()),
      );
      await expectLater(
        allowed.cancel(
          _request(
            scope: DataGovernanceScope.home,
            status: DataGovernanceRequestStatus.completed,
          ),
        ),
        throwsA(isA<DataGovernanceCapabilityException>()),
      );
      await expectLater(
        allowed.cancel(
          _request(
            scope: DataGovernanceScope.home,
            status: DataGovernanceRequestStatus.processing,
          ),
        ),
        throwsA(isA<DataGovernanceCapabilityException>()),
      );
      expect(repository.calls, isEmpty);
    },
  );
}

DataGovernanceRequest _request({
  required DataGovernanceScope scope,
  String homeId = _homeId,
  DataGovernanceRequestStatus status = DataGovernanceRequestStatus.queued,
}) => DataGovernanceRequest(
  id: _requestId,
  kind: scope == DataGovernanceScope.home
      ? DataGovernanceRequestKind.homeExport
      : DataGovernanceRequestKind.accountExport,
  scope: scope,
  status: status,
  revision: 3,
  retainedDataDisclosure: const <RetainedDataDisclosure>[],
  homeId: scope == DataGovernanceScope.home ? homeId : null,
);

final class _RecordingRepository implements DataGovernanceRepository {
  final List<String> calls = <String>[];

  @override
  Future<void> cancelRequest({
    required String requestId,
    required int expectedRevision,
  }) async {
    calls.add('cancel:$requestId:$expectedRevision');
  }

  @override
  Future<List<DataGovernanceRequest>> listAccountRequests() async {
    calls.add('account-list');
    return <DataGovernanceRequest>[
      _request(scope: DataGovernanceScope.account),
    ];
  }

  @override
  Future<List<DataGovernanceRequest>> listHomeRequests({
    required String homeId,
  }) async {
    calls.add('home-list:$homeId');
    return <DataGovernanceRequest>[_request(scope: DataGovernanceScope.home)];
  }

  @override
  Future<DataGovernanceRequest> requestAccountErasure() async {
    calls.add('account-erasure');
    return _request(scope: DataGovernanceScope.account);
  }

  @override
  Future<DataGovernanceRequest> requestAccountExport() async {
    calls.add('account-export');
    return _request(scope: DataGovernanceScope.account);
  }

  @override
  Future<DataGovernanceRequest> requestHomeErasure({
    required String homeId,
  }) async {
    calls.add('home-erasure:$homeId');
    return _request(scope: DataGovernanceScope.home);
  }

  @override
  Future<DataGovernanceRequest> requestHomeExport({
    required String homeId,
  }) async {
    calls.add('home-export:$homeId');
    return _request(scope: DataGovernanceScope.home);
  }
}

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _otherHomeId = '01912345-6789-7abc-8def-1123456789ab';
const String _requestId = '01912345-6789-7abc-8def-2123456789ab';
