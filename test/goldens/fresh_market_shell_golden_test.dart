import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

void main() {
  testWidgets('approved Fresh Market phone preview', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    const summary = SyncSummary(
      pending: 2,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 8,
      availability: SyncAvailability.offline,
      isSynchronizing: false,
    );
    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const Key('phone-shell')),
      matchesGoldenFile('providentia_fresh_market_phone.png'),
    );
  });
}
