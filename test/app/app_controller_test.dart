import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_coordinator.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  test(
    'failed authorization never records a successful synchronization',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final controller = AppController(
        coordinator: SyncCoordinator(
          local: DriftLocalSyncRepository(database),
          remote: const _DeniedGateway(),
          connectivity: const _OnlineProbe(),
        ),
        activeHomeId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
      );
      addTearDown(controller.dispose);

      await controller.start();

      expect(
        controller.syncSummary.availability,
        SyncAvailability.authorizationDenied,
      );
      expect(controller.syncSummary.lastSuccessfulSync, isNull);
      expect(controller.syncSummary.lastSafeError, contains('removed'));
    },
  );
}

final class _DeniedGateway implements SyncRemoteGateway {
  const _DeniedGateway();

  @override
  Future<PullPage> bootstrap({required String homeId}) {
    throw const AuthorizationSyncException('Access to this home was removed.');
  }

  @override
  Future<PullPage> pull({required String homeId, String? afterCursor}) {
    throw UnimplementedError();
  }

  @override
  Future<PushResponse> push({
    required String homeId,
    required String? lastPulledCursor,
    required List<PendingClientOperation> operations,
  }) {
    throw UnimplementedError();
  }
}

final class _OnlineProbe implements ConnectivityProbe {
  const _OnlineProbe();

  @override
  Future<ConnectivityResult> check() async {
    return const ConnectivityResult.online();
  }
}
