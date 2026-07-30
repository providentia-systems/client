import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/shopping/application/shopping_repository.dart';
import 'package:providentia/features/shopping/domain/shopping_models.dart';

final class ShoppingState {
  const ShoppingState({this.list, this.loading = true, this.safeError});

  final ShoppingList? list;
  final bool loading;
  final String? safeError;
}

final class ShoppingController extends ChangeNotifier {
  factory ShoppingController({
    required ShoppingRepository repository,
    required String homeId,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => ShoppingController._(
    repository,
    homeId,
    clock ?? DateTime.now,
    idGenerator ?? (() => DateTime.now().microsecondsSinceEpoch.toString()),
  );

  ShoppingController._(
    this._repository,
    this.homeId,
    this._clock,
    this._idGenerator,
  );

  final ShoppingRepository _repository;
  final String homeId;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  StreamSubscription<ShoppingList>? _subscription;
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
        _state = ShoppingState(list: list, loading: false);
        notifyListeners();
      },
      onError: (Object _) =>
          _setError('The shopping list could not be loaded.'),
    );
  }

  Future<void> addManual(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = _requireList();
    await _repository.saveList(
      list.add(
        ShoppingListLine(
          id: _idGenerator(),
          homeId: homeId,
          name: trimmed,
          quantity: 1,
          origin: ShoppingLineOrigin.manual,
          createdAt: _clock().toUtc(),
        ),
      ),
    );
  }

  Future<void> toggle(String lineId) =>
      _repository.saveList(_requireList().toggle(lineId));

  Future<void> updateQuantity(String lineId, double quantity) =>
      _repository.saveList(_requireList().updateQuantity(lineId, quantity));

  Future<void> recordFeedback(SuggestionFeedback feedback) {
    if (feedback.homeId != homeId) {
      throw StateError('Cannot record feedback for another home.');
    }
    return _repository.recordFeedback(feedback);
  }

  ShoppingList _requireList() {
    final list = _state.list;
    if (list == null) {
      throw StateError('The active shopping list is not loaded.');
    }
    return list;
  }

  void _setError(String message) {
    _state = ShoppingState(
      list: _state.list,
      loading: false,
      safeError: message,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
