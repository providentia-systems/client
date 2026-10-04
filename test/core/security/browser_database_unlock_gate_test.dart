import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/security/browser_database_unlock_gate.dart';

void main() {
  late _Vault vault;
  Future<void> Function()? lock;
  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      BrowserDatabaseUnlockGate(
        vaultFactory: () => vault,
        builder: (_, session, callback) {
          lock = callback;
          return const MaterialApp(home: Text('Account email-code sign in'));
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, {bool confirm = false}) async {
    await tester.enterText(
      find.byKey(const Key('browser-local-passphrase')),
      'synthetic local passphrase',
    );
    if (confirm) {
      await tester.enterText(
        find.byKey(const Key('browser-local-passphrase-confirm')),
        'synthetic local passphrase',
      );
      await tester.tap(find.byType(CheckboxListTile));
    }
  }

  setUp(() {
    vault = _Vault();
    lock = null;
  });
  tearDown(() => vault.session.executor.close());

  testWidgets(
    'creation has separate sign-in explanation and irreversible warning',
    (tester) async {
      await show(tester);
      expect(find.text('Protect browser data'), findsOneWidget);
      expect(find.textContaining('usual email sign-in code'), findsOneWidget);
      expect(
        find.textContaining('An email sign-in code cannot recover it'),
        findsOneWidget,
      );
      await tester.tap(find.text('Protect local data'));
      await tester.pump();
      expect(find.textContaining('Use at least 16 characters'), findsOneWidget);
      expect(vault.unlocks, 0);
      await enter(tester, confirm: true);
      await tester.tap(find.text('Protect local data'));
      await tester.pumpAndSettle();
      expect(find.text('Account email-code sign in'), findsOneWidget);
      expect(vault.secret, 'synthetic local passphrase');
      expect(vault.unlocks, 1);
      vault.state = BrowserDatabaseState.unlock;
      await lock!();
      await tester.pumpAndSettle();
      expect(find.text('Unlock browser data'), findsOneWidget);
      expect(
        find.byKey(const Key('browser-local-passphrase-confirm')),
        findsNothing,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(vault.closes, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'existing vault rejects empty or wrong passphrase without resetting',
    (tester) async {
      vault.state = BrowserDatabaseState.unlock;
      vault.error = const BrowserDatabaseProtectionException('unlock_failed');
      await show(tester);
      await tester.tap(find.text('Unlock local data'));
      await tester.pump();
      expect(find.text('Enter your local-data passphrase.'), findsOneWidget);
      await enter(tester);
      await tester.tap(find.text('Unlock local data'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Saved data has not been reset.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      vault.error = null;
      await enter(tester);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Account email-code sign in'), findsOneWidget);
    },
  );

  testWidgets(
    'pending unlock disables repeated submit and clears secret controls',
    (tester) async {
      vault.state = BrowserDatabaseState.unlock;
      vault.pending = Completer<BrowserDatabaseSession>();
      await show(tester);
      await enter(tester);
      await tester.tap(find.text('Unlock local data'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(vault.unlocks, 1);
      vault.pending!.complete(vault.session);
      await tester.pumpAndSettle();
      expect(find.text('Account email-code sign in'), findsOneWidget);
    },
  );

  for (final entry in {
    'legacy_data_detected': 'previous trusted client version',
    'database_busy': 'Another tab',
    'unsupported_browser': 'over HTTPS',
    'storage_format_invalid': 'Do not clear browser storage',
  }.entries) {
    testWidgets(
      'preparation ${entry.key} explains safe recovery and supports retry',
      (tester) async {
        vault.prepareError = BrowserDatabaseProtectionException(entry.key);
        await show(tester);
        expect(find.textContaining(entry.value), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        vault.prepareError = null;
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Protect local data'), findsOneWidget);
      },
    );
  }

  for (final error in <Object>[
    const BrowserDatabaseProtectionException('passphrase_too_short'),
    StateError('synthetic failure'),
  ]) {
    testWidgets('safe unlock error ${error.runtimeType} stays locked', (
      tester,
    ) async {
      vault.state = BrowserDatabaseState.unlock;
      vault.error = error;
      await show(tester);
      await enter(tester);
      await tester.tap(find.text('Unlock local data'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browser-unlock-error')), findsOneWidget);
      expect(find.text('Account email-code sign in'), findsNothing);
    });
  }

  testWidgets('disposal during unlock closes a late session', (tester) async {
    vault.state = BrowserDatabaseState.unlock;
    vault.pending = Completer<BrowserDatabaseSession>();
    await show(tester);
    await enter(tester);
    await tester.tap(find.text('Unlock local data'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    vault.pending!.complete(vault.session);
    await tester.pump();
    expect(vault.closes, greaterThan(0));
    expect(vault.session.closes, 1);
  });

  testWidgets(
    'disposal during lock does not touch disposed secret controllers',
    (tester) async {
      vault.state = BrowserDatabaseState.unlock;
      await show(tester);
      await enter(tester);
      await tester.tap(find.text('Unlock local data'));
      await tester.pumpAndSettle();
      vault.closePending = Completer<void>();
      final locking = lock!();
      await tester.pumpWidget(const SizedBox());
      vault.closePending!.complete();
      await locking;
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposal during retry does not prepare another vault', (
    tester,
  ) async {
    vault.prepareError = const BrowserDatabaseProtectionException(
      'database_busy',
    );
    await show(tester);
    vault.closePending = Completer<void>();
    await tester.tap(find.text('Try again'));
    await tester.pumpWidget(const SizedBox());
    vault.closePending!.complete();
    await tester.pump();
    expect(vault.prepares, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal during preparation closes late vault', (tester) async {
    vault.preparePending = Completer<BrowserDatabaseState>();
    await tester.pumpWidget(
      BrowserDatabaseUnlockGate(
        vaultFactory: () => vault,
        builder: (_, _, _) => const SizedBox(),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    vault.preparePending!.complete(BrowserDatabaseState.unlock);
    await tester.pump();
    expect(vault.closes, greaterThan(0));
  });
}

final class _Vault implements BrowserDatabaseVault {
  BrowserDatabaseState state = BrowserDatabaseState.create;
  Object? prepareError;
  Object? error;
  Completer<BrowserDatabaseState>? preparePending;
  Completer<BrowserDatabaseSession>? pending;
  Completer<void>? closePending;
  int prepares = 0;
  final _Session session = _Session();
  int unlocks = 0;
  int closes = 0;
  String? secret;
  @override
  Future<BrowserDatabaseState> prepare() async {
    prepares++;
    if (prepareError != null) throw prepareError!;
    return preparePending?.future ?? state;
  }

  @override
  Future<BrowserDatabaseSession> unlock(String passphrase) async {
    unlocks++;
    secret = passphrase;
    if (error != null) throw error!;
    return pending?.future ?? session;
  }

  @override
  Future<void> close() async {
    closes++;
    await closePending?.future;
  }
}

final class _Session implements BrowserDatabaseSession {
  @override
  final QueryExecutor executor = NativeDatabase.memory();
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
  }
}
