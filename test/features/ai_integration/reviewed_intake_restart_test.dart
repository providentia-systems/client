import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/ai_integration/application/receipt_ai_handoff_controller.dart';
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

void main() {
  for (final decision in AiObservationDecision.values) {
    test('accepted candidates cannot bypass $decision evidence', () {
      final review = _review(decision: decision);
      expect(review.canAccept(1), decision == AiObservationDecision.distinct);
      if (decision == AiObservationDecision.distinct) {
        expect(const AiReviewHandoffBuilder().build(review).acceptedCandidates, hasLength(2));
      } else {
        expect(() => const AiReviewHandoffBuilder().build(review), throwsA(isA<AiServerException>()));
      }
    });
  }
  test('rejected discrepancy prevents handoff even after candidate acceptance', () {
    final review = _review(discrepancies: const [AiDiscrepancyReview(position: 0, observationIndex: 0, revision: 2, type: 'field', field: 'merchant', primary: 'A', validation: 'B', decision: AiDiscrepancyDecision.rejectedExtraction)]);
    expect(() => const AiReviewHandoffBuilder().build(review), throwsA(isA<AiServerException>()));
  });
  test('receipt intake survives database reopen and preserves manual edits', () async {
    final directory = await Directory.systemTemp.createTemp('providentia-intake-');
    final file = File('${directory.path}/device.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    try {
      var repository = DriftHouseholdRepository(database, deviceId: _device);
      final handoff = const AiReviewHandoffBuilder().build(_review());
      var controller = ReceiptAiHandoffController(handoff: handoff, repository: repository, activeHomeId: _home, mayWritePurchases: true);
      expect(await database.select(database.clientOperations).get(), isEmpty);
      expect(await controller.confirm(), isTrue, reason: controller.safeMessage);
      final receiptId = controller.receiptId;
      final capture = (await repository.watchActiveReceiptCapture(homeId: _home).first)!;
      expect(capture.lines.first.rawDescription, 'Original scan line 0');
      await repository.updateReceiptDraftLine(lineId: capture.lines.first.id, expectedRevision: capture.lines.first.revision, line: PurchaseReceiptLineRequest(homeId: _home, receiptId: capture.id, rawDescription: 'Manually corrected rice', quantity: 3, lineTotal: Money(minorUnits: 300, currency: 'NAD')));
      final operationCount = (await database.select(database.clientOperations).get()).length;
      controller.dispose();
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      repository = DriftHouseholdRepository(database, deviceId: _device);
      controller = ReceiptAiHandoffController(handoff: handoff, repository: repository, activeHomeId: _home, mayWritePurchases: true);
      expect(await controller.confirm(), isTrue, reason: controller.safeMessage);
      expect(controller.receiptId, receiptId);
      final resumed = (await repository.watchActiveReceiptCapture(homeId: _home).first)!;
      expect(resumed.lines, hasLength(2));
      expect(resumed.lines.first.rawDescription, 'Manually corrected rice');
      expect(resumed.lines.first.quantity, 3);
      final operations = await database.select(database.clientOperations).get();
      expect(operations, hasLength(operationCount));
      expect(operations.any((row) => row.operationType == 'purchasing.receipt.commit'), isFalse);
      controller.dispose();
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}

AiExtractionReview _review({AiObservationDecision decision = AiObservationDecision.distinct, List<AiDiscrepancyReview> discrepancies = const []}) => AiExtractionReview(homeId: _home, extractionId: _extraction, kind: AiExtractionKind.receipt, observations: [AiObservationReview(id: _observation, revision: 1, exactDigest: false, leftReference: 'observation:0:candidate:0', rightReference: 'observation:1:candidate:0', leftCandidatePosition: 0, rightCandidatePosition: 1, decision: decision)], discrepancies: discrepancies, candidates: [for (var position = 0; position < 2; position++) AiReviewCandidate(homeId: _home, extractionId: _extraction, position: position, type: AiCandidateType.receiptLine, label: 'Rice', status: AiCandidateReviewStatus.accepted, revision: 2, receiptPayload: AiReceiptCandidatePayload(rawText: 'Original scan line $position', description: 'Rice', quantity: 1, packText: null, unitPriceMinorUnits: 100, lineTotalMinorUnits: 100, header: AiReceiptHeaderPayload(merchant: 'Synthetic market', receiptNumber: 'S1', purchaseDate: DateTime.utc(2026, 9, 14), currency: 'NAD', totalMinorUnits: 200, taxMinorUnits: 0, notes: null)))]);
const _home = '11111111-1111-4111-8111-111111111111';
const _device = '22222222-2222-4222-8222-222222222222';
const _extraction = '33333333-3333-4333-8333-333333333333';
const _observation = '44444444-4444-4444-8444-444444444444';
