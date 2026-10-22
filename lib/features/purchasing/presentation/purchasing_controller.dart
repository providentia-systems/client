import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/application/purchase_draft_maintenance_repository.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/application/purchase_store_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
import 'package:providentia/features/purchasing/domain/purchase_quantity.dart';
import 'package:providentia/features/purchasing/domain/purchase_services.dart';

enum PurchaseView { recent, history }

final class PurchasingState {
  const PurchasingState({
    this.lines = const <PurchaseLine>[],
    this.matchCandidates = const <PurchaseMatchCandidate>[],
    this.view = PurchaseView.recent,
    this.loading = true,
    this.captureBusy = false,
    this.capture,
    this.captureNotice,
    this.captureError,
    this.safeError,
  });

  final List<PurchaseLine> lines;
  final List<PurchaseMatchCandidate> matchCandidates;
  final PurchaseView view;
  final bool loading;
  final bool captureBusy;
  final PurchaseReceiptCapture? capture;
  final String? captureNotice;
  final String? captureError;
  final String? safeError;
}

final class PurchasingController extends ChangeNotifier {
  factory PurchasingController({
    required PurchaseRepository repository,
    required String homeId,
    bool mayWrite = false,
    PurchaseHistoryGrouper grouper = const PurchaseHistoryGrouper(),
    PurchaseMatchRanker matchRanker = const PurchaseMatchRanker(),
    InventoryProductCreationRepository? productCreationRepository,
    Future<SyncSummary> Function()? synchronize,
    VoidCallback? onReviewSynchronization,
  }) => PurchasingController._(
    repository,
    homeId,
    mayWrite,
    grouper,
    matchRanker,
    productCreationRepository,
    synchronize,
    onReviewSynchronization,
  );

  PurchasingController._(
    PurchaseRepository repository,
    this.homeId,
    this._mayWrite,
    this._grouper,
    this._matchRanker,
    this._productCreationRepository,
    this._synchronize,
    this._onReviewSynchronization,
  ) : _repository = repository,
      _captureRepository = repository is PurchaseCaptureRepository
          ? repository
          : null;

  final Future<SyncSummary> Function()? _synchronize;
  final VoidCallback? _onReviewSynchronization;
  bool get canReviewSynchronization => _onReviewSynchronization != null;
  void reviewSynchronization() => _onReviewSynchronization?.call();
  Future<void>? _synchronizationAttempt;
  SyncSummary? _synchronizationSummary;
  bool _disposed = false;
  final Map<String, String> _receiptErrors = {};

  bool get synchronizationBusy =>
      _synchronizationAttempt != null ||
      _synchronizationSummary?.isSynchronizing == true;
  bool get canRetrySynchronization => _synchronize != null;
  SyncSummary? get synchronizationSummary => _synchronizationSummary;

  /// Current household work can precede this receipt in the durable queue.
  String? get receiptSynchronizationNotice {
    final capture = _state.capture;
    if (capture == null) return null;
    final summary = _synchronizationSummary;
    if (synchronizationBusy) {
      return 'Synchronizing… Household dependencies are processed before this receipt.';
    }
    if (capture.commitConfirmed && capture.commitAwaitingReadback) {
      return 'Server confirmed; receipt details are refreshing. Local stock application and server readback are separate.'
          '${summary?.lastSafeError == null ? '' : ' ${summary!.lastSafeError} Review synchronization to continue refreshing safely.'}';
    }
    if (capture.synchronizationState ==
        PurchaseSynchronizationState.synchronized) {
      return capture.status == PurchaseReceiptStatus.committed
          ? 'Receipt and line details are synchronized.'
          : null;
    }
    if (summary == null) {
      return 'Saved on this device; awaiting server confirmation.';
    }
    final waiting = summary.unresolved;
    final prefix = waiting > 0
        ? '$waiting saved operation${waiting == 1 ? '' : 's'} remain unresolved. '
        : '';
    if (summary.blocked > 0) {
      return '${prefix}First blocker: ${syncOperationLabel(summary.blockedOperationType)}. ${summary.lastSafeError ?? 'A preceding household change needs review.'} '
          '${syncRecoveryInstruction(summary.failureCode)} '
          'Review Home synchronization for the first blocker; later queued operations are waiting, not separate failures.';
    }
    if (summary.availability == SyncAvailability.offline) {
      return '${prefix}Saved on this device; reconnect before retrying.';
    }
    if (summary.availability == SyncAvailability.authenticationRequired) {
      return '${prefix}Sign in again using the original account. Your saved work is preserved.';
    }
    if (summary.lastSafeError != null) {
      return '$prefix${summary.lastSafeError} Saved receipt data is preserved; retry safely from this receipt or Home.';
    }
    return '${prefix}Saved on this device; awaiting server confirmation. Retry synchronization to process household dependencies and refresh receipt details.';
  }

  void updateSynchronizationSummary(SyncSummary summary) {
    if (_disposed) return;
    _synchronizationSummary = summary;
    _notifyIfActive();
  }

  /// Retry observes real household synchronization; it never submits another
  /// purchase or changes the original commit/operation identities.
  Future<void> retrySynchronization() {
    final active = _synchronizationAttempt;
    if (active != null) return active;
    final synchronize = _synchronize;
    if (_disposed || synchronize == null) return Future<void>.value();
    final completer = Completer<void>();
    _synchronizationAttempt = completer.future;
    _notifyIfActive();
    unawaited(() async {
      try {
        final summary = await synchronize();
        if (!_disposed) _synchronizationSummary = summary;
      } catch (_) {
        if (!_disposed) {
          _synchronizationSummary =
              (_synchronizationSummary ?? const SyncSummary.initial()).copyWith(
                availability: SyncAvailability.temporarilyUnavailable,
                lastSafeError: 'Synchronization was interrupted. Retry safely.',
                failureCode: 'service_unavailable',
              );
        }
      } finally {
        _synchronizationAttempt = null;
        _notifyIfActive();
        completer.complete();
      }
    }());
    return completer.future;
  }

  final PurchaseRepository _repository;
  final PurchaseCaptureRepository? _captureRepository;
  final PurchaseHistoryGrouper _grouper;
  final PurchaseMatchRanker _matchRanker;
  final InventoryProductCreationRepository? _productCreationRepository;
  final bool _mayWrite;
  final String homeId;
  StreamSubscription<List<PurchaseLine>>? _subscription;
  StreamSubscription<PurchaseReceiptCapture?>? _captureSubscription;
  StreamSubscription<List<PurchaseReceiptCapture>>? _receiptsSubscription;
  List<PurchaseReceiptCapture> _receipts = const [];
  String? _selectedReceiptId;
  List<PurchaseReceiptCapture> get receipts => _receipts;
  bool get canSelectReceipts =>
      _repository is PurchaseReceiptSelectionRepository;
  bool get canReviewPacks => _repository is PurchasePackReviewRepository;
  bool get canQuickEntry =>
      captureEnabled && _repository is PurchaseQuickEntryRepository;

  void selectReceipt(String receiptId) {
    _selectedReceiptId = receiptId;
    for (final receipt in _receipts) {
      if (receipt.id == receiptId) {
        _receiveCapture(receipt);
        return;
      }
    }
  }

  void startAnotherReceipt() {
    _selectedReceiptId = '';
    _receiveCapture(null);
  }

  StreamSubscription<List<PurchaseMatchCandidate>>? _candidateSubscription;
  StreamSubscription<List<InventoryItem>>? _itemMasterSubscription;
  List<PurchaseMatchCandidate> _legacyMatchCandidates =
      const <PurchaseMatchCandidate>[];
  bool _itemMasterVerified = false;
  bool _captureReadFailed = false;
  final Map<String, String> _createdHomeProductIds = <String, String>{};
  PurchasingState _state = const PurchasingState();

  StreamSubscription<List<PurchaseStore>>? _storesSubscription;
  List<PurchaseStore> _stores = const [];
  List<PurchaseStore> get stores => _stores;
  PurchaseStoreRepository? get _storesRepository =>
      _repository is PurchaseStoreRepository
      ? _repository as PurchaseStoreRepository
      : null;
  bool get canEditStores =>
      _mayWrite && _storesRepository?.supportsPurchaseStores == true;

  Future<bool> saveStore({
    String? id,
    required String name,
    required String location,
    required bool archived,
    int? expectedRevision,
  }) async {
    if (!canEditStores) return false;
    try {
      await _storesRepository!.savePurchaseStore(
        homeId: homeId,
        storeId: id,
        name: name,
        location: location,
        archived: archived,
        expectedRevision: expectedRevision,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  PurchasingState get state => _state;
  List<PurchaseGroup> get recentGroups =>
      _grouper.groupRecent(homeId: homeId, lines: _state.lines);
  List<MonthlyPurchaseSummary> get monthlyHistory =>
      _grouper.summarizeHistory(homeId: homeId, lines: _state.lines);
  Money? get recentSpend =>
      _grouper.recentSpend(homeId: homeId, lines: _state.lines);
  bool get captureEnabled => _mayWrite && _captureRepository != null;
  bool get canAddPublishedPack =>
      captureEnabled &&
      _productCreationRepository?.supportsCatalogHomeProductCreation == true;
  bool get canCreatePrivateProduct =>
      captureEnabled &&
      _productCreationRepository?.supportsPrivateHomeProductCreation == true;

  List<RankedPurchaseMatchCandidate> rankedCandidatesFor(
    PurchaseReceiptLineCapture line,
  ) => _matchRanker.rank(line: line, candidates: _state.matchCandidates);

  void start() {
    if (_subscription != null) return;
    _storesSubscription = _storesRepository
        ?.watchPurchaseStores(homeId)
        .listen(
          (rows) {
            _stores = List.unmodifiable(rows);
            _notifyIfActive();
          },
          onError: (Object _) {
            _stores = const [];
            _setCaptureError('Stores could not be loaded.');
          },
        );
    _subscription = _repository
        .watchPurchaseLines(homeId: homeId)
        .listen(
          (lines) {
            if (lines.any((line) => line.homeId != homeId)) {
              _state = PurchasingState(
                lines: _state.lines,
                matchCandidates: _state.matchCandidates,
                view: _state.view,
                loading: false,
                captureBusy: _state.captureBusy,
                capture: _state.capture,
                captureNotice: _state.captureNotice,
                captureError: _state.captureError,
                safeError: 'Purchase-history access was rejected.',
              );
              _notifyIfActive();
              return;
            }
            _state = PurchasingState(
              lines: List<PurchaseLine>.unmodifiable(lines),
              matchCandidates: _state.matchCandidates,
              view: _state.view,
              loading: false,
              captureBusy: _state.captureBusy,
              capture: _state.capture,
              captureNotice: _state.captureNotice,
              captureError: _state.captureError,
            );
            _notifyIfActive();
          },
          onError: (Object _) {
            _state = PurchasingState(
              lines: _state.lines,
              matchCandidates: _state.matchCandidates,
              view: _state.view,
              loading: false,
              captureBusy: _state.captureBusy,
              capture: _state.capture,
              captureNotice: _state.captureNotice,
              captureError: _state.captureError,
              safeError: 'Purchase history could not be loaded.',
            );
            _notifyIfActive();
          },
        );
    final captureRepository = _captureRepository;
    if (!captureEnabled || captureRepository == null) return;
    if (_repository is PurchaseReceiptSelectionRepository) {
      _receiptsSubscription =
          (_repository as PurchaseReceiptSelectionRepository)
              .watchReceiptCaptures(homeId: homeId)
              .listen(
                (receipts) {
                  if (receipts.any((receipt) => receipt.homeId != homeId)) {
                    _setCaptureError('Purchase capture access was rejected.');
                    return;
                  }
                  _receipts = List.unmodifiable(receipts);
                  PurchaseReceiptCapture? selected;
                  for (final receipt in receipts) {
                    if (receipt.id == _selectedReceiptId) selected = receipt;
                  }
                  selected ??= _selectedReceiptId == null && receipts.isNotEmpty
                      ? receipts.first
                      : null;
                  if (_selectedReceiptId == null && selected != null) {
                    _selectedReceiptId = selected.id;
                  }
                  _receiveCapture(selected);
                },
                onError: (Object error) {
                  _captureReadFailed = true;
                  _setCaptureError(_captureSafeError(error));
                },
              );
    } else {
      _captureSubscription = captureRepository
          .watchActiveReceiptCapture(homeId: homeId)
          .listen(
            _receiveCapture,
            onError: (Object error) {
              _captureReadFailed = true;
              _setCaptureError(_captureSafeError(error));
            },
          );
    }
    _candidateSubscription = captureRepository
        .watchPurchaseMatchCandidates(homeId: homeId)
        .listen(
          (candidates) {
            if (candidates.any((candidate) => candidate.homeId != homeId)) {
              _setCaptureError('Purchase product access was rejected.');
              return;
            }
            _legacyMatchCandidates = List<PurchaseMatchCandidate>.unmodifiable(
              candidates,
            );
            if (!_itemMasterVerified) {
              _replaceMatchCandidates(_legacyMatchCandidates);
            }
          },
          onError: (Object error) {
            _setCaptureError(_captureSafeError(error));
          },
        );
    final productRepository = _productCreationRepository;
    if (productRepository != null) {
      _itemMasterSubscription = productRepository
          .watchItems(homeId: homeId)
          .listen(
            (items) {
              if (items.any((item) => item.homeId != homeId)) {
                _setCaptureError('Purchase product access was rejected.');
                return;
              }
              _itemMasterVerified = true;
              _replaceMatchCandidates(_projectItemMasterCandidates(items));
            },
            onError: (Object _) {
              _setCaptureError(
                'The verified offline item master remains available; product refresh failed.',
              );
            },
          );
    }
  }

  void _receiveCapture(PurchaseReceiptCapture? capture) {
    if (capture != null && capture.homeId != homeId) {
      _setCaptureError('Purchase capture access was rejected.');
      return;
    }
    final previous = _state.capture;
    final sameReceipt = capture != null && previous?.id == capture.id;
    final confirmed =
        capture != null &&
        sameReceipt &&
        previous!.commitAwaitingReadback &&
        capture.synchronizationState ==
            PurchaseSynchronizationState.synchronized;
    if (_captureReadFailed && sameReceipt) _receiptErrors.remove(capture.id);
    _state = PurchasingState(
      lines: _state.lines,
      matchCandidates: _state.matchCandidates,
      view: _state.view,
      loading: _state.loading,
      captureBusy: _state.captureBusy,
      capture: capture,
      captureNotice: capture == null
          ? null
          : confirmed
          ? 'The receipt commit is synchronized.'
          : capture.commitConfirmed && capture.commitAwaitingReadback
          ? 'The server confirmed the receipt commit. Receipt details are refreshing.'
          : capture.synchronizationState == PurchaseSynchronizationState.pending
          ? 'Saved on this device; awaiting server confirmation.'
          : null,
      captureError: capture == null ? null : _receiptErrors[capture.id],
      safeError: _state.safeError,
    );
    _captureReadFailed = false;
    _notifyIfActive();
  }

  void selectView(PurchaseView view) {
    if (_state.view == view) return;
    _state = PurchasingState(
      lines: _state.lines,
      matchCandidates: _state.matchCandidates,
      view: view,
      loading: _state.loading,
      captureBusy: _state.captureBusy,
      capture: _state.capture,
      captureNotice: _state.captureNotice,
      captureError: _state.captureError,
      safeError: _state.safeError,
    );
    _notifyIfActive();
  }

  PurchaseDraftMaintenanceRepository? get _draftMaintenance =>
      _repository is PurchaseDraftMaintenanceRepository
      ? _repository as PurchaseDraftMaintenanceRepository
      : null;
  bool get canMaintainDraft => captureEnabled && _draftMaintenance != null;

  Future<bool> updateDraft({
    required PurchaseReceiptCapture original,
    required DateTime purchaseDate,
    required String currency,
    String? storeId,
    Money? total,
    String notes = '',
  }) {
    if (!canMaintainDraft) {
      return _rejectCapture('Receipt editing is unavailable.');
    }
    return _runCaptureMutation(
      () => _draftMaintenance!.updateReceiptDraft(
        receiptId: original.id,
        expectedRevision: original.revision,
        draft: PurchaseReceiptDraftRequest(
          homeId: homeId,
          purchaseDate: purchaseDate,
          currency: currency,
          storeId: storeId,
          total: total,
          notes: notes,
        ),
      ),
      queuedNotice:
          'Receipt changes are saved locally and queued for synchronization.',
    );
  }

  Future<bool> updateLine({
    required PurchaseReceiptLineCapture original,
    required String rawDescription,
    required double quantity,
    String? quantityText,
    String? originalPackText,
    Money? unitPrice,
    Money? lineTotal,
  }) {
    if (!canMaintainDraft) {
      return _rejectCapture('Receipt editing is unavailable.');
    }
    return _runCaptureMutation(
      () => _draftMaintenance!.updateReceiptDraftLine(
        lineId: original.id,
        expectedRevision: original.revision,
        line: PurchaseReceiptLineRequest(
          homeId: homeId,
          receiptId: original.receiptId,
          rawDescription: rawDescription,
          quantity: quantity,
          quantityText: quantityText,
          originalPackText: originalPackText,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        ),
      ),
      queuedNotice: original.stockApplied
          ? 'Purchase corrected. Stock is updated locally; synchronization is pending.'
          : 'Line changes are saved locally. Review the edited line before committing.',
    );
  }

  Future<bool> removeLine(PurchaseReceiptLineCapture original) {
    if (!canMaintainDraft) {
      return _rejectCapture('Receipt editing is unavailable.');
    }
    return _runCaptureMutation(
      () => _draftMaintenance!.removeReceiptDraftLine(
        homeId: homeId,
        receiptId: original.receiptId,
        lineId: original.id,
        expectedRevision: original.revision,
      ),
      queuedNotice:
          'Line removal is saved locally and queued for synchronization.',
    );
  }

  Future<bool> cancelDraft(PurchaseReceiptCapture original) {
    if (!canMaintainDraft) {
      return _rejectCapture('Receipt editing is unavailable.');
    }
    return _runCaptureMutation(
      () => _draftMaintenance!.cancelReceiptDraft(
        homeId: homeId,
        receiptId: original.id,
        expectedRevision: original.revision,
      ),
      queuedNotice:
          'Draft cancellation is saved locally and queued for synchronization.',
    );
  }

  Future<bool> createDraft({
    required DateTime purchaseDate,
    required String currency,
    String? storeId,
    Money? total,
    String notes = '',
    String? sourceReference,
  }) {
    return _runCaptureMutation(
      () => _captureRepository!.createReceiptDraft(
        PurchaseReceiptDraftRequest(
          homeId: homeId,
          storeId: storeId,
          purchaseDate: purchaseDate,
          currency: currency,
          total: total,
          notes: notes,
          sourceReference: sourceReference,
        ),
      ),
      onResult: (result) => selectReceipt(result.entityId),
      queuedNotice:
          'The draft is saved locally and queued for synchronization.',
    );
  }

  Future<bool> addLine({
    required String rawDescription,
    required double quantity,
    String? quantityText,
    String? originalPackText,
    Money? unitPrice,
    Money? lineTotal,
  }) {
    final capture = _state.capture;
    if (capture == null || capture.status != PurchaseReceiptStatus.draft) {
      return _rejectCapture('Start a draft receipt before adding a line.');
    }
    return _runCaptureMutation(
      () => _captureRepository!.addReceiptLine(
        PurchaseReceiptLineRequest(
          homeId: homeId,
          receiptId: capture.id,
          rawDescription: rawDescription,
          quantity: quantity,
          quantityText: quantityText,
          originalPackText: originalPackText,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        ),
      ),
      queuedNotice:
          'The receipt line is saved locally and queued for synchronization.',
    );
  }

  Future<bool> addPurchasedLine({
    required String homeProductId,
    String? packId,
    required String rawDescription,
    required String quantityText,
    String? originalPackText,
    Money? unitPrice,
    Money? lineTotal,
  }) {
    final receipt = _state.capture;
    if (!canQuickEntry ||
        receipt == null ||
        receipt.status != PurchaseReceiptStatus.draft) {
      return _rejectCapture('Start a receipt before adding purchases.');
    }
    if (!_state.matchCandidates.any(
      (candidate) => candidate.homeProductId == homeProductId,
    )) {
      return _rejectCapture('Choose an existing product from this home.');
    }
    return _runCaptureMutation(
      () =>
          (_repository as PurchaseQuickEntryRepository).addPurchasedReceiptLine(
            homeProductId: homeProductId,
            packId: packId,
            line: PurchaseReceiptLineRequest(
              homeId: homeId,
              receiptId: receipt.id,
              rawDescription: rawDescription,
              quantity: double.tryParse(quantityText) ?? double.nan,
              quantityText: quantityText,
              originalPackText: originalPackText,
              unitPrice: unitPrice,
              lineTotal: lineTotal,
            ),
          ),
      queuedNotice:
          'Purchase saved. Stock is updated locally; synchronization is pending.',
    );
  }

  Future<bool> approveLine({
    required String lineId,
    required String homeProductId,
  }) {
    final capture = _state.capture;
    if (capture == null || capture.status != PurchaseReceiptStatus.draft) {
      return _rejectCapture('No editable draft receipt is available.');
    }
    if (!capture.lines.any((line) => line.id == lineId)) {
      return _rejectCapture('The selected receipt line is unavailable.');
    }
    if (!_state.matchCandidates.any(
      (candidate) => candidate.id == homeProductId,
    )) {
      return _rejectCapture(
        'The selected product is unavailable in this home.',
      );
    }
    return _runCaptureMutation(
      () => _captureRepository!.approveReceiptLine(
        homeId: homeId,
        receiptId: capture.id,
        lineId: lineId,
        homeProductId: homeProductId,
      ),
      queuedNotice:
          'The line approval is saved locally and queued for synchronization.',
    );
  }

  Future<bool> approveCandidate({
    required String lineId,
    required String candidateId,
    String? purchasedPackId,
    bool quantityInStockUnits = false,
  }) async {
    final line = _captureLine(lineId);
    if (line == null) {
      return _rejectCapture('The selected receipt line is unavailable.');
    }
    if (line.approved) return true;
    PurchaseMatchCandidate? candidate;
    for (final value in _state.matchCandidates) {
      if (value.id == candidateId) {
        candidate = value;
        break;
      }
    }
    if (candidate == null || candidate.homeId != homeId) {
      return _rejectCapture(
        'The selected product is unavailable in this home.',
      );
    }
    final selectedCandidate = candidate;
    final homeProductId = reviewTargetForCandidate(
      selectedCandidate,
    ).homeProductId;
    if (homeProductId != null) {
      return _runCaptureMutation(
        () => _approveSelectedLine(
          receiptId: _state.capture!.id,
          lineId: lineId,
          homeProductId: homeProductId,
          packId: quantityInStockUnits
              ? null
              : purchasedPackId ??
                    (selectedCandidate.packStatus == 'published'
                        ? selectedCandidate.packId
                        : null),
        ),
        queuedNotice:
            'The reviewed product and quantity are saved locally; stock changes when the receipt is finished.',
      );
    }
    return _createProductAndApprove(
      lineId: lineId,
      pendingKey:
          '$lineId:catalog:${selectedCandidate.productId}:${selectedCandidate.packId}',
      create: () => _productCreationRepository!.createCatalogHomeProduct(
        CatalogHomeProductDraft(
          homeId: homeId,
          productId: selectedCandidate.productId!,
          packId: selectedCandidate.packId!,
          canonicalName: selectedCandidate.name,
          packSize: selectedCandidate.packSize,
          category: selectedCandidate.category,
          brand: selectedCandidate.brand,
          aliases: selectedCandidate.aliases,
        ),
      ),
      unavailableMessage:
          'Adding a published pack is unavailable in this workspace.',
      supported: canAddPublishedPack,
      reviewedPackId: quantityInStockUnits
          ? null
          : purchasedPackId ?? selectedCandidate.packId,
    );
  }

  Future<bool> createPrivateProductAndApprove({
    required String lineId,
    required String privateName,
    String? originalPackText,
  }) {
    final normalizedName = privateName.trim().toLowerCase();
    final normalizedPack = originalPackText?.trim().toLowerCase() ?? '';
    return _createProductAndApprove(
      lineId: lineId,
      pendingKey: '$lineId:private:$normalizedName:$normalizedPack',
      create: () => _productCreationRepository!.createPrivateHomeProduct(
        PrivateHomeProductDraft(
          homeId: homeId,
          privateName: privateName,
          originalPackText: originalPackText,
        ),
      ),
      unavailableMessage:
          'Private product creation is unavailable in this workspace.',
      supported: canCreatePrivateProduct,
    );
  }

  Future<bool> leaveLineUnresolved(String lineId) async {
    if (!captureEnabled) {
      return _rejectCapture(
        'Purchase capture is unavailable for this read-only home.',
      );
    }
    final capture = _state.capture;
    final line = _captureLine(lineId);
    if (capture == null ||
        capture.status != PurchaseReceiptStatus.draft ||
        line == null) {
      return _rejectCapture('The selected receipt line is unavailable.');
    }
    return _runCaptureMutation(
      () => _captureRepository!.markReceiptLineUnresolved(
        homeId: homeId,
        receiptId: capture.id,
        lineId: line.id,
      ),
      queuedNotice:
          'The unresolved decision is saved locally and queued; it creates no price or stock effect.',
    );
  }

  Future<bool> commitDraft() {
    final capture = _state.capture;
    if (capture == null) {
      return _rejectCapture('No draft receipt is available to commit.');
    }
    if (capture.commitAwaitingReadback) {
      return _runCaptureMutation(
        () => _captureRepository!.commitReceipt(
          homeId: homeId,
          receiptId: capture.id,
        ),
        queuedNotice:
            'The receipt commit remains queued; server confirmation is pending.',
      );
    }
    if (capture.status != PurchaseReceiptStatus.draft) {
      return _rejectCapture('This receipt is no longer editable.');
    }
    if (!capture.reviewComplete) {
      return _rejectCapture(
        'Every receipt line must be approved or intentionally left unresolved.',
      );
    }
    return _runCaptureMutation(
      () => _captureRepository!.commitReceipt(
        homeId: homeId,
        receiptId: capture.id,
      ),
      queuedNotice:
          'The receipt commit is queued; server confirmation is pending.',
    );
  }

  void reportCaptureValidation(String safeMessage) {
    _setCaptureError(safeMessage);
  }

  Future<bool> _createProductAndApprove({
    required String lineId,
    required String pendingKey,
    required Future<InventoryProductCreationResult> Function() create,
    required String unavailableMessage,
    required bool supported,
    String? reviewedPackId,
  }) async {
    final capture = _state.capture;
    final line = _captureLine(lineId);
    if (capture == null ||
        capture.status != PurchaseReceiptStatus.draft ||
        line == null) {
      return _rejectCapture('No editable draft receipt is available.');
    }
    if (line.approved) return true;
    if (!supported) return _rejectCapture(unavailableMessage);
    if (_state.captureBusy || _disposed) return false;
    final originalReceiptId = _state.capture?.id;
    _setCaptureBusy(true);
    try {
      var homeProductId = _createdHomeProductIds[pendingKey];
      if (homeProductId == null) {
        final result = await create();
        if (result.homeProductId.trim().isEmpty) {
          throw const InventoryProductCreationException(
            'The product identity could not be created safely.',
          );
        }
        homeProductId = result.homeProductId;
        _createdHomeProductIds[pendingKey] = homeProductId;
      }
      final result = await _approveSelectedLine(
        receiptId: capture.id,
        lineId: lineId,
        homeProductId: homeProductId,
        packId: reviewedPackId,
      );
      if (_disposed) return true;
      if (_state.capture?.id != originalReceiptId) {
        _setCaptureBusy(false);
        return true;
      }
      _receiptErrors.remove(capture.id);
      _state = PurchasingState(
        lines: _state.lines,
        matchCandidates: _state.matchCandidates,
        view: _state.view,
        loading: _state.loading,
        capture: _state.capture,
        captureNotice:
            result.disposition == PurchaseMutationDisposition.synchronized &&
                _state.capture?.synchronizationState ==
                    PurchaseSynchronizationState.synchronized
            ? 'The product and line approval are synchronized.'
            : result.disposition ==
                  PurchaseMutationDisposition.confirmedAwaitingReadback
            ? 'The server confirmed the line approval. Receipt details are refreshing.'
            : 'The product and line approval are saved locally and queued.',
        safeError: _state.safeError,
      );
      _notifyIfActive();
      return true;
    } on InventoryProductCreationException catch (error) {
      _reportMutationError(originalReceiptId, error.safeMessage);
      return false;
    } on PurchaseCaptureException catch (error) {
      _reportMutationError(originalReceiptId, error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _reportMutationError(
        originalReceiptId,
        'Check the product name and pack details.',
      );
      return false;
    } catch (_) {
      _reportMutationError(
        originalReceiptId,
        'The product match could not be saved safely.',
      );
      return false;
    }
  }

  Future<PurchaseMutationResult> _approveSelectedLine({
    required String receiptId,
    required String lineId,
    required String homeProductId,
    String? packId,
  }) => canReviewPacks
      ? (_repository as PurchasePackReviewRepository)
            .approveReceiptLineWithPack(
              homeId: homeId,
              receiptId: receiptId,
              lineId: lineId,
              homeProductId: homeProductId,
              packId: packId,
            )
      : _captureRepository!.approveReceiptLine(
          homeId: homeId,
          receiptId: receiptId,
          lineId: lineId,
          homeProductId: homeProductId,
        );

  PurchaseMatchCandidate reviewTargetForCandidate(
    PurchaseMatchCandidate candidate,
  ) {
    if (!candidate.requiresHomeSelection || candidate.productId == null) {
      return candidate;
    }
    final existing = _state.matchCandidates
        .where(
          (value) =>
              value.homeProductId != null &&
              value.productId == candidate.productId,
        )
        .toList();
    return existing.length == 1 ? existing.single : candidate;
  }

  String approvedStockPreview(PurchaseReceiptLineCapture line) {
    try {
      final quantity = PurchaseQuantity.parse(
        line.quantityText ??
            line.quantity
                .toStringAsFixed(8)
                .replaceFirst(RegExp(r'\.?0+$'), ''),
        positive: true,
      );
      final factor = PurchaseQuantity.parse(
        line.stockQuantityPerPack ?? '1',
        positive: true,
      );
      return 'On finish: +${quantity * factor} ${line.stockUnit ?? 'stock units'}';
    } on ArgumentError {
      return 'Review the quantity before finishing this receipt.';
    }
  }

  String reviewedStockPreview({
    required PurchaseReceiptLineCapture line,
    required PurchaseMatchCandidate product,
    String? packId,
    bool quantityInStockUnits = false,
  }) {
    try {
      final quantity = PurchaseQuantity.parse(
        line.quantityText ??
            line.quantity
                .toStringAsFixed(8)
                .replaceFirst(RegExp(r'\.?0+$'), ''),
        positive: true,
      );
      final target = reviewTargetForCandidate(product);
      final unit = target.requiresHomeSelection ? 'units' : target.stockUnit;
      if (quantityInStockUnits || packId == null) {
        return 'On finish: +$quantity $unit';
      }
      final selected = _state.matchCandidates
          .where(
            (candidate) =>
                candidate.productId == product.productId &&
                candidate.packId == packId,
          )
          .firstOrNull;
      if (selected == null) return 'Choose a published pack.';
      final factor = purchasePackConversionFactor(
        stockUnit: unit,
        selectedAmount: selected.normalizedBaseAmount,
        selectedUnit: selected.normalizedBaseUnit,
        baseAmount: target.normalizedBaseAmount,
        baseUnit: target.normalizedBaseUnit,
        selectedIsBasePack: target.packId == selected.packId,
      );
      return 'On finish: +${quantity * factor} $unit';
    } on ArgumentError {
      return 'Choose a compatible pack or use quantity in stock units.';
    }
  }

  PurchaseReceiptLineCapture? _captureLine(String lineId) {
    final capture = _state.capture;
    if (capture == null || capture.homeId != homeId) return null;
    for (final line in capture.lines) {
      if (line.id == lineId && line.homeId == homeId) return line;
    }
    return null;
  }

  List<PurchaseMatchCandidate> _projectItemMasterCandidates(
    List<InventoryItem> items,
  ) {
    final candidates = <String, PurchaseMatchCandidate>{};
    for (final item in items) {
      if (item.homeId != homeId) {
        throw StateError('Cross-home item-master data was rejected.');
      }
      final kind = !item.isHomeProduct
          ? PurchaseMatchCandidateKind.unselectedPublishedPack
          : item.productId == null || item.packId == null
          ? PurchaseMatchCandidateKind.privateHomeProduct
          : PurchaseMatchCandidateKind.selectedCatalogPack;
      final key = item.productId != null && item.packId != null
          ? 'catalog:${item.productId}:${item.packId}'
          : 'private:${item.id}';
      final candidate = PurchaseMatchCandidate(
        id: item.id,
        homeId: homeId,
        name: item.canonicalName,
        packSize: item.packSize,
        kind: kind,
        homeProductId: item.isHomeProduct ? item.id : null,
        productId: item.productId,
        packId: item.packId,
        brand: item.brand,
        stockUnit: item.unit,
        normalizedBaseAmount: item.normalizedBaseAmount,
        normalizedBaseUnit: item.normalizedBaseUnit,
        packStatus: item.packStatus,
        category: item.category,
        aliases: item.aliases,
      );
      final existing = candidates[key];
      if (existing == null ||
          (existing.requiresHomeSelection &&
              !candidate.requiresHomeSelection)) {
        candidates[key] = candidate;
      }
    }
    final result = candidates.values.toList(growable: false)
      ..sort((left, right) {
        final name = left.name.compareTo(right.name);
        if (name != 0) return name;
        final pack = left.packSize.compareTo(right.packSize);
        return pack != 0 ? pack : left.id.compareTo(right.id);
      });
    return result;
  }

  void _replaceMatchCandidates(List<PurchaseMatchCandidate> candidates) {
    _state = PurchasingState(
      lines: _state.lines,
      matchCandidates: List<PurchaseMatchCandidate>.unmodifiable(candidates),
      view: _state.view,
      loading: _state.loading,
      captureBusy: _state.captureBusy,
      capture: _state.capture,
      captureNotice: _state.captureNotice,
      captureError: _state.captureError,
      safeError: _state.safeError,
    );
    _notifyIfActive();
  }

  Future<bool> _runCaptureMutation(
    Future<PurchaseMutationResult> Function() mutation, {
    required String queuedNotice,
    void Function(PurchaseMutationResult)? onResult,
  }) async {
    if (!captureEnabled) {
      return _rejectCapture(
        'Purchase capture is unavailable for this read-only home.',
      );
    }
    if (_state.captureBusy || _disposed) return false;
    final originalReceiptId = _state.capture?.id;
    _setCaptureBusy(true);
    try {
      final result = await mutation();
      if (_disposed) return true;
      onResult?.call(result);
      if (onResult == null && _state.capture?.id != originalReceiptId) {
        _setCaptureBusy(false);
        return true;
      }
      if (_state.capture?.id case final String receiptId) {
        _receiptErrors.remove(receiptId);
      }
      _state = PurchasingState(
        lines: _state.lines,
        matchCandidates: _state.matchCandidates,
        view: _state.view,
        loading: _state.loading,
        capture: _state.capture,
        captureNotice:
            result.disposition == PurchaseMutationDisposition.synchronized &&
                _state.capture?.synchronizationState ==
                    PurchaseSynchronizationState.synchronized
            ? 'The receipt change is synchronized.'
            : _state.capture?.commitConfirmed == true
            ? 'The server confirmed the receipt commit. Receipt details are refreshing.'
            : result.disposition ==
                  PurchaseMutationDisposition.confirmedAwaitingReadback
            ? 'The server confirmed the receipt change. Receipt details are refreshing.'
            : queuedNotice,
        safeError: _state.safeError,
      );
      _notifyIfActive();
      return true;
    } on PurchaseCaptureException catch (error) {
      _reportMutationError(originalReceiptId, error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _reportMutationError(
        originalReceiptId,
        'Check the receipt values and try again.',
      );
      return false;
    } catch (_) {
      _reportMutationError(
        originalReceiptId,
        'The receipt change could not be saved safely.',
      );
      return false;
    }
  }

  void _reportMutationError(String? receiptId, String message) {
    if (_disposed) return;
    if (receiptId != _state.capture?.id) {
      if (receiptId != null) _receiptErrors[receiptId] = message;
      _setCaptureBusy(false);
      return;
    }
    _setCaptureError(message);
  }

  Future<bool> _rejectCapture(String safeMessage) async {
    _setCaptureError(safeMessage);
    return false;
  }

  void _setCaptureBusy(bool busy) {
    _state = PurchasingState(
      lines: _state.lines,
      matchCandidates: _state.matchCandidates,
      view: _state.view,
      loading: _state.loading,
      captureBusy: busy,
      capture: _state.capture,
      captureNotice: _state.captureNotice,
      captureError: _state.captureError,
      safeError: _state.safeError,
    );
    _notifyIfActive();
  }

  void _setCaptureError(String safeMessage) {
    if (_disposed) return;
    if (_state.capture?.id case final String receiptId) {
      _receiptErrors[receiptId] = safeMessage;
    }
    _state = PurchasingState(
      lines: _state.lines,
      matchCandidates: _state.matchCandidates,
      view: _state.view,
      loading: _state.loading,
      capture: _state.capture,
      captureNotice: _state.captureNotice,
      captureError: safeMessage,
      safeError: _state.safeError,
    );
    _notifyIfActive();
  }

  String _captureSafeError(Object error) => error is PurchaseCaptureException
      ? error.safeMessage
      : 'Receipt capture could not be loaded safely.';

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _storesSubscription?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_captureSubscription?.cancel());
    unawaited(_receiptsSubscription?.cancel());
    unawaited(_candidateSubscription?.cancel());
    unawaited(_itemMasterSubscription?.cancel());
    super.dispose();
  }
}
