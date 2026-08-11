import 'dart:collection';

import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';

enum OnlineSuggestionFailureKind {
  authenticationRequired,
  authorizationDenied,
  invalidResponse,
  unavailable,
}

final class OnlineSuggestionException implements Exception {
  const OnlineSuggestionException(this.kind);

  final OnlineSuggestionFailureKind kind;

  @override
  String toString() => 'OnlineSuggestionException(${kind.name})';
}

final class ShoppingSuggestionFeed {
  ShoppingSuggestionFeed({
    required List<OnlineShoppingSuggestion> suggestions,
    required this.fromVerifiedCache,
    required this.verifiedAt,
  }) : suggestions = UnmodifiableListView<OnlineShoppingSuggestion>(
         suggestions,
       );

  final List<OnlineShoppingSuggestion> suggestions;
  final bool fromVerifiedCache;
  final DateTime verifiedAt;
}

abstract interface class OnlineShoppingSuggestionRepository {
  Future<ShoppingSuggestionFeed> list({required String homeId});

  Future<OnlineShoppingSuggestionExplanation> explanation({
    required String homeId,
    required String suggestionId,
  });

  Future<OnlineSuggestionFeedbackReceipt> recordFeedback(
    OnlineSuggestionFeedback feedback,
  );
}

final class VerifiedShoppingSuggestionSnapshot {
  VerifiedShoppingSuggestionSnapshot({
    required this.homeId,
    required this.verifiedAt,
    required List<OnlineShoppingSuggestion> suggestions,
  }) : suggestions = UnmodifiableListView<OnlineShoppingSuggestion>(
         suggestions,
       ) {
    if (homeId.trim().isEmpty ||
        suggestions.any((suggestion) => suggestion.homeId != homeId)) {
      throw StateError('A verified suggestion snapshot must be home-scoped.');
    }
  }

  final String homeId;
  final DateTime verifiedAt;
  final List<OnlineShoppingSuggestion> suggestions;
}

/// Persistence boundary for an encrypted/local verified-suggestion cache.
/// Implementations must partition and purge by home.
abstract interface class ShoppingSuggestionCache {
  Future<VerifiedShoppingSuggestionSnapshot?> read({required String homeId});

  Future<void> replace(VerifiedShoppingSuggestionSnapshot snapshot);

  Future<void> clear({required String homeId});
}

final class NoShoppingSuggestionCache implements ShoppingSuggestionCache {
  const NoShoppingSuggestionCache();

  @override
  Future<void> clear({required String homeId}) async {}

  @override
  Future<VerifiedShoppingSuggestionSnapshot?> read({required String homeId}) {
    return Future<VerifiedShoppingSuggestionSnapshot?>.value();
  }

  @override
  Future<void> replace(VerifiedShoppingSuggestionSnapshot snapshot) async {}
}

/// Adds offline last-verified reads without hiding authentication,
/// authorization, or response-integrity failures behind stale data.
final class CachedOnlineShoppingSuggestionRepository
    implements OnlineShoppingSuggestionRepository {
  factory CachedOnlineShoppingSuggestionRepository({
    required OnlineShoppingSuggestionRepository remote,
    required ShoppingSuggestionCache cache,
  }) => CachedOnlineShoppingSuggestionRepository._(remote, cache);

  const CachedOnlineShoppingSuggestionRepository._(this._remote, this._cache);

  final OnlineShoppingSuggestionRepository _remote;
  final ShoppingSuggestionCache _cache;

  @override
  Future<ShoppingSuggestionFeed> list({required String homeId}) async {
    try {
      final feed = await _remote.list(homeId: homeId);
      if (feed.suggestions.any((row) => row.homeId != homeId)) {
        throw const OnlineSuggestionException(
          OnlineSuggestionFailureKind.invalidResponse,
        );
      }
      try {
        await _cache.replace(
          VerifiedShoppingSuggestionSnapshot(
            homeId: homeId,
            verifiedAt: feed.verifiedAt,
            suggestions: feed.suggestions,
          ),
        );
      } catch (_) {
        // A local cache failure must not hide a freshly verified live feed.
      }
      return feed;
    } on OnlineSuggestionException catch (error) {
      if (error.kind == OnlineSuggestionFailureKind.authenticationRequired ||
          error.kind == OnlineSuggestionFailureKind.authorizationDenied ||
          error.kind == OnlineSuggestionFailureKind.invalidResponse) {
        await _cache.clear(homeId: homeId);
        rethrow;
      }
      final cached = await _cache.read(homeId: homeId);
      if (cached == null || cached.homeId != homeId) rethrow;
      return ShoppingSuggestionFeed(
        suggestions: cached.suggestions,
        fromVerifiedCache: true,
        verifiedAt: cached.verifiedAt,
      );
    }
  }

  @override
  Future<OnlineShoppingSuggestionExplanation> explanation({
    required String homeId,
    required String suggestionId,
  }) async {
    try {
      return await _remote.explanation(
        homeId: homeId,
        suggestionId: suggestionId,
      );
    } on OnlineSuggestionException catch (error) {
      await _clearForAccessFailure(homeId, error);
      rethrow;
    }
  }

  @override
  Future<OnlineSuggestionFeedbackReceipt> recordFeedback(
    OnlineSuggestionFeedback feedback,
  ) async {
    try {
      return await _remote.recordFeedback(feedback);
    } on OnlineSuggestionException catch (error) {
      await _clearForAccessFailure(feedback.homeId, error);
      rethrow;
    }
  }

  Future<void> _clearForAccessFailure(
    String homeId,
    OnlineSuggestionException error,
  ) async {
    if (error.kind == OnlineSuggestionFailureKind.authenticationRequired ||
        error.kind == OnlineSuggestionFailureKind.authorizationDenied) {
      await _cache.clear(homeId: homeId);
    }
  }
}
