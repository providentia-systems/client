import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/application/shopping_interaction_capabilities.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

final class ShoppingState {
  const ShoppingState({
    this.list,
    this.loading = true,
    this.safeError,
    this.suggestions = const <OnlineShoppingSuggestion>[],
    this.suggestionsLoading = false,
    this.suggestionsFromVerifiedCache = false,
    this.suggestionsVerifiedAt,
    this.explanations = const <String, OnlineShoppingSuggestionExplanation>{},
    this.suggestionsAccessDenied = false,
  });

  final ShoppingList? list;
  final bool loading;
  final String? safeError;
  final List<OnlineShoppingSuggestion> suggestions;
  final bool suggestionsLoading;
  final bool suggestionsFromVerifiedCache;
  final DateTime? suggestionsVerifiedAt;
  final Map<String, OnlineShoppingSuggestionExplanation> explanations;
  final bool suggestionsAccessDenied;
}

final class ShoppingController extends ChangeNotifier {
  factory ShoppingController({
    required ShoppingRepository repository,
    required String homeId,
    DateTime Function()? clock,
    String Function()? idGenerator,
    OnlineShoppingSuggestionRepository? suggestionRepository,
    Future<void> Function()? onAuthorizationDenied,
    ShoppingInteractionCapabilities capabilities =
        ShoppingInteractionCapabilities.localManualOnly,
  }) {
    if (capabilities.onlineSuggestionsComposed !=
        (suggestionRepository != null)) {
      throw ArgumentError(
        'Online suggestion capability must match repository composition.',
      );
    }
    return ShoppingController._(
      repository,
      homeId,
      clock ?? DateTime.now,
      idGenerator ?? UuidV4Generator().call,
      suggestionRepository,
      capabilities,
      onAuthorizationDenied,
    );
  }

  ShoppingController._(
    this._repository,
    this.homeId,
    this._clock,
    this._idGenerator,
    this._suggestionRepository,
    this.capabilities,
    this._onAuthorizationDenied,
  );

  final ShoppingRepository _repository;
  final String homeId;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final OnlineShoppingSuggestionRepository? _suggestionRepository;
  final ShoppingInteractionCapabilities capabilities;
  final Future<void> Function()? _onAuthorizationDenied;
  StreamSubscription<ShoppingList>? _subscription;
  final Set<String> _suggestionActionsInFlight = <String>{};
  final Set<String> _hiddenSuggestionIds = <String>{};
  var _suggestionRequestGeneration = 0;
  var _suggestionAuthorizationDenied = false;
  var _authorizationDenialReported = false;
  var _disposed = false;
  ShoppingState _state = const ShoppingState();

  ShoppingState get state => _state;

  void start() {
    if (_subscription != null) return;
    _subscription = _repository.watchActiveList(homeId: homeId).listen(
      (list) {
        if (list.homeId != homeId) {
          _setError('Shopping-list access was rejected.');
          return;
        }
        // The list stream and online-suggestion refresh complete independently.
        // A late list emission must not erase an authorization or validation
        // error produced by the suggestion boundary.
        _state = _copyState(list: list, loading: false);
        notifyListeners();
      },
      onError: (Object _) =>
          _setError('The shopping list could not be loaded.'),
    );
    if (_suggestionRepository != null) {
      unawaited(refreshSuggestions());
    }
  }

  Future<bool> addManual(String name, {double quantity = 1}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (!quantity.isFinite || quantity <= 0) {
      _setError('Enter a quantity greater than zero.');
      return false;
    }
    final list = _requireList();
    try {
      await _repository.saveList(
        list.add(
          ShoppingListLine(
            id: _idGenerator(),
            homeId: homeId,
            name: trimmed,
            quantity: quantity,
            origin: ShoppingLineOrigin.manual,
            createdAt: _clock().toUtc(),
          ),
        ),
      );
      return true;
    } catch (_) {
      _setError('The manual shopping item could not be saved.');
      return false;
    }
  }

  Future<void> refreshSuggestions() async {
    final repository = _suggestionRepository;
    if (repository == null || _suggestionAuthorizationDenied) return;
    final generation = ++_suggestionRequestGeneration;
    _state = _copyState(suggestionsLoading: true, clearSafeError: true);
    notifyListeners();
    try {
      final feed = await repository.list(homeId: homeId);
      if (!_requestIsCurrent(generation)) return;
      if (feed.suggestions.any((suggestion) => suggestion.homeId != homeId)) {
        _clearSuggestions(
          'Online suggestion access was rejected for this home.',
        );
        return;
      }
      final existingSuggestionIds = _state.list?.lines
          .map((line) => line.suggestionId)
          .whereType<String>()
          .toSet();
      final now = _clock().toUtc();
      final visible = feed.suggestions
          .where(
            (suggestion) =>
                suggestion.activeAt(now) &&
                suggestion.requiredQuantity.isPositive &&
                !_hiddenSuggestionIds.contains(suggestion.id) &&
                !(existingSuggestionIds?.contains(suggestion.id) ?? false),
          )
          .toList(growable: false);
      _state = _copyState(
        suggestions: visible,
        suggestionsLoading: false,
        suggestionsFromVerifiedCache: feed.fromVerifiedCache,
        suggestionsVerifiedAt: feed.verifiedAt,
        explanations: const <String, OnlineShoppingSuggestionExplanation>{},
        clearSafeError: true,
      );
      notifyListeners();
    } on OnlineSuggestionException catch (error) {
      if (!_requestIsCurrent(generation)) return;
      if (error.kind == OnlineSuggestionFailureKind.authorizationDenied) {
        _denySuggestionAccess();
      } else if (error.kind ==
              OnlineSuggestionFailureKind.authenticationRequired ||
          error.kind == OnlineSuggestionFailureKind.invalidResponse) {
        _clearSuggestions(_suggestionFailureMessage(error.kind));
      } else {
        _state = _copyState(
          suggestionsLoading: false,
          safeError: _suggestionFailureMessage(error.kind),
        );
        notifyListeners();
      }
    } catch (_) {
      if (!_requestIsCurrent(generation)) return;
      _clearSuggestions('Online suggestions could not be loaded safely.');
    }
  }

  Future<bool> addOnlineSuggestion(
    OnlineShoppingSuggestion suggestion, {
    ExactDecimal? quantity,
  }) async {
    final selectedQuantity = quantity ?? suggestion.requiredQuantity;
    if (!_isCurrentVisibleSuggestion(suggestion) ||
        _state.list == null ||
        !selectedQuantity.isPositive ||
        !_suggestionActionsInFlight.add(suggestion.id)) {
      _setError('This suggestion is no longer available for this home.');
      return false;
    }
    final list = _requireList();
    if (list.lines.any((line) => line.suggestionId == suggestion.id)) {
      _suggestionActionsInFlight.remove(suggestion.id);
      _hideSuggestion(suggestion.id);
      return false;
    }
    final updated = list.add(
      ShoppingListLine(
        id: _idGenerator(),
        homeId: homeId,
        name: suggestion.productName,
        quantity: selectedQuantity.toListQuantity(),
        origin: ShoppingLineOrigin.suggestion,
        createdAt: _clock().toUtc(),
        suggestionId: suggestion.id,
        homeProductId: suggestion.homeProductId,
        selectedPackId: suggestion.selectedPackId,
        explanation:
            'Evidence-based legacy suggestion. Open the live explanation '
            'to review factors and limitations.',
      ),
    );
    try {
      await _repository.saveList(updated);
      _state = _copyState(list: updated, loading: false);
      _hideSuggestion(suggestion.id);
      final suggestionRepository = _suggestionRepository;
      if (suggestionRepository != null &&
          capabilities.canRecordSuggestionFeedback) {
        try {
          await suggestionRepository.recordFeedback(
            OnlineSuggestionFeedback(
              homeId: homeId,
              suggestionId: suggestion.id,
              decision:
                  selectedQuantity.compareTo(suggestion.requiredQuantity) == 0
                  ? OnlineSuggestionDecision.accepted
                  : OnlineSuggestionDecision.edited,
              resultQuantity: selectedQuantity,
              reason:
                  selectedQuantity.compareTo(suggestion.requiredQuantity) == 0
                  ? 'Added to shopping list.'
                  : 'Added to shopping list with an edited quantity.',
            ),
          );
        } on OnlineSuggestionException catch (error) {
          _handleSuggestionActionFailure(error);
        } catch (_) {
          _setError(
            'The item was added, but suggestion feedback was not recorded.',
          );
        }
      }
      return true;
    } catch (_) {
      _setError('The suggested shopping item could not be added.');
      return false;
    } finally {
      _suggestionActionsInFlight.remove(suggestion.id);
    }
  }

  Future<OnlineShoppingSuggestionExplanation?> loadSuggestionExplanation(
    OnlineShoppingSuggestion suggestion,
  ) async {
    final repository = _suggestionRepository;
    if (repository == null || !_isCurrentVisibleSuggestion(suggestion)) {
      _setError('This suggestion explanation is no longer available.');
      return null;
    }
    final cached = _state.explanations[suggestion.id];
    if (cached != null) return cached;
    try {
      final explanation = await repository.explanation(
        homeId: homeId,
        suggestionId: suggestion.id,
      );
      if (!_matchesSuggestion(explanation, suggestion)) {
        _clearSuggestions('The suggestion explanation could not be verified.');
        return null;
      }
      _state = _copyState(
        explanations: <String, OnlineShoppingSuggestionExplanation>{
          ..._state.explanations,
          suggestion.id: explanation,
        },
        clearSafeError: true,
      );
      notifyListeners();
      return explanation;
    } on OnlineSuggestionException catch (error) {
      _handleSuggestionActionFailure(error);
      return null;
    } catch (_) {
      _setError('The suggestion explanation could not be loaded safely.');
      return null;
    }
  }

  Future<bool> decideOnlineSuggestion(
    OnlineShoppingSuggestion suggestion,
    OnlineSuggestionDecision decision,
  ) async {
    final repository = _suggestionRepository;
    if (!capabilities.canRecordSuggestionFeedback ||
        repository == null ||
        !_isCurrentVisibleSuggestion(suggestion) ||
        (decision != OnlineSuggestionDecision.dismissed &&
            decision != OnlineSuggestionDecision.snoozed) ||
        !_suggestionActionsInFlight.add(suggestion.id)) {
      _setError('This suggestion decision is not available.');
      return false;
    }
    try {
      await repository.recordFeedback(
        OnlineSuggestionFeedback(
          homeId: homeId,
          suggestionId: suggestion.id,
          decision: decision,
          resultQuantity: null,
          reason: decision == OnlineSuggestionDecision.dismissed
              ? 'Dismissed from shopping suggestions.'
              : 'Snoozed from shopping suggestions.',
        ),
      );
      _hideSuggestion(suggestion.id);
      return true;
    } on OnlineSuggestionException catch (error) {
      _handleSuggestionActionFailure(error);
      return false;
    } catch (_) {
      _setError('The suggestion decision could not be recorded.');
      return false;
    } finally {
      _suggestionActionsInFlight.remove(suggestion.id);
    }
  }

  Future<void> toggle(String lineId) =>
      _repository.saveList(_requireList().toggle(lineId));

  Future<void> updateQuantity(String lineId, double quantity) {
    if (!capabilities.canEditExistingQuantities) {
      throw UnsupportedError(
        'Existing shopping-line quantity edits are not connected in this workspace.',
      );
    }
    if (!quantity.isFinite || quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'must be positive and finite',
      );
    }
    return _repository.saveList(
      _requireList().updateQuantity(lineId, quantity),
    );
  }

  Future<bool> tryUpdateQuantity(ShoppingListLine line, double quantity) async {
    if (line.homeId != homeId ||
        !_requireList().lines.any((candidate) => candidate.id == line.id)) {
      _setError('This shopping item is not available in the current home.');
      return false;
    }
    try {
      await updateQuantity(line.id, quantity);
    } catch (_) {
      _setError('The shopping quantity could not be updated.');
      return false;
    }
    try {
      if (line.origin == ShoppingLineOrigin.suggestion &&
          capabilities.canRecordSuggestionFeedback) {
        if (line.suggestionId != null && _suggestionRepository != null) {
          await _suggestionRepository.recordFeedback(
            OnlineSuggestionFeedback(
              homeId: homeId,
              suggestionId: line.suggestionId!,
              decision: OnlineSuggestionDecision.edited,
              resultQuantity: ExactDecimal(_feedbackDecimal(quantity)),
              reason: 'Changed shopping-list quantity.',
            ),
          );
        } else if (line.productPackId != null) {
          await _repository.recordFeedback(
            SuggestionFeedback(
              id: _idGenerator(),
              homeId: homeId,
              productPackId: line.productPackId!,
              kind: SuggestionFeedbackKind.quantityEdited,
              recordedAt: _clock().toUtc(),
              originalQuantity: line.quantity,
              updatedQuantity: quantity,
            ),
          );
        }
      }
      return true;
    } on OnlineSuggestionException catch (error) {
      _handleSuggestionActionFailure(error);
      _setError(
        'The quantity was saved, but suggestion feedback was not recorded.',
      );
      return true;
    } catch (_) {
      _setError(
        'The quantity was saved, but suggestion feedback was not recorded.',
      );
      return true;
    }
  }

  Future<void> recordFeedback(SuggestionFeedback feedback) {
    if (feedback.homeId != homeId) {
      throw StateError('Cannot record feedback for another home.');
    }
    if (!capabilities.canRecordSuggestionFeedback) {
      throw UnsupportedError(
        'Suggestion feedback is not connected in this workspace.',
      );
    }
    return _repository.recordFeedback(feedback);
  }

  Future<bool> submitSuggestionFeedback(
    ShoppingListLine line,
    SuggestionFeedbackKind kind,
  ) async {
    if (line.homeId != homeId || line.origin != ShoppingLineOrigin.suggestion) {
      _setError('Only a current-home suggestion can receive feedback.');
      return false;
    }
    if (!capabilities.canRecordSuggestionFeedback) {
      _setError('Suggestion feedback is not available in this workspace.');
      return false;
    }
    if (kind == SuggestionFeedbackKind.quantityEdited) {
      _setError('Edit the quantity to record quantity feedback.');
      return false;
    }
    try {
      final suggestionId = line.suggestionId;
      final suggestionRepository = _suggestionRepository;
      if (suggestionId != null && suggestionRepository != null) {
        await suggestionRepository.recordFeedback(
          OnlineSuggestionFeedback(
            homeId: homeId,
            suggestionId: suggestionId,
            decision: switch (kind) {
              SuggestionFeedbackKind.accepted =>
                OnlineSuggestionDecision.accepted,
              SuggestionFeedbackKind.dismissed =>
                OnlineSuggestionDecision.dismissed,
              SuggestionFeedbackKind.snoozed =>
                OnlineSuggestionDecision.snoozed,
              SuggestionFeedbackKind.quantityEdited =>
                OnlineSuggestionDecision.edited,
            },
            resultQuantity: kind == SuggestionFeedbackKind.accepted
                ? ExactDecimal(_feedbackDecimal(line.quantity))
                : null,
            reason: switch (kind) {
              SuggestionFeedbackKind.accepted =>
                'Marked useful from the shopping list.',
              SuggestionFeedbackKind.dismissed =>
                'Marked not useful from the shopping list.',
              SuggestionFeedbackKind.snoozed =>
                'Snoozed from the shopping list.',
              SuggestionFeedbackKind.quantityEdited =>
                'Changed shopping-list quantity.',
            },
          ),
        );
        return true;
      }
      final productPackId = line.productPackId;
      if (productPackId == null) {
        _setError('Suggestion feedback is not available in this workspace.');
        return false;
      }
      await recordFeedback(
        SuggestionFeedback(
          id: _idGenerator(),
          homeId: homeId,
          productPackId: productPackId,
          kind: kind,
          recordedAt: _clock().toUtc(),
          originalQuantity: line.quantity,
        ),
      );
      return true;
    } on OnlineSuggestionException catch (error) {
      _handleSuggestionActionFailure(error);
      return false;
    } catch (_) {
      _setError('Suggestion feedback could not be recorded.');
      return false;
    }
  }

  ShoppingList _requireList() {
    final list = _state.list;
    if (list == null) {
      throw StateError('The active shopping list is not loaded.');
    }
    return list;
  }

  bool _requestIsCurrent(int generation) =>
      !_disposed && generation == _suggestionRequestGeneration;

  bool _isCurrentVisibleSuggestion(OnlineShoppingSuggestion suggestion) =>
      suggestion.homeId == homeId &&
      suggestion.activeAt(_clock()) &&
      _state.suggestions.any((candidate) => candidate.id == suggestion.id);

  bool _matchesSuggestion(
    OnlineShoppingSuggestionExplanation explanation,
    OnlineShoppingSuggestion suggestion,
  ) =>
      explanation.homeId == homeId &&
      explanation.id == suggestion.id &&
      explanation.homeProductId == suggestion.homeProductId &&
      explanation.requiredQuantity.compareTo(suggestion.requiredQuantity) ==
          0 &&
      explanation.confidenceScore.compareTo(suggestion.confidenceScore) == 0 &&
      explanation.confidenceBand == suggestion.confidenceBand &&
      explanation.modelVersion == suggestion.modelVersion &&
      explanation.asOf == suggestion.asOf &&
      explanation.inputWatermark == suggestion.inputWatermark;

  void _hideSuggestion(String suggestionId) {
    _hiddenSuggestionIds.add(suggestionId);
    final explanations = <String, OnlineShoppingSuggestionExplanation>{
      ..._state.explanations,
    }..remove(suggestionId);
    _state = _copyState(
      suggestions: _state.suggestions
          .where((suggestion) => suggestion.id != suggestionId)
          .toList(growable: false),
      explanations: explanations,
      clearSafeError: true,
    );
    notifyListeners();
  }

  void _clearSuggestions(String message) {
    _suggestionRequestGeneration++;
    _state = ShoppingState(
      list: _state.list,
      loading: _state.loading,
      safeError: message,
      suggestions: const <OnlineShoppingSuggestion>[],
      suggestionsLoading: false,
      suggestionsFromVerifiedCache: false,
      explanations: const <String, OnlineShoppingSuggestionExplanation>{},
      suggestionsAccessDenied: _state.suggestionsAccessDenied,
    );
    notifyListeners();
  }

  void _handleSuggestionActionFailure(OnlineSuggestionException error) {
    if (error.kind == OnlineSuggestionFailureKind.authorizationDenied) {
      _denySuggestionAccess();
      return;
    }
    if (error.kind == OnlineSuggestionFailureKind.authenticationRequired ||
        error.kind == OnlineSuggestionFailureKind.invalidResponse) {
      _clearSuggestions(_suggestionFailureMessage(error.kind));
      return;
    }
    _setError(_suggestionFailureMessage(error.kind));
  }

  String _suggestionFailureMessage(OnlineSuggestionFailureKind kind) =>
      switch (kind) {
        OnlineSuggestionFailureKind.authenticationRequired =>
          'Sign in again before viewing online suggestions.',
        OnlineSuggestionFailureKind.authorizationDenied =>
          'Online suggestion access is no longer available for this home.',
        OnlineSuggestionFailureKind.invalidResponse =>
          'Online suggestions failed verification and were hidden.',
        OnlineSuggestionFailureKind.unavailable =>
          'Online suggestions are temporarily unavailable.',
      };

  void _denySuggestionAccess() {
    if (_disposed || _suggestionAuthorizationDenied) return;
    _suggestionAuthorizationDenied = true;
    _suggestionRequestGeneration++;
    _state = ShoppingState(
      list: _state.list,
      loading: _state.loading,
      safeError: _suggestionFailureMessage(
        OnlineSuggestionFailureKind.authorizationDenied,
      ),
      suggestions: const <OnlineShoppingSuggestion>[],
      suggestionsLoading: false,
      suggestionsFromVerifiedCache: false,
      explanations: const <String, OnlineShoppingSuggestionExplanation>{},
      suggestionsAccessDenied: true,
    );
    notifyListeners();
    final callback = _onAuthorizationDenied;
    if (callback != null && !_authorizationDenialReported) {
      _authorizationDenialReported = true;
      unawaited(_reportAuthorizationDenial(callback));
    }
  }

  Future<void> _reportAuthorizationDenial(
    Future<void> Function() callback,
  ) async {
    try {
      await callback();
    } on Object {
      // Authorization loss is already terminal locally. The application
      // boundary owns retry/routing and must not be invoked more than once.
    }
  }

  ShoppingState _copyState({
    ShoppingList? list,
    bool? loading,
    String? safeError,
    bool clearSafeError = false,
    List<OnlineShoppingSuggestion>? suggestions,
    bool? suggestionsLoading,
    bool? suggestionsFromVerifiedCache,
    DateTime? suggestionsVerifiedAt,
    Map<String, OnlineShoppingSuggestionExplanation>? explanations,
    bool? suggestionsAccessDenied,
  }) => ShoppingState(
    list: list ?? _state.list,
    loading: loading ?? _state.loading,
    safeError: clearSafeError ? null : safeError ?? _state.safeError,
    suggestions: suggestions ?? _state.suggestions,
    suggestionsLoading: suggestionsLoading ?? _state.suggestionsLoading,
    suggestionsFromVerifiedCache:
        suggestionsFromVerifiedCache ?? _state.suggestionsFromVerifiedCache,
    suggestionsVerifiedAt:
        suggestionsVerifiedAt ?? _state.suggestionsVerifiedAt,
    explanations: explanations ?? _state.explanations,
    suggestionsAccessDenied:
        suggestionsAccessDenied ?? _state.suggestionsAccessDenied,
  );

  void _setError(String message) {
    _state = _copyState(loading: false, safeError: message);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _suggestionRequestGeneration++;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

String _feedbackDecimal(double value) {
  if (!value.isFinite || value < 0) {
    throw ArgumentError.value(
      value,
      'value',
      'must be finite and non-negative',
    );
  }
  var text = value.toStringAsFixed(8);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
