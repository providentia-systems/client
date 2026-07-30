import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';

void main() {
  test(
    'failed authorization never records a successful synchronization',
    () async {
      final synchronization = _FakeSynchronization(
        outcome: const SyncRunOutcome(
          status: SyncRunStatus.authorizationFailure,
          safeMessage: 'Access to this home was removed.',
        ),
      );
      final controller = AppController(
        synchronization: synchronization,
        activeHomeId: '0198a0b1-c2d3-7e4f-8123-456789abcdef',
      );
      addTearDown(() async {
        controller.dispose();
        await synchronization.close();
      });

      await controller.start();

      expect(
        controller.syncSummary.availability,
        SyncAvailability.authorizationDenied,
      );
      expect(controller.syncSummary.lastSuccessfulSync, isNull);
      expect(controller.syncSummary.lastSafeError, contains('removed'));
    },
  );

  test('summary subscription is scoped to the selected home', () async {
    final synchronization = _FakeSynchronization();
    final controller = AppController(
      synchronization: synchronization,
      activeHomeId: 'home-1',
    );
    addTearDown(() async {
      controller.dispose();
      await synchronization.close();
    });

    await controller.start();
    await controller.start();
    synchronization.summaries.add(
      const SyncSummary(
        pending: 2,
        syncing: 0,
        retryWaiting: 0,
        blockedConflicts: 0,
        blockedValidation: 0,
        blockedAuthorization: 0,
        acknowledged: 0,
        availability: SyncAvailability.checking,
        isSynchronizing: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(synchronization.watchedHomes, <String>['home-1']);
    expect(synchronization.synchronizeCalls, 1);
    expect(controller.syncSummary.pending, 2);
  });

  test('overlapping refresh requests are coalesced', () async {
    final gate = Completer<void>();
    final synchronization = _FakeSynchronization(connectivityGate: gate);
    final controller = AppController(
      synchronization: synchronization,
      activeHomeId: 'home-1',
    );
    addTearDown(() async {
      controller.dispose();
      await synchronization.close();
    });

    final first = controller.refresh();
    final second = controller.refresh();
    gate.complete();
    await Future.wait(<Future<void>>[first, second]);

    expect(synchronization.synchronizeCalls, 1);
    expect(synchronization.connectivityCalls, 2);
  });

  test('successful synchronization uses the injected UTC clock', () async {
    final synchronization = _FakeSynchronization();
    final completedAt = DateTime.utc(2026, 7, 30, 16, 45);
    final controller = AppController(
      synchronization: synchronization,
      activeHomeId: 'home-1',
      clock: () => completedAt,
    );
    addTearDown(() async {
      controller.dispose();
      await synchronization.close();
    });

    await controller.refresh();

    expect(controller.syncSummary.lastSuccessfulSync, completedAt);
    expect(controller.syncSummary.availability, SyncAvailability.online);
    expect(controller.syncSummary.isSynchronizing, isFalse);
  });

  test('section changes notify only when the value changes', () {
    final controller = AppController.preview();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.selectSection(AppSection.home);
    controller.selectSection(AppSection.stock);
    controller.selectSection(AppSection.stock);

    expect(controller.section, AppSection.stock);
    expect(notifications, 1);
  });
}

final class _FakeSynchronization implements AppSynchronization {
  _FakeSynchronization({
    this.outcome = const SyncRunOutcome(status: SyncRunStatus.completed),
    this.connectivityGate,
  });

  final SyncRunOutcome outcome;
  final ConnectivityResult connectivityResult =
      const ConnectivityResult.online();
  final Completer<void>? connectivityGate;
  final StreamController<SyncSummary> summaries =
      StreamController<SyncSummary>.broadcast();
  final List<String> watchedHomes = <String>[];
  int connectivityCalls = 0;
  int synchronizeCalls = 0;

  @override
  Future<ConnectivityResult> connectivity() async {
    connectivityCalls++;
    await connectivityGate?.future;
    return connectivityResult;
  }

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async {
    synchronizeCalls++;
    return outcome;
  }

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    watchedHomes.add(homeId);
    return summaries.stream;
  }

  Future<void> close() => summaries.close();
}
