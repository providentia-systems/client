import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/proposal_validation.dart';

import 'test_fixtures.dart';

void main() {
  test('strict receipt schema accepts a valid bounded proposal', () {
    final proposal = AiProposalValidator.receiptFromJson(
      proposalId: 'proposal-1',
      runId: 'run-1',
      json: validReceiptJson(),
    );

    expect(proposal.classification, ReceiptDocumentClassification.receipt);
    expect(proposal.lines.single.productName.value, 'Milk');
    expect(proposal.lines.single.quantity.value, 2);
  });

  test('strict receipt schema rejects additional properties', () {
    final json = validReceiptJson()..['providerRawText'] = 'must not persist';

    expect(
      () => AiProposalValidator.receiptFromJson(
        proposalId: 'proposal-1',
        runId: 'run-1',
        json: json,
      ),
      throwsA(isA<ProposalValidationException>()),
    );
  });

  test('receipt line safety limit is enforced before review', () {
    final lines = List<Object?>.generate(
      AiProposalValidator.maximumReceiptLines + 1,
      (index) => validReceiptLineJson(lineId: 'line-$index'),
    );

    expect(
      () => AiProposalValidator.receiptFromJson(
        proposalId: 'proposal-1',
        runId: 'run-1',
        json: validReceiptJson(lines: lines),
      ),
      throwsA(
        isA<ProposalValidationException>().having(
          (error) => error.issues.single,
          'issue',
          contains('300-line'),
        ),
      ),
    );
  });

  test('medical classification is quarantined and cannot contain lines', () {
    expect(
      () => AiProposalValidator.receiptFromJson(
        proposalId: 'proposal-1',
        runId: 'run-1',
        json: validReceiptJson(classification: 'medicine_leaflet'),
      ),
      throwsA(isA<ProposalValidationException>()),
    );

    final quarantined = AiProposalValidator.receiptFromJson(
      proposalId: 'proposal-2',
      runId: 'run-2',
      json: validReceiptJson(
        classification: 'medicine_leaflet',
        lines: <Object?>[],
      ),
    );
    expect(quarantined.requiresQuarantine, isTrue);
  });

  test('stock schema rejects candidates for unrelated media', () {
    final json = _validStockJson(classification: 'unrelated');

    expect(
      () => AiProposalValidator.stockPhotoFromJson(
        proposalId: 'proposal-1',
        runId: 'run-1',
        json: json,
      ),
      throwsA(isA<ProposalValidationException>()),
    );
  });

  test('stock schema validates quantity ranges and normalized regions', () {
    final json = _validStockJson();
    final candidates = json['candidates']! as List<Object?>;
    final candidate = candidates.single as Map<String, Object?>;
    candidate['quantityMinimum'] = 4;
    candidate['quantityMaximum'] = 2;

    expect(
      () => AiProposalValidator.stockPhotoFromJson(
        proposalId: 'proposal-1',
        runId: 'run-1',
        json: json,
      ),
      throwsA(isA<ProposalValidationException>()),
    );
  });
}

Map<String, Object?> _validStockJson({
  String classification = 'pantry_stock',
}) => <String, Object?>{
  'schemaVersion': 'stock-photo-v1',
  'classification': classification,
  'candidates': <Object?>[
    <String, Object?>{
      'candidateId': 'candidate-1',
      'brand': field(null, 0.2),
      'productName': field('Rice', 0.9),
      'variant': field(null, 0.2),
      'packDescription': field('1 kg', 0.85),
      'quantityMinimum': 2,
      'quantityMaximum': 3,
      'confidence': 0.82,
      'warnings': <Object?>['One package is partly occluded'],
      'region': <String, Object?>{
        'pageIndex': 0,
        'x': 0.1,
        'y': 0.1,
        'width': 0.4,
        'height': 0.5,
      },
    },
  ],
  'warnings': <Object?>[],
};
