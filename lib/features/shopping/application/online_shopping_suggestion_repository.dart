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

abstract interface class OnlineShoppingSuggestionRunner {
  Future<void> regenerate({required String homeId});
}

/// Durable decision boundary. A successful queue acknowledges local persistence;
/// the synchronized server feedback remains authoritative across devices.
abstract interface class ShoppingSuggestionFeedbackQueue {
  Future<OnlineSuggestionFeedbackReceipt> queueFeedback(
    OnlineSuggestionFeedback feedback,
  );
  Future<Set<String>> decidedSuggestionIds({required String homeId});
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
    implements
        OnlineShoppingSuggestionRepository,
        OnlineShoppingSuggestionRunner {
  factory CachedOnlineShoppingSuggestionRepository({
    required OnlineShoppingSuggestionRepository remote,
    required ShoppingSuggestionCache cache,
    ShoppingSuggestionFeedbackQueue? feedbackQueue,
  }) =>
      CachedOnlineShoppingSuggestionRepository._(remote, cache, feedbackQueue);

  const CachedOnlineShoppingSuggestionRepository._(
    this._remote,
    this._cache,
    this._feedbackQueue,
  );

  final OnlineShoppingSuggestionRepository _remote;
  final ShoppingSuggestionCache _cache;
  final ShoppingSuggestionFeedbackQueue? _feedbackQueue;

  @override
  Future<void> regenerate({required String homeId}) async {
    final remote = _remote;
    if (remote is! OnlineShoppingSuggestionRunner) {
      throw const OnlineSuggestionException(
        OnlineSuggestionFailureKind.unavailable,
      );
    }
    await (remote as OnlineShoppingSuggestionRunner).regenerate(homeId: homeId);
  }

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
      return _applyDecisions(feed, homeId);
    } on OnlineSuggestionException catch (error) {
      if (error.kind == OnlineSuggestionFailureKind.authenticationRequired ||
          error.kind == OnlineSuggestionFailureKind.authorizationDenied ||
          error.kind == OnlineSuggestionFailureKind.invalidResponse) {
        await _cache.clear(homeId: homeId);
        rethrow;
      }
      final cached = await _cache.read(homeId: homeId);
      if (cached == null || cached.homeId != homeId) rethrow;
      return _applyDecisions(
        ShoppingSuggestionFeed(
          suggestions: cached.suggestions,
          fromVerifiedCache: true,
          verifiedAt: cached.verifiedAt,
        ),
        homeId,
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
    final queue = _feedbackQueue;
    if (queue != null) return queue.queueFeedback(feedback);
    try {
      return await _remote.recordFeedback(feedback);
    } on OnlineSuggestionException catch (error) {
      await _clearForAccessFailure(feedback.homeId, error);
      rethrow;
    }
  }

  Future<ShoppingSuggestionFeed> _applyDecisions(
    ShoppingSuggestionFeed feed,
    String homeId,
  ) async {
    final queue = _feedbackQueue;
    if (queue == null) return feed;
    final decided = await queue.decidedSuggestionIds(homeId: homeId);
    return ShoppingSuggestionFeed(
      suggestions: feed.suggestions
          .where((row) => !decided.contains(row.id))
          .toList(growable: false),
      fromVerifiedCache: feed.fromVerifiedCache,
      verifiedAt: feed.verifiedAt,
    );
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
