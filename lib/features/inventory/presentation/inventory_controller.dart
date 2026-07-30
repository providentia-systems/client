import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';

final class InventoryViewState {
  const InventoryViewState({
    this.items = const <InventoryItem>[],
    this.criteria = const InventorySearchCriteria(),
    this.activeSession,
    this.loading = true,
    this.safeError,
  });

  final List<InventoryItem> items;
  final InventorySearchCriteria criteria;
  final StockCountSession? activeSession;
  final bool loading;
  final String? safeError;
}

final class InventoryController extends ChangeNotifier {
  factory InventoryController({
    required InventoryRepository repository,
    required String homeId,
    InventoryItemSearch search = const InventoryItemSearch(),
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => InventoryController._(
    repository,
    homeId,
    search,
    clock ?? DateTime.now,
    idGenerator ?? (() => DateTime.now().microsecondsSinceEpoch.toString()),
  );

  InventoryController._(
    this._repository,
    this.homeId,
    this._search,
    this._clock,
    this._idGenerator,
  );

  final InventoryRepository _repository;
  final InventoryItemSearch _search;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final String homeId;
  StreamSubscription<List<InventoryItem>>? _itemsSubscription;
  StreamSubscription<StockCountSession?>? _sessionSubscription;
  InventoryViewState _state = const InventoryViewState();
  bool _started = false;

  InventoryViewState get state => _state;

  List<InventoryItem> get visibleItems => _search.filter(
    _state.items,
    InventorySearchCriteria(
      query: _state.criteria.query,
      category: _state.criteria.category,
      view: _state.criteria.view,
      confirmedItemIds: _confirmedItemIds,
    ),
  );

  void start() {
    if (_started) return;
    _started = true;
    _itemsSubscription = _repository.watchItems(homeId: homeId).listen((items) {
      if (items.any((item) => item.homeId != homeId)) {
        _setSafeError('Inventory access was rejected.');
        return;
      }
      _setState(
        InventoryViewState(
          items: List<InventoryItem>.unmodifiable(items),
          criteria: _state.criteria,
          activeSession: _state.activeSession,
          loading: false,
        ),
      );
    }, onError: (Object _) => _setSafeError('Inventory could not be loaded.'));
    _sessionSubscription = _repository
        .watchActiveCountSession(homeId: homeId)
        .listen(
          (session) {
            if (session != null && session.homeId != homeId) {
              _setSafeError('Count-session access was rejected.');
              return;
            }
            _setState(
              InventoryViewState(
                items: _state.items,
                criteria: _state.criteria,
                activeSession: session,
                loading: _state.loading,
              ),
            );
          },
          onError: (Object _) =>
              _setSafeError('The count session could not be loaded.'),
        );
  }

  void updateSearch(String query) => _updateCriteria(
    InventorySearchCriteria(
      query: query,
      category: _state.criteria.category,
      view: _state.criteria.view,
      confirmedItemIds: _confirmedItemIds,
    ),
  );

  void selectCategory(String? category) => _updateCriteria(
    InventorySearchCriteria(
      query: _state.criteria.query,
      category: category,
      view: _state.criteria.view,
      confirmedItemIds: _confirmedItemIds,
    ),
  );

  void selectView(InventoryView view) => _updateCriteria(
    InventorySearchCriteria(
      query: '',
      view: view,
      confirmedItemIds: _confirmedItemIds,
    ),
  );

  Future<void> adjustQuantity({
    required InventoryItem item,
    required String locationId,
    required double observedQuantity,
    required String reason,
  }) async {
    final intentId = _idGenerator();
    final intent = ManualAdjustmentIntent(
      id: intentId,
      homeId: homeId,
      itemId: item.id,
      locationId: locationId,
      projectedQuantity: item.currentQuantity ?? 0.0,
      observedQuantity: observedQuantity,
      reason: reason,
      createdAt: _clock().toUtc(),
    );
    await _repository.commitManualAdjustment(
      intent: intent,
      movement: intent.toMovement('${intentId}_movement'),
    );
  }

  Future<void> saveSession(StockCountSession session) {
    if (session.homeId != homeId) {
      throw StateError('Cannot save a count session for another home.');
    }
    return _repository.saveCountSession(session);
  }

  Future<void> startCount({String locationId = 'primary'}) {
    if (_state.activeSession != null) {
      throw StateError(
        'Finish or cancel the active count before starting one.',
      );
    }
    return saveSession(
      StockCountSession(
        id: _idGenerator(),
        homeId: homeId,
        locationId: locationId,
        startedAt: _clock().toUtc(),
      ),
    );
  }

  Future<void> recordManualCount({
    required InventoryItem item,
    required double observedQuantity,
  }) {
    final session = _state.activeSession;
    if (session == null) {
      throw StateError('Start a count session before recording quantities.');
    }
    final lineId = 'manual:${session.id}:${item.id}';
    return saveSession(
      session.recordLine(
        StockCountLine(
          id: lineId,
          itemId: item.id,
          status: CountLineStatus.confirmed,
          source: CountSource.manual,
          observedQuantity: observedQuantity,
        ),
      ),
    );
  }

  Future<void> closeCount() {
    final session = _state.activeSession;
    if (session == null) {
      throw StateError('There is no active count to close.');
    }
    return saveSession(session.close(_clock().toUtc()));
  }

  Future<void> cancelCount() {
    final session = _state.activeSession;
    if (session == null) {
      throw StateError('There is no active count to cancel.');
    }
    return saveSession(session.cancel());
  }

  Set<String> get _confirmedItemIds =>
      _state.activeSession?.confirmedLines.map((line) => line.itemId).toSet() ??
      const <String>{};

  void _updateCriteria(InventorySearchCriteria criteria) {
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: criteria,
        activeSession: _state.activeSession,
        loading: _state.loading,
      ),
    );
  }

  void _setSafeError(String message) {
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: _state.criteria,
        activeSession: _state.activeSession,
        loading: false,
        safeError: message,
      ),
    );
  }

  void _setState(InventoryViewState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_itemsSubscription?.cancel());
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }
}
