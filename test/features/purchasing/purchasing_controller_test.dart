import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_controller.dart';
import 'package:providentia/features/purchasing/presentation/purchasing_workspace.dart';

void main() {
  testWidgets(
    'purchasing workspace switches from receipts to monthly history',
    (tester) async {
      final repository = _PurchaseRepository();
      final controller = PurchasingController(
        repository: repository,
        homeId: 'home-a',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingWorkspace(controller: controller)),
        ),
      );
      repository.lines.add(<PurchaseLine>[
        _line(
          'recent',
          PurchaseSource.recentReceipt,
          DateTime.utc(2026, 7, 18),
        ),
        _line(
          'history',
          PurchaseSource.historicalImport,
          DateTime.utc(2026, 4),
        ),
      ]);
      await tester.pump();

      expect(find.text('Metro Fresh'), findsOneWidget);
      await tester.tap(find.text('History'));
      await tester.pump();
      expect(find.text('2026-04'), findsOneWidget);
      expect(find.text('1 purchase lines'), findsOneWidget);

      controller.dispose();
      await repository.close();
    },
  );
}

PurchaseLine _line(String id, PurchaseSource source, DateTime at) =>
    PurchaseLine(
      id: id,
      homeId: 'home-a',
      purchasedAt: at,
      datePrecision: source == PurchaseSource.recentReceipt
          ? PurchaseDatePrecision.exactDay
          : PurchaseDatePrecision.monthOnly,
      storeName: 'Metro Fresh',
      rawDescription: 'Rice',
      packSize: '1 kg',
      quantity: 1,
      source: source,
      lineTotal: source == PurchaseSource.recentReceipt
          ? Money(minorUnits: 1000, currency: 'NAD')
          : null,
    );

class _PurchaseRepository implements PurchaseRepository {
  final lines = StreamController<List<PurchaseLine>>.broadcast();

  @override
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId}) =>
      lines.stream;

  @override
  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  }) => const Stream<List<PriceObservation>>.empty();

  Future<void> close() => lines.close();
}
