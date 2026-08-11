import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/infrastructure/generated_online_shopping_suggestion_repository.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  test(
    'uses only the last verified same-home feed while unavailable',
    () async {
      final remote = _RemoteRepository(
        ShoppingSuggestionFeed(
          suggestions: <OnlineShoppingSuggestion>[_suggestion(_homeId)],
          fromVerifiedCache: false,
          verifiedAt: DateTime.utc(2026, 8, 11, 12),
        ),
      );
      final cache = _Cache();
      final repository = CachedOnlineShoppingSuggestionRepository(
        remote: remote,
        cache: cache,
      );

      final live = await repository.list(homeId: _homeId);
      expect(live.fromVerifiedCache, isFalse);
      expect(cache.snapshot!.homeId, _homeId);

      remote.failure = const OnlineSuggestionException(
        OnlineSuggestionFailureKind.unavailable,
      );
      final offline = await repository.list(homeId: _homeId);
      expect(offline.fromVerifiedCache, isTrue);
      expect(offline.suggestions.single.homeId, _homeId);

      await expectLater(
        repository.list(homeId: _otherHomeId),
        throwsA(isA<OnlineSuggestionException>()),
      );
    },
  );

  test('authorization failure purges cache and never falls back', () async {
    final cache = _Cache()
      ..snapshot = VerifiedShoppingSuggestionSnapshot(
        homeId: _homeId,
        verifiedAt: DateTime.utc(2026, 8, 11),
        suggestions: <OnlineShoppingSuggestion>[_suggestion(_homeId)],
      );
    final remote = _RemoteRepository(null)
      ..failure = const OnlineSuggestionException(
        OnlineSuggestionFailureKind.authorizationDenied,
      );
    final repository = CachedOnlineShoppingSuggestionRepository(
      remote: remote,
      cache: cache,
    );

    await expectLater(
      repository.list(homeId: _homeId),
      throwsA(
        isA<OnlineSuggestionException>().having(
          (error) => error.kind,
          'kind',
          OnlineSuggestionFailureKind.authorizationDenied,
        ),
      ),
    );
    expect(cache.snapshot, isNull);
    expect(cache.clearedHomes, <String>[_homeId]);
  });

  test('non-disclosing HTTP 404 purges verified cache', () async {
    final cache = _Cache()
      ..snapshot = VerifiedShoppingSuggestionSnapshot(
        homeId: _homeId,
        verifiedAt: DateTime.utc(2026, 8, 11),
        suggestions: <OnlineShoppingSuggestion>[_suggestion(_homeId)],
      );
    final remote = GeneratedOnlineShoppingSuggestionRepository(
      ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(<String, Object?>{
              'type': 'about:blank',
              'title': 'Not Found',
              'status': 404,
            }),
            404,
          ),
        ),
      ),
    );
    final repository = CachedOnlineShoppingSuggestionRepository(
      remote: remote,
      cache: cache,
    );

    await expectLater(
      repository.list(homeId: _homeId),
      throwsA(
        isA<OnlineSuggestionException>().having(
          (error) => error.kind,
          'kind',
          OnlineSuggestionFailureKind.authorizationDenied,
        ),
      ),
    );
    expect(cache.snapshot, isNull);
    expect(cache.clearedHomes, <String>[_homeId]);
  });
}

const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _otherHomeId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';

OnlineShoppingSuggestion _suggestion(String homeId) => OnlineShoppingSuggestion(
  id: '0198a0b1-c2d3-7e4f-a345-6789abcdef01',
  homeId: homeId,
  homeProductId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
  productName: 'Oats',
  expectedDemand: ExactDecimal('3'),
  safetyStock: ExactDecimal('1'),
  factualStock: ExactDecimal('1'),
  usableStock: ExactDecimal('1'),
  requiredQuantity: ExactDecimal('3'),
  confidenceScore: ExactDecimal('0.5'),
  confidenceBand: ShoppingSuggestionConfidenceBand.medium,
  status: OnlineShoppingSuggestionStatus.active,
  expiresAt: DateTime.utc(2026, 8, 12),
  modelVersion: 'suggestion-v1',
  asOf: DateTime.utc(2026, 8, 11),
  inputWatermark:
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
);

final class _Cache implements ShoppingSuggestionCache {
  VerifiedShoppingSuggestionSnapshot? snapshot;
  final List<String> clearedHomes = <String>[];

  @override
  Future<void> clear({required String homeId}) async {
    clearedHomes.add(homeId);
    if (snapshot?.homeId == homeId) snapshot = null;
  }

  @override
  Future<VerifiedShoppingSuggestionSnapshot?> read({required String homeId}) {
    return Future<VerifiedShoppingSuggestionSnapshot?>.value(
      snapshot?.homeId == homeId ? snapshot : null,
    );
  }

  @override
  Future<void> replace(VerifiedShoppingSuggestionSnapshot value) async {
    snapshot = value;
  }
}

final class _RemoteRepository implements OnlineShoppingSuggestionRepository {
  _RemoteRepository(this.feed);

  ShoppingSuggestionFeed? feed;
  OnlineSuggestionException? failure;

  @override
  Future<ShoppingSuggestionFeed> list({required String homeId}) async {
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    return feed!;
  }

  @override
  Future<OnlineShoppingSuggestionExplanation> explanation({
    required String homeId,
    required String suggestionId,
  }) => throw UnimplementedError();

  @override
  Future<OnlineSuggestionFeedbackReceipt> recordFeedback(
    OnlineSuggestionFeedback feedback,
  ) => throw UnimplementedError();
}
