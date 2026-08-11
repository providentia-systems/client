import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/generated_server_ai_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'parser preserves allowlisted corrected receipt values in handoff',
    () async {
      final repository = GeneratedServerAiRepository(
        _client((request) async => _json(_extraction())),
      );

      final review = await repository.loadExtractionReview(
        homeId: 'home-1',
        extractionId: 'extract-1',
      );
      final candidate = review.candidates.single;
      final payload = candidate.receiptPayload!;
      final handoff = const AiReviewHandoffBuilder().build(review);

      expect(payload.rawText, 'RICE OLD LABEL 1KG');
      expect(payload.description, 'Corrected rice');
      expect(payload.quantity, 2);
      expect(payload.packText, '1 kg');
      expect(payload.unitPriceMinorUnits, 1299);
      expect(payload.lineTotalMinorUnits, 2598);
      expect(payload.header?.merchant, 'Home Market');
      expect(payload.header?.purchaseDate, DateTime.utc(2026, 8, 10));
      expect(payload.header?.currency, 'NAD');
      expect(payload.header?.totalMinorUnits, 2598);
      expect(handoff.acceptedReceiptPayloads.single, same(payload));
      expect(handoff.acceptedPositions, <int>[0]);
    },
  );

  test('candidate payload fields outside the allowlist fail closed', () async {
    final unsafe = _extraction();
    final candidates = unsafe['candidates']! as List<Object?>;
    final candidate = candidates.single as Map<String, Object?>;
    final payload = candidate['payload']! as Map<String, Object?>;
    payload['privateProviderResponse'] = 'must never cross the boundary';
    final repository = GeneratedServerAiRepository(
      _client((request) async => _json(unsafe)),
    );

    await expectLater(
      repository.loadExtractionReview(
        homeId: 'home-1',
        extractionId: 'extract-1',
      ),
      throwsA(
        isA<AiServerException>().having(
          (error) => error.kind,
          'kind',
          AiServerFailureKind.invalidResponse,
        ),
      ),
    );
  });
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: const <String, String>{'content-type': 'application/json'},
);

Map<String, Object?> _extraction() => <String, Object?>{
  'id': 'extract-1',
  'kind': 'receipt',
  'status': 'review_required',
  'result': <String, Object?>{
    'documentType': 'receipt',
    'merchant': 'Home Market',
    'receiptNumber': 'R-42',
    'purchaseDate': '2026-08-10',
    'currency': 'NAD',
    'totalAmount': '25.98',
    'taxAmount': '0.00',
    'notes': 'Header corrected during review.',
    'warnings': <Object?>[],
    'candidates': <Object?>[],
  },
  'candidates': <Object?>[
    <String, Object?>{
      'position': 0,
      'candidateType': 'receipt_line',
      'reviewStatus': 'accepted',
      'revision': 2,
      'payload': <String, Object?>{
        'candidateType': 'receipt_line',
        'rawText': 'RICE OLD LABEL 1KG',
        'description': 'Corrected rice',
        'brand': null,
        'product': 'Rice',
        'variant': null,
        'quantity': '2',
        'packText': '1 kg',
        'unitPrice': '12.99',
        'lineTotal': '25.98',
        'discountAmount': null,
        'taxAmount': '0.00',
        'boundingRegion': null,
        'confidence': 0.97,
        'fieldConfidence': <String, Object?>{},
        'warnings': <Object?>[],
        'unresolvedValues': <Object?>[],
      },
    },
  ],
};
