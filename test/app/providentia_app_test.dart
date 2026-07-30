import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/app_controller.dart';
import 'package:providentia/app/providentia_app.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

void main() {
  testWidgets('Fresh Market shell identifies the product and phase boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview()),
    );

    expect(find.text('Providentia'), findsOneWidget);
    expect(find.text('Your pantry, ready'), findsOneWidget);
    expect(find.textContaining('Prototype shell:'), findsOneWidget);
  });

  for (final viewport in <(String, Size, Key)>[
    ('phone', const Size(390, 844), const Key('phone-shell')),
    ('tablet', const Size(900, 1000), const Key('tablet-shell')),
    ('desktop', const Size(1440, 1000), const Key('desktop-shell')),
  ]) {
    testWidgets('${viewport.$1} uses its adaptive navigation', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.$2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProvidentiaApp(controller: AppController.preview()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(viewport.$3), findsOneWidget);
      switch (viewport.$1) {
        case 'phone':
          expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
          break;
        case 'tablet':
          expect(find.byKey(const Key('navigation-rail')), findsOneWidget);
          break;
        case 'desktop':
          expect(find.byKey(const Key('navigation-sidebar')), findsOneWidget);
          break;
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('offline pending state is explicit and has manual retry', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 2,
      syncing: 0,
      retryWaiting: 1,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 4,
      availability: SyncAvailability.offline,
      isSynchronizing: false,
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Saved on this device — waiting to sync'), findsOneWidget);
    expect(find.text('3 local changes waiting.'), findsOneWidget);
    expect(find.byKey(const Key('manual-sync')), findsOneWidget);
  });

  testWidgets('membership loss is distinct from expired authentication', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.authorizationDenied,
      isSynchronizing: false,
      lastSafeError: 'Home membership no longer permits synchronization.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Access to this home changed'), findsOneWidget);
    expect(find.textContaining('membership'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsNothing);
  });

  testWidgets('a pull failure never presents the client as up to date', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 0,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.temporarilyUnavailable,
      isSynchronizing: false,
      lastSafeError: 'Synchronization was interrupted. Try again safely.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Sync paused'), findsOneWidget);
    expect(find.text('Up to date'), findsNothing);
  });

  testWidgets('blocked validation never presents the client as up to date', (
    tester,
  ) async {
    const summary = SyncSummary(
      pending: 0,
      syncing: 0,
      retryWaiting: 0,
      blockedConflicts: 0,
      blockedValidation: 1,
      blockedAuthorization: 0,
      acknowledged: 0,
      availability: SyncAvailability.online,
      isSynchronizing: false,
      lastSafeError: 'Correct the value before retrying.',
    );

    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview(summary: summary)),
    );

    expect(find.text('Review a change before syncing'), findsOneWidget);
    expect(find.text('Up to date'), findsNothing);
  });

  testWidgets('large text and reduced motion remain usable', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(semantics.dispose);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(1.8),
          disableAnimations: true,
        ),
        child: ProvidentiaApp(controller: AppController.preview()),
      ),
    );
    await tester.pump();

    expect(find.text('Your pantry, ready'), findsOneWidget);
    final brandMark = find.byKey(const Key('brand-mark-semantics'));
    expect(brandMark, findsOneWidget);
    expect(tester.getSemantics(brandMark).label, 'Providentia');
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard traversal reaches primary interactive controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProvidentiaApp(controller: AppController.preview()),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus, isNotNull);
  });
}
