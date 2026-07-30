import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';
import 'package:providentia/features/inventory/presentation/inventory_controller.dart';
import 'package:providentia/features/inventory/presentation/inventory_workspace.dart';

void main() {
  group('InventoryController stream isolation', () {
    test(
      'starts once and reports item and count-session access failures',
      () async {
        final repository = _RecordingInventoryRepository();
        final controller = _controller(repository);
        addTearDown(() async {
          controller.dispose();
          await repository.close();
        });

        controller
          ..start()
          ..start();

        expect(repository.watchItemsCalls, 1);
        expect(repository.watchSessionCalls, 1);

        repository.items.add(<InventoryItem>[
          _item(id: 'rice', name: 'Basmati Rice', quantity: 4),
        ]);
        repository.sessions.add(null);
        await pumpEventQueue();

        expect(controller.state.loading, isFalse);
        expect(controller.state.items.single.id, 'rice');
        expect(controller.state.safeError, isNull);

        repository.items.add(<InventoryItem>[
          _item(id: 'foreign-item', homeId: 'another-home'),
        ]);
        await pumpEventQueue();

        expect(controller.state.items.single.id, 'rice');
        expect(controller.state.safeError, 'Inventory access was rejected.');

        final validSession = _session(id: 'valid-session');
        repository.sessions.add(validSession);
        await pumpEventQueue();
        expect(controller.state.activeSession, validSession);

        repository.sessions.add(
          _session(id: 'foreign-session', homeId: 'another-home'),
        );
        await pumpEventQueue();

        expect(controller.state.activeSession, validSession);
        expect(
          controller.state.safeError,
          'Count-session access was rejected.',
        );
      },
    );

    test(
      'turns repository stream errors into safe user-facing messages',
      () async {
        final repository = _RecordingInventoryRepository();
        final controller = _controller(repository);
        addTearDown(() async {
          controller.dispose();
          await repository.close();
        });

        controller.start();
        repository.items.addError(StateError('database unavailable'));
        await pumpEventQueue();

        expect(controller.state.safeError, 'Inventory could not be loaded.');
        expect(controller.state.loading, isFalse);

        repository.sessions.addError(StateError('session unavailable'));
        await pumpEventQueue();

        expect(
          controller.state.safeError,
          'The count session could not be loaded.',
        );
      },
    );

    test('dispose detaches both repository subscriptions', () async {
      final repository = _RecordingInventoryRepository();
      final controller = _controller(repository)..start();

      repository.items.add(<InventoryItem>[_item(id: 'before-dispose')]);
      await pumpEventQueue();
      expect(controller.state.items.single.id, 'before-dispose');

      controller.dispose();
      await pumpEventQueue();
      expect(repository.items.hasListener, isFalse);
      expect(repository.sessions.hasListener, isFalse);

      await repository.close();
    });
  });

  group('InventoryController workflow', () {
    test('combines search, category, and inventory-view criteria', () async {
      final repository = _RecordingInventoryRepository();
      final controller = _controller(repository);
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      controller.start();
      repository.items.add(<InventoryItem>[
        _item(
          id: 'cola',
          name: 'Cola Zero',
          category: 'Drinks',
          aliases: const <String>['coca cola'],
          quantity: 2,
        ),
        _item(id: 'tea', name: 'Green Tea', category: 'Drinks'),
        _item(id: 'soap', name: 'Dish Soap', category: 'Cleaning', quantity: 1),
      ]);
      repository.sessions.add(
        _session(
          lines: <StockCountLine>[_line(itemId: 'cola', observedQuantity: 2)],
        ),
      );
      await pumpEventQueue();

      controller
        ..selectView(InventoryView.itemMaster)
        ..selectCategory('Drinks')
        ..updateSearch('coca cola');
      expect(
        controller.visibleItems.map((InventoryItem item) => item.id),
        <String>['cola'],
      );

      controller.selectView(InventoryView.counted);
      expect(controller.state.criteria.query, isEmpty);
      expect(controller.state.criteria.category, isNull);
      expect(
        controller.visibleItems.map((InventoryItem item) => item.id),
        <String>['soap', 'cola'],
      );

      controller.selectView(InventoryView.itemMaster);
      expect(
        controller.visibleItems.map((InventoryItem item) => item.id),
        <String>['soap', 'tea', 'cola'],
      );
    });

    test(
      'records adjustment intents and omits a zero stock movement',
      () async {
        final repository = _RecordingInventoryRepository();
        final controller = _controller(
          repository,
          idGenerator: () => 'adjustment-7',
        );
        addTearDown(() async {
          controller.dispose();
          await repository.close();
        });

        await controller.adjustQuantity(
          item: _item(id: 'empty-bin'),
          locationId: 'secondary',
          observedQuantity: 0,
          reason: 'Verified empty shelf',
        );

        expect(repository.adjustments, hasLength(1));
        expect(repository.movements, <StockMovement?>[null]);
        expect(repository.adjustments.single.id, 'adjustment-7');
        expect(repository.adjustments.single.projectedQuantity, 0);
        expect(repository.adjustments.single.observedQuantity, 0);
        expect(repository.adjustments.single.locationId, 'secondary');
      },
    );

    test('runs a deterministic manual count through completion', () async {
      final repository = _RecordingInventoryRepository(
        publishSavedSessions: true,
      );
      final controller = _controller(
        repository,
        idGenerator: () => 'count-42',
        clock: () => DateTime.utc(2026, 7, 31, 9, 30),
      );
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      controller.start();
      repository.items.add(<InventoryItem>[_item(id: 'flour', name: 'Flour')]);
      repository.sessions.add(null);
      await pumpEventQueue();

      expect(
        () => controller.recordManualCount(
          item: _item(id: 'flour'),
          observedQuantity: 3,
        ),
        throwsStateError,
      );
      expect(controller.closeCount, throwsStateError);
      expect(controller.cancelCount, throwsStateError);

      await controller.startCount(locationId: 'pantry');
      await pumpEventQueue();

      expect(repository.savedSessions, hasLength(1));
      expect(controller.state.activeSession?.id, 'count-42');
      expect(controller.state.activeSession?.locationId, 'pantry');
      expect(
        () => controller.startCount(locationId: 'another-location'),
        throwsStateError,
      );

      await controller.recordManualCount(
        item: _item(id: 'flour', name: 'Flour'),
        observedQuantity: 3,
      );
      await pumpEventQueue();

      final recorded = repository.savedSessions.last;
      expect(recorded.lines, hasLength(1));
      expect(recorded.lines.single.id, 'manual:count-42:flour');
      expect(recorded.lines.single.source, CountSource.manual);
      expect(recorded.lines.single.status, CountLineStatus.confirmed);
      expect(recorded.lines.single.observedQuantity, 3);

      await controller.closeCount();
      await pumpEventQueue();

      final closed = repository.savedSessions.last;
      expect(closed.status, CountSessionStatus.closed);
      expect(closed.closedAt, DateTime.utc(2026, 7, 31, 9, 30));
      expect(controller.state.activeSession, isNull);
    });

    test(
      'cancels an active count and rejects cross-home session writes',
      () async {
        final repository = _RecordingInventoryRepository(
          publishSavedSessions: true,
        );
        final controller = _controller(
          repository,
          idGenerator: () => 'count-to-cancel',
        );
        addTearDown(() async {
          controller.dispose();
          await repository.close();
        });

        controller.start();
        repository.sessions.add(null);
        await pumpEventQueue();

        expect(
          () => controller.saveSession(_session(homeId: 'another-home')),
          throwsStateError,
        );

        await controller.startCount();
        await pumpEventQueue();
        await controller.cancelCount();
        await pumpEventQueue();

        expect(
          repository.savedSessions.last.status,
          CountSessionStatus.cancelled,
        );
        expect(controller.state.activeSession, isNull);
      },
    );
  });

  group('InventoryWorkspace workflow', () {
    testWidgets(
      'keeps adjustment dialog controllers alive through route exit',
      (WidgetTester tester) async {
        final repository = _RecordingInventoryRepository();
        final controller = _controller(
          repository,
          idGenerator: () => 'dialog-adjustment',
        );
        addTearDown(() async {
          controller.dispose();
          await repository.close();
        });

        await tester.pumpWidget(_testApp(controller));
        repository.items.add(<InventoryItem>[
          _item(
            id: 'rice',
            name: 'Basmati Rice',
            category: 'Food',
            quantity: 2,
          ),
        ]);
        repository.sessions.add(null);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Basmati Rice'));
        await tester.pumpAndSettle();
        expect(find.text('Adjust Basmati Rice'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey<String>('inventory-quantity-input')),
          '3.5',
        );
        await tester.enterText(
          find.byKey(const ValueKey<String>('inventory-adjustment-reason')),
          'Cycle count correction',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Adjust Basmati Rice'), findsNothing);
        expect(repository.adjustments, hasLength(1));
        expect(repository.adjustments.single.id, 'dialog-adjustment');
        expect(repository.adjustments.single.observedQuantity, 3.5);
        expect(repository.adjustments.single.reason, 'Cycle count correction');
        expect(repository.movements.single?.quantityDelta, 1.5);
      },
    );

    testWidgets('records and finishes a count from the workspace', (
      WidgetTester tester,
    ) async {
      final repository = _RecordingInventoryRepository(
        publishSavedSessions: true,
      );
      final controller = _controller(
        repository,
        idGenerator: () => 'workspace-count',
      );
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      await tester.pumpWidget(_testApp(controller));
      repository.items.add(<InventoryItem>[
        _item(id: 'beans', name: 'Black Beans', category: 'Food', quantity: 0),
      ]);
      repository.sessions.add(null);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('start-stock-count')));
      await tester.pumpAndSettle();

      expect(find.text('0 products counted'), findsOneWidget);
      FilledButton finishButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('finish-stock-count')),
      );
      expect(finishButton.onPressed, isNull);

      await controller.recordManualCount(
        item: _item(
          id: 'beans',
          name: 'Black Beans',
          category: 'Food',
          quantity: 0,
        ),
        observedQuantity: 6,
      );
      await tester.pumpAndSettle();

      expect(find.text('1 products counted'), findsOneWidget);
      finishButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('finish-stock-count')),
      );
      expect(finishButton.onPressed, isNotNull);

      await tester.tap(
        find.byKey(const ValueKey<String>('finish-stock-count')),
      );
      await tester.pumpAndSettle();

      expect(
        repository.savedSessions.map(
          (StockCountSession session) => session.status,
        ),
        <CountSessionStatus>[
          CountSessionStatus.open,
          CountSessionStatus.open,
          CountSessionStatus.closed,
        ],
      );
      expect(
        find.byKey(const ValueKey<String>('start-stock-count')),
        findsOneWidget,
      );
    });

    testWidgets('renders safe errors and whole or decimal quantities', (
      WidgetTester tester,
    ) async {
      final repository = _RecordingInventoryRepository();
      final controller = _controller(repository);
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      await tester.pumpWidget(_testApp(controller));
      repository.items.add(<InventoryItem>[
        _item(id: 'whole', name: 'Whole Units', quantity: 2),
        _item(id: 'decimal', name: 'Decimal Units', quantity: 1.25),
      ]);
      repository.sessions.add(null);
      await tester.pumpAndSettle();

      expect(find.text('2 units'), findsOneWidget);
      expect(find.text('1.25 units'), findsOneWidget);

      repository.items.addError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Inventory could not be loaded.'), findsOneWidget);
    });

    testWidgets('filters the item master by category and shows empty state', (
      WidgetTester tester,
    ) async {
      final repository = _RecordingInventoryRepository();
      final controller = _controller(repository);
      addTearDown(() async {
        controller.dispose();
        await repository.close();
      });

      await tester.pumpWidget(_testApp(controller));
      repository.items.add(<InventoryItem>[
        _item(id: 'coffee', name: 'Coffee', category: 'Drinks', quantity: 1),
        _item(id: 'soap', name: 'Dish Soap', category: 'Cleaning'),
      ]);
      repository.sessions.add(null);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Item master'));
      await tester.pumpAndSettle();
      expect(find.text('Coffee'), findsOneWidget);
      expect(find.text('Dish Soap'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('inventory-category')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cleaning').last);
      await tester.pumpAndSettle();

      expect(find.text('Dish Soap'), findsOneWidget);
      expect(find.text('Coffee'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey<String>('inventory-search')),
        'missing product',
      );
      await tester.pumpAndSettle();

      expect(find.text('No matching inventory items.'), findsOneWidget);
    });
  });
}

InventoryController _controller(
  _RecordingInventoryRepository repository, {
  String Function()? idGenerator,
  DateTime Function()? clock,
}) {
  return InventoryController(
    repository: repository,
    homeId: 'home-1',
    search: const InventoryItemSearch(),
    idGenerator: idGenerator ?? () => 'generated-id',
    clock: clock ?? () => DateTime.utc(2026, 7, 31, 8),
  );
}

Widget _testApp(InventoryController controller) {
  return MaterialApp(
    home: Scaffold(body: InventoryWorkspace(controller: controller)),
  );
}

InventoryItem _item({
  required String id,
  String homeId = 'home-1',
  String name = 'Item',
  String category = 'Food',
  List<String> aliases = const <String>[],
  double? quantity,
}) {
  return InventoryItem(
    id: id,
    homeId: homeId,
    canonicalName: name,
    packSize: '1 unit',
    category: category,
    aliases: aliases,
    currentQuantity: quantity,
  );
}

StockCountSession _session({
  String id = 'session-1',
  String homeId = 'home-1',
  List<StockCountLine> lines = const <StockCountLine>[],
}) {
  return StockCountSession(
    id: id,
    homeId: homeId,
    locationId: 'primary',
    startedAt: DateTime.utc(2026, 7, 31),
    lines: lines,
  );
}

StockCountLine _line({
  required String itemId,
  required double observedQuantity,
}) {
  return StockCountLine(
    id: 'line-$itemId',
    itemId: itemId,
    observedQuantity: observedQuantity,
    source: CountSource.manual,
    status: CountLineStatus.confirmed,
  );
}

class _RecordingInventoryRepository implements InventoryRepository {
  _RecordingInventoryRepository({this.publishSavedSessions = false});

  final bool publishSavedSessions;
  final StreamController<List<InventoryItem>> items =
      StreamController<List<InventoryItem>>.broadcast();
  final StreamController<StockCountSession?> sessions =
      StreamController<StockCountSession?>.broadcast();

  final List<ManualAdjustmentIntent> adjustments = <ManualAdjustmentIntent>[];
  final List<StockMovement?> movements = <StockMovement?>[];
  final List<StockCountSession> savedSessions = <StockCountSession>[];

  int watchItemsCalls = 0;
  int watchSessionCalls = 0;

  @override
  Stream<List<InventoryItem>> watchItems({required String homeId}) {
    watchItemsCalls++;
    return items.stream;
  }

  @override
  Stream<StockCountSession?> watchActiveCountSession({required String homeId}) {
    watchSessionCalls++;
    return sessions.stream;
  }

  @override
  Future<void> commitManualAdjustment({
    required ManualAdjustmentIntent intent,
    required StockMovement? movement,
  }) async {
    adjustments.add(intent);
    movements.add(movement);
  }

  @override
  Future<void> saveCountSession(StockCountSession session) async {
    savedSessions.add(session);
    if (publishSavedSessions) {
      sessions.add(session.status == CountSessionStatus.open ? session : null);
    }
  }

  Future<void> close() async {
    await items.close();
    await sessions.close();
  }
}
