import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/infrastructure/generated_online_shopping_suggestion_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _otherHomeId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const _suggestionId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const _homeProductId = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const _packId = '0198a0b1-c2d3-7e4f-9567-89abcdef0123';
const _storeId = '0198a0b1-c2d3-7e4f-a678-9abcdef01234';
const _feedbackId = '0198a0b1-c2d3-7e4f-b789-abcdef012345';
const _watermark =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  test('maps list, explanation, and feedback without decimal loss', () async {
    Map<String, Object?>? feedbackBody;
    final repository = GeneratedOnlineShoppingSuggestionRepository(
      _client((request) async {
        if (request.url.path.endsWith('/shopping-suggestions')) {
          return _json(<String, Object?>{
            'data': <Object?>[_suggestion()],
          });
        }
        if (request.url.path.endsWith('/explanation')) {
          return _json(_explanation());
        }
        if (request.url.path.endsWith('/feedback')) {
          feedbackBody = jsonDecode(request.body) as Map<String, Object?>;
          return _json(<String, Object?>{'id': _feedbackId}, status: 201);
        }
        return _json(<String, Object?>{}, status: 404);
      }),
      clock: () => DateTime.utc(2026, 8, 11, 12, 30),
    );

    final feed = await repository.list(homeId: _homeId);
    final suggestion = feed.suggestions.single;
    expect(feed.fromVerifiedCache, isFalse);
    expect(feed.verifiedAt, DateTime.utc(2026, 8, 11, 12, 30));
    expect(suggestion.id, _suggestionId);
    expect(suggestion.homeId, _homeId);
    expect(suggestion.homeProductId, _homeProductId);
    expect(suggestion.selectedPackId, _packId);
    expect(suggestion.requiredQuantity.value, '3.12500001');
    expect(suggestion.confidenceScore.value, '0.2500');
    expect(suggestion.confidenceBand, ShoppingSuggestionConfidenceBand.low);

    final explanation = await repository.explanation(
      homeId: _homeId,
      suggestionId: _suggestionId,
    );
    expect(explanation.id, _suggestionId);
    expect(explanation.homeProductId, _homeProductId);
    expect(explanation.factors.single.key, 'expected-demand');
    expect(explanation.factors.single.value!.value, '4.12500001');
    expect(explanation.limitations, <String>['Only one count interval.']);
    expect(explanation.packOptions.single.storeId, _storeId);
    expect(explanation.packOptions.single.effectiveTotal.value, '42.75000001');

    final receipt = await repository.recordFeedback(
      OnlineSuggestionFeedback(
        homeId: _homeId,
        suggestionId: _suggestionId,
        decision: OnlineSuggestionDecision.edited,
        resultQuantity: ExactDecimal('3.12500001'),
        reason: 'Exact user reason.',
      ),
    );
    expect(receipt.id, _feedbackId);
    expect(feedbackBody, <String, Object?>{
      'decision': 'edited',
      'resultQuantity': '3.12500001',
      'reason': 'Exact user reason.',
    });
  });

  for (final malformed in <(String, void Function(Map<String, Object?>))>[
    ('invalid UUID', (row) => row['id'] = 'not-a-uuid'),
    ('numeric decimal', (row) => row['requiredQuantity'] = 3.5),
    ('out-of-range confidence', (row) => row['confidenceScore'] = '1.0001'),
    ('unknown status', (row) => row['status'] = 'pending'),
    (
      'non-advancing expiry',
      (row) => row['expiresAt'] = '2026-08-11T11:00:00Z',
    ),
    (
      'invalid watermark',
      (row) => row['inputWatermark'] = _watermark.toUpperCase(),
    ),
    (
      'nested cross-home value',
      (row) => row['future'] = <String, Object?>{'homeId': _otherHomeId},
    ),
  ]) {
    test('rejects ${malformed.$1}', () async {
      final row = _suggestion();
      malformed.$2(row);
      final repository = GeneratedOnlineShoppingSuggestionRepository(
        _client(
          (_) async => _json(<String, Object?>{
            'data': <Object?>[row],
          }),
        ),
      );

      await expectLater(
        repository.list(homeId: _homeId),
        throwsA(
          isA<OnlineSuggestionException>().having(
            (error) => error.kind,
            'kind',
            OnlineSuggestionFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  for (final statusCode in <int>[403, 404]) {
    test(
      'normalizes HTTP $statusCode authorization without backend detail',
      () async {
        const privateDetail = 'PRIVATE household product and support trace';
        final repository = GeneratedOnlineShoppingSuggestionRepository(
          _client(
            (_) async => _json(<String, Object?>{
              'type': 'about:blank',
              'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
              'status': statusCode,
              'detail': privateDetail,
            }, status: statusCode),
          ),
        );

        try {
          await repository.list(homeId: _homeId);
          fail('Expected an authorization failure.');
        } on OnlineSuggestionException catch (error) {
          expect(error.kind, OnlineSuggestionFailureKind.authorizationDenied);
          expect(error.toString(), isNot(contains(privateDetail)));
        }
      },
    );
  }
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

Map<String, Object?> _suggestion() => <String, Object?>{
  'id': _suggestionId,
  'homeProductId': _homeProductId,
  'productName': 'Rolled oats',
  'packText': '1 kg',
  'expectedDemand': '4.12500001',
  'safetyStock': '1',
  'factualStock': '2',
  'usableStock': '2',
  'requiredQuantity': '3.12500001',
  'selectedPackId': _packId,
  'packCount': 4,
  'confidenceScore': '0.2500',
  'confidenceBand': 'low',
  'status': 'active',
  'expiresAt': '2026-08-12T12:00:00Z',
  'modelVersion': 'suggestion-v1',
  'asOf': '2026-08-11T12:00:00Z',
  'inputWatermark': _watermark,
};

Map<String, Object?> _explanation() => <String, Object?>{
  'id': _suggestionId,
  'homeProductId': _homeProductId,
  'requiredQuantity': '3.12500001',
  'confidenceScore': '0.2500',
  'confidenceBand': 'low',
  'factors': <Object?>[
    <String, Object?>{
      'key': 'expected-demand',
      'value': '4.12500001',
      'days': 7,
    },
  ],
  'limitations': <Object?>['Only one count interval.'],
  'packOptions': <Object?>[
    <String, Object?>{
      'packId': _packId,
      'storeId': _storeId,
      'currency': 'NAD',
      'packCount': 4,
      'effectiveTotal': '42.75000001',
      'excessQuantity': '0.87499999',
      'priceObservedAt': '2026-08-10T12:00:00Z',
      'selected': true,
      'reason': 'Lowest comparable total.',
    },
  ],
  'modelVersion': 'suggestion-v1',
  'asOf': '2026-08-11T12:00:00Z',
  'inputWatermark': _watermark,
};
