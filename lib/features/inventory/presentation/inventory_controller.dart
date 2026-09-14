import 'package:providentia/core/security/intake_entity_id.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/inventory/application/home_location_repository.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/application/stock_preference_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/inventory/domain/inventory_services.dart';
import 'package:providentia/features/inventory/domain/stock_preference.dart';

final class InventoryViewState {
  const InventoryViewState({
    this.items = const <InventoryItem>[],
    this.criteria = const InventorySearchCriteria(),
    this.activeSession,
    this.loading = true,
    this.productCreationBusy = false,
    this.productCreationNotice,
    this.productCreationError,
    this.safeError,
  });

  final List<InventoryItem> items;
  final InventorySearchCriteria criteria;
  final StockCountSession? activeSession;
  final bool loading;
  final bool productCreationBusy;
  final String? productCreationNotice;
  final String? productCreationError;
  final String? safeError;
}

final class InventoryController extends ChangeNotifier {
  factory InventoryController({
    required InventoryRepository repository,
    required String homeId,
    bool mayManageStockPreferences = false,
    InventoryItemSearch search = const InventoryItemSearch(),
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) => InventoryController._(
    repository,
    homeId,
    search,
    clock ?? DateTime.now,
    idGenerator ?? UuidV4Generator().call,
    mayManageStockPreferences,
  );

  InventoryController._(
    InventoryRepository repository,
    this.homeId,
    this._search,
    this._clock,
    this._idGenerator,
    this.mayManageStockPreferences,
  ) : _repository = repository,
      _productCreationRepository =
          repository is InventoryProductCreationRepository ? repository : null;

  final bool mayManageStockPreferences;
  StockPreferenceRepository? get _stockPreferences =>
      _repository is StockPreferenceRepository
      ? _repository as StockPreferenceRepository
      : null;
  bool get canManageStockPreferences =>
      mayManageStockPreferences &&
      _stockPreferences?.supportsStockPreferences == true;

  Future<StockPreference> loadStockPreference(InventoryItem item) {
    if (!canManageStockPreferences || item.homeId != homeId) {
      throw StateError('Stock preference access is unavailable.');
    }
    return _stockPreferences!.loadStockPreference(
      homeId: homeId,
      productId: item.id,
    );
  }

  Future<void> saveStockPreference(StockPreference preference) {
    if (!canManageStockPreferences || preference.homeId != homeId) {
      throw StateError('Stock preference access is unavailable.');
    }
    return _stockPreferences!.saveStockPreference(preference);
  }

  final InventoryRepository _repository;
  final InventoryProductCreationRepository? _productCreationRepository;
  final InventoryItemSearch _search;
  final DateTime Function() _clock;
  final String Function() _idGenerator;
  final String homeId;
  StreamSubscription<List<InventoryItem>>? _itemsSubscription;
  StreamSubscription<StockCountSession?>? _sessionSubscription;
  InventoryViewState _state = const InventoryViewState();
  bool _started = false;
  StreamSubscription<List<HomeInventoryCategory>>? _categoriesSubscription;
  StreamSubscription<List<InventoryItem>>? _archivedSubscription;
  List<InventoryItem> _archivedProducts = const [];
  List<InventoryItem> get archivedProducts => _archivedProducts;
  List<HomeInventoryCategory> _categories = const [];
  List<HomeInventoryCategory> get homeCategories => _categories;
  InventoryMetadataRepository? get _metadata =>
      _repository is InventoryMetadataRepository
      ? _repository as InventoryMetadataRepository
      : null;
  bool get canEditMetadata => _metadata?.supportsInventoryMetadata == true;

  Future<bool> saveCategory({
    HomeInventoryCategory? category,
    required String name,
    bool archived = false,
  }) => _metadataMutation(
    () => _metadata!.saveHomeCategory(
      homeId: homeId,
      categoryId: category?.id,
      name: name,
      archived: archived,
      expectedRevision: category?.revision,
    ),
  );

  Future<bool> editProduct({
    required InventoryItem item,
    required String name,
    String? pack,
    String? categoryId,
    bool archived = false,
  }) => _metadataMutation(() async {
    if (item.homeId != homeId) {
      throw StateError('Product belongs to another home.');
    }
    await _metadata!.updateHomeProduct(
      homeId: homeId,
      productId: item.id,
      expectedRevision: item.revision,
      privateName: name,
      originalPackText: pack,
      homeCategoryId: categoryId,
      archived: archived,
    );
  });

  Future<bool> _metadataMutation(Future<void> Function() action) async {
    if (!canEditMetadata) return false;
    try {
      await action();
      return true;
    } catch (_) {
      _setProductCreationError(
        'The change could not be saved. Refresh and try again.',
      );
      return false;
    }
  }

  StreamSubscription<List<HomeLocation>>? _locationsSubscription;
  List<HomeLocation> _locations = const [];
  List<HomeLocation> get locations => _locations;
  HomeLocationRepository? get _locationsRepository =>
      _repository is HomeLocationRepository
      ? _repository as HomeLocationRepository
      : null;
  bool get canEditLocations =>
      _locationsRepository?.supportsHomeLocations == true;

  Future<bool> saveLocation({
    String? id,
    required String name,
    required String kind,
    required bool archived,
    int? expectedRevision,
  }) async {
    if (!canEditLocations) return false;
    try {
      await _locationsRepository!.saveHomeLocation(
        homeId: homeId,
        locationId: id,
        name: name,
        kind: kind,
        archived: archived,
        expectedRevision: expectedRevision,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  InventoryViewState get state => _state;
  bool get canCreatePrivateProduct =>
      _productCreationRepository?.supportsPrivateHomeProductCreation == true;
  bool get canAddCatalogProduct =>
      _productCreationRepository?.supportsCatalogHomeProductCreation == true;

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
    _locationsSubscription = _locationsRepository
        ?.watchHomeLocations(homeId)
        .listen(
          (rows) {
            _locations = List.unmodifiable(rows);
            notifyListeners();
          },
          onError: (Object _) {
            _locations = const [];
            _setSafeError('Locations could not be loaded.');
          },
        );
    _archivedSubscription = _metadata?.watchArchivedHomeProducts(homeId).listen(
      (items) {
        if (items.any((item) => item.homeId != homeId)) {
          _setSafeError('Archived product access was rejected.');
          return;
        }
        _archivedProducts = List.unmodifiable(items);
        notifyListeners();
      },
      onError: (Object _) =>
          _setSafeError('Archived products could not be loaded.'),
    );
    _categoriesSubscription = _metadata?.watchHomeCategories(homeId).listen((
      rows,
    ) {
      _categories = List.unmodifiable(rows);
      notifyListeners();
    }, onError: (Object _) => _setSafeError('Categories could not be loaded.'));

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
          productCreationBusy: _state.productCreationBusy,
          productCreationNotice: _state.productCreationNotice,
          productCreationError: _state.productCreationError,
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
                productCreationBusy: _state.productCreationBusy,
                productCreationNotice: _state.productCreationNotice,
                productCreationError: _state.productCreationError,
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

  Future<bool> createPrivateProduct({
    required String privateName,
    String? originalPackText,
    String? homeCategoryId,
  }) async {
    final repository = _productCreationRepository;
    if (repository == null || !repository.supportsPrivateHomeProductCreation) {
      _setProductCreationError(
        'Private product creation is unavailable in this workspace.',
      );
      return false;
    }
    if (_state.productCreationBusy) return false;
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: _state.criteria,
        activeSession: _state.activeSession,
        loading: _state.loading,
        productCreationBusy: true,
        productCreationNotice: _state.productCreationNotice,
        safeError: _state.safeError,
      ),
    );
    try {
      final result = await repository.createPrivateHomeProduct(
        PrivateHomeProductDraft(
          homeId: homeId,
          privateName: privateName,
          originalPackText: originalPackText,
          homeCategoryId: homeCategoryId,
        ),
      );
      _setState(
        InventoryViewState(
          items: _state.items,
          criteria: _state.criteria,
          activeSession: _state.activeSession,
          loading: _state.loading,
          productCreationNotice: result.awaitsServerConfirmation
              ? 'The private product is saved locally and queued; server confirmation is pending.'
              : 'The private product is synchronized.',
          safeError: _state.safeError,
        ),
      );
      return true;
    } on InventoryProductCreationException catch (error) {
      _setProductCreationError(error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _setProductCreationError('Check the private product name and pack text.');
      return false;
    } catch (_) {
      _setProductCreationError(
        'The private product could not be saved safely.',
      );
      return false;
    }
  }

  Future<bool> addCatalogProduct(InventoryItem item) async {
    final repository = _productCreationRepository;
    if (repository == null || !repository.supportsCatalogHomeProductCreation) {
      _setProductCreationError(
        'Catalog product selection is unavailable in this workspace.',
      );
      return false;
    }
    if (item.homeId != homeId || item.isHomeProduct) {
      _setProductCreationError('Choose an unselected catalog product.');
      return false;
    }
    if (_state.productCreationBusy) return false;
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: _state.criteria,
        activeSession: _state.activeSession,
        loading: _state.loading,
        productCreationBusy: true,
        productCreationNotice: _state.productCreationNotice,
        safeError: _state.safeError,
      ),
    );
    try {
      final result = await repository.createCatalogHomeProduct(
        CatalogHomeProductDraft.fromItem(item),
      );
      _setState(
        InventoryViewState(
          items: _state.items,
          criteria: _state.criteria,
          activeSession: _state.activeSession,
          loading: _state.loading,
          productCreationNotice: result.awaitsServerConfirmation
              ? 'The catalog product is added locally and queued; server confirmation is pending.'
              : 'The catalog product is synchronized.',
          safeError: _state.safeError,
        ),
      );
      return true;
    } on InventoryProductCreationException catch (error) {
      _setProductCreationError(error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _setProductCreationError('Refresh the item master and choose again.');
      return false;
    } catch (_) {
      _setProductCreationError(
        'The catalog product could not be added safely.',
      );
      return false;
    }
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
    final lineId =
        session.lines.where((line) => line.itemId == item.id).firstOrNull?.id ??
        _idGenerator();
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

  /// Records a human-confirmed photo proposal through the same ordinary
  /// count-line repository boundary used by manual counts. The photo reference
  /// is deliberately opaque and ephemeral; image bytes never enter inventory
  /// projections or the synchronization outbox.
  Future<void> recordPhotoCount({
    required InventoryItem item,
    required double observedQuantity,
    required String proposalId,
  }) async {
    final session = _state.activeSession;
    if (session == null || session.status != CountSessionStatus.open) {
      throw StateError('Start a count session before recording photo counts.');
    }
    if (item.homeId != homeId || !item.isHomeProduct) {
      throw StateError('Photo counts require a product in the active home.');
    }
    if (!observedQuantity.isFinite || observedQuantity < 0) {
      throw ArgumentError.value(
        observedQuantity,
        'observedQuantity',
        'must be finite and non-negative',
      );
    }
    final photoId = proposalId.trim();
    if (photoId.isEmpty) {
      throw ArgumentError.value(proposalId, 'proposalId', 'must not be empty');
    }
    final lineId = intakeEntityId(<String>[
      'stock-line',
      homeId,
      session.id,
      photoId,
    ]);
    final prior = session.lines.where((line) => line.id == lineId).firstOrNull;
    if (prior != null) {
      if (prior.itemId != item.id)
        throw StateError(
          'This reviewed candidate was already matched differently.',
        );
      return;
    }
    final withPhoto = session.attachPhoto(
      StockPhotoReference(
        id: photoId,
        localReference: 'ephemeral://stock-photo-review',
        addedAt: _clock().toUtc(),
      ),
    );
    final updated = withPhoto.recordLine(
      StockCountLine(
        id: lineId,
        itemId: item.id,
        status: CountLineStatus.confirmed,
        source: CountSource.photo,
        observedQuantity: observedQuantity,
        photoId: photoId,
      ),
    );
    await saveSession(updated);
    // Keep only non-sensitive ordinary count data in presentation state. The
    // stock-photo controller retains previews until explicit close/cancel.
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: _state.criteria,
        activeSession: StockCountSession(
          id: updated.id,
          homeId: updated.homeId,
          locationId: updated.locationId,
          startedAt: updated.startedAt,
          status: updated.status,
          closedAt: updated.closedAt,
          lines: updated.lines,
        ),
        loading: _state.loading,
        productCreationBusy: _state.productCreationBusy,
        productCreationNotice: _state.productCreationNotice,
        productCreationError: _state.productCreationError,
        safeError: _state.safeError,
      ),
    );
  }

  Future<void> removeCountForItem(InventoryItem item) async {
    final session = _state.activeSession;
    if (session == null || item.homeId != homeId) {
      throw StateError('An open count in the active home is required.');
    }
    final line = session.lines
        .where((line) => line.itemId == item.id)
        .firstOrNull;
    if (line == null) throw StateError('The count line is unavailable.');
    await saveSession(session.removeLine(line.id));
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
        productCreationBusy: _state.productCreationBusy,
        productCreationNotice: _state.productCreationNotice,
        productCreationError: _state.productCreationError,
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
        productCreationBusy: _state.productCreationBusy,
        productCreationNotice: _state.productCreationNotice,
        productCreationError: _state.productCreationError,
        safeError: message,
      ),
    );
  }

  void _setProductCreationError(String message) {
    _setState(
      InventoryViewState(
        items: _state.items,
        criteria: _state.criteria,
        activeSession: _state.activeSession,
        loading: _state.loading,
        productCreationNotice: _state.productCreationNotice,
        productCreationError: message,
        safeError: _state.safeError,
      ),
    );
  }

  void _setState(InventoryViewState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _locationsSubscription?.cancel();
    unawaited(_archivedSubscription?.cancel());
    unawaited(_categoriesSubscription?.cancel());
    unawaited(_itemsSubscription?.cancel());
    unawaited(_sessionSubscription?.cancel());
    super.dispose();
  }
}
