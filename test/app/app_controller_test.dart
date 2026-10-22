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

  test('overlapping refresh callers join and drain a follow-up pass', () async {
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

    expect(synchronization.synchronizeCalls, 2);
    expect(synchronization.connectivityCalls, 4);
  });

  test(
    'joined callers await network completion and work saved mid-run gets a pass',
    () async {
      final gate = Completer<void>();
      final synchronization = _FakeSynchronization(synchronizeGate: gate);
      final controller = AppController(
        synchronization: synchronization,
        activeHomeId: 'home-1',
      );
      addTearDown(() async {
        controller.dispose();
        await synchronization.close();
      });
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      var joinedCompleted = false;
      final joined = controller.refresh().then((_) => joinedCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(joinedCompleted, isFalse);
      expect(controller.syncSummary.isSynchronizing, isTrue);
      expect(synchronization.synchronizeCalls, 1);
      gate.complete();
      await Future.wait([first, joined]);
      expect(synchronization.synchronizeCalls, 2);
      expect(synchronization.maximumConcurrentRuns, 1);
      expect(joinedCompleted, isTrue);
      expect(controller.syncSummary.isSynchronizing, isFalse);
    },
  );

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

  test(
    'outbox updates retain refresh progress and the last refresh failure',
    () async {
      final gate = Completer<void>();
      final synchronization = _FakeSynchronization(
        connectivityGate: gate,
        outcome: const SyncRunOutcome(
          status: SyncRunStatus.retryableFailure,
          safeMessage: 'The catalog could not be refreshed.',
        ),
      );
      final controller = AppController(
        synchronization: synchronization,
        activeHomeId: 'home-1',
      );
      addTearDown(() async {
        controller.dispose();
        await synchronization.close();
      });
      final started = controller.start();
      synchronization.summaries.add(const SyncSummary.initial());
      await Future<void>.delayed(Duration.zero);
      expect(controller.syncSummary.isSynchronizing, isTrue);
      gate.complete();
      await started;
      synchronization.summaries.add(const SyncSummary.initial());
      await Future<void>.delayed(Duration.zero);
      expect(controller.syncSummary.isSynchronizing, isFalse);
      expect(controller.syncSummary.lastSafeError, contains('catalog'));
      expect(controller.syncSummary.lastSuccessfulSync, isNull);

      synchronization.outcome = const SyncRunOutcome(
        status: SyncRunStatus.completed,
      );
      await controller.refresh();
      expect(controller.syncSummary.lastSafeError, isNull);
      expect(controller.syncSummary.lastSuccessfulSync, isNotNull);
    },
  );

  test(
    'unexpected connectivity failure allows a later manual refresh',
    () async {
      final synchronization = _FakeSynchronization(
        connectivityFailure: const FormatException(
          'Invalid connectivity response',
        ),
      );
      final controller = AppController(
        synchronization: synchronization,
        activeHomeId: 'home-1',
      );
      addTearDown(() async {
        controller.dispose();
        await synchronization.close();
      });
      await controller.refresh();
      expect(controller.syncSummary.isSynchronizing, isFalse);
      expect(
        controller.syncSummary.availability,
        SyncAvailability.temporarilyUnavailable,
      );
      expect(controller.syncSummary.lastSafeError, contains('interrupted'));
      synchronization.connectivityFailure = null;
      await controller.refresh();
      expect(controller.syncSummary.lastSafeError, isNull);
      expect(controller.syncSummary.lastSuccessfulSync, isNotNull);
    },
  );

  test(
    'leaving a home during refresh does not notify a disposed controller',
    () async {
      final gate = Completer<void>();
      final synchronization = _FakeSynchronization(connectivityGate: gate);
      final controller = AppController(
        synchronization: synchronization,
        activeHomeId: 'home-1',
      );
      final refreshing = controller.refresh();
      controller.dispose();
      gate.complete();
      await refreshing;
      expect(synchronization.synchronizeCalls, 0);
      await synchronization.close();
    },
  );
}

final class _FakeSynchronization implements AppSynchronization {
  _FakeSynchronization({
    this.outcome = const SyncRunOutcome(status: SyncRunStatus.completed),
    this.connectivityGate,
    this.connectivityFailure,
    this.synchronizeGate,
  });

  SyncRunOutcome outcome;
  final ConnectivityResult connectivityResult =
      const ConnectivityResult.online();
  final Completer<void>? connectivityGate;
  Exception? connectivityFailure;
  final StreamController<SyncSummary> summaries =
      StreamController<SyncSummary>.broadcast();
  final List<String> watchedHomes = <String>[];
  int connectivityCalls = 0;
  int synchronizeCalls = 0;
  final Completer<void>? synchronizeGate;
  int _activeRuns = 0;
  int maximumConcurrentRuns = 0;

  @override
  Future<ConnectivityResult> connectivity() async {
    connectivityCalls++;
    await connectivityGate?.future;
    if (connectivityFailure case final Exception failure) throw failure;
    return connectivityResult;
  }

  @override
  Future<SyncRunOutcome> synchronize(String homeId) async {
    synchronizeCalls++;
    _activeRuns++;
    if (_activeRuns > maximumConcurrentRuns) {
      maximumConcurrentRuns = _activeRuns;
    }
    await synchronizeGate?.future;
    _activeRuns--;
    return outcome;
  }

  @override
  Stream<SyncSummary> watchSummary({required String homeId}) {
    watchedHomes.add(homeId);
    return summaries.stream;
  }

  Future<void> close() => summaries.close();
}
