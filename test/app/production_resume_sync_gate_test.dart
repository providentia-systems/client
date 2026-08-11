import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';

void main() {
  test(
    'pause then resume pushes a queued operation and pulls exactly once',
    () async {
      var online = true;
      var queuedOperations = 0;
      var pushes = 0;
      var pulls = 0;
      var refreshes = 0;
      final gate = ProductionResumeSyncGate(
        refresh: () async {
          refreshes++;
          if (!online) return;
          if (queuedOperations > 0) {
            pushes++;
            queuedOperations = 0;
          }
          pulls++;
        },
      );

      // A lifecycle callback before the connected workspace finishes its
      // authorized bootstrap is ignored.
      gate.resume();
      await gate.settle();
      expect(refreshes, 0);

      gate.markReady();
      queuedOperations = 1; // mutation committed while the app is paused
      gate.resume();
      await gate.settle();

      expect(refreshes, 1);
      expect(pushes, 1);
      expect(pulls, 1);
      expect(queuedOperations, 0);
      online = false;
      gate.dispose();
    },
  );

  test('rapid duplicate resumes coalesce while refresh is running', () async {
    final release = Completer<void>();
    var refreshes = 0;
    final gate = ProductionResumeSyncGate(
      refresh: () async {
        refreshes++;
        await release.future;
      },
    )..markReady();

    gate.resume();
    gate.resume();
    gate.resume();
    expect(gate.isRunning, isTrue);
    expect(refreshes, 1);

    release.complete();
    await gate.settle();
    expect(gate.isRunning, isFalse);
    expect(refreshes, 1);
    gate.dispose();
  });

  test('revoked and disposed workspaces never refresh private data', () async {
    var privateDataReads = 0;
    final revoked = ProductionResumeSyncGate(
      refresh: () async => privateDataReads++,
    )..markReady();
    revoked.markRevoked();
    revoked.resume();
    await revoked.settle();

    final disposed = ProductionResumeSyncGate(
      refresh: () async => privateDataReads++,
    )..markReady();
    disposed.dispose();
    disposed.resume();
    await disposed.settle();

    expect(privateDataReads, 0);
    revoked.dispose();
  });
}
