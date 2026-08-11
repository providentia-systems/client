import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/inventory/application/inventory_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';
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
  }) => PurchasingController._(
    repository,
    homeId,
    mayWrite,
    grouper,
    matchRanker,
    productCreationRepository,
  );

  PurchasingController._(
    PurchaseRepository repository,
    this.homeId,
    this._mayWrite,
    this._grouper,
    this._matchRanker,
    this._productCreationRepository,
  ) : _repository = repository,
      _captureRepository = repository is PurchaseCaptureRepository
          ? repository
          : null;

  final PurchaseRepository _repository;
  final PurchaseCaptureRepository? _captureRepository;
  final PurchaseHistoryGrouper _grouper;
  final PurchaseMatchRanker _matchRanker;
  final InventoryProductCreationRepository? _productCreationRepository;
  final bool _mayWrite;
  final String homeId;
  StreamSubscription<List<PurchaseLine>>? _subscription;
  StreamSubscription<PurchaseReceiptCapture?>? _captureSubscription;
  StreamSubscription<List<PurchaseMatchCandidate>>? _candidateSubscription;
  StreamSubscription<List<InventoryItem>>? _itemMasterSubscription;
  List<PurchaseMatchCandidate> _legacyMatchCandidates =
      const <PurchaseMatchCandidate>[];
  bool _itemMasterVerified = false;
  final Map<String, String> _createdHomeProductIds = <String, String>{};
  PurchasingState _state = const PurchasingState();

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
              notifyListeners();
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
            notifyListeners();
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
            notifyListeners();
          },
        );
    final captureRepository = _captureRepository;
    if (!captureEnabled || captureRepository == null) return;
    _captureSubscription = captureRepository
        .watchActiveReceiptCapture(homeId: homeId)
        .listen(
          (capture) {
            if (capture != null && capture.homeId != homeId) {
              _setCaptureError('Purchase capture access was rejected.');
              return;
            }
            final confirmed =
                _state.capture?.commitAwaitingConfirmation == true &&
                capture == null;
            _state = PurchasingState(
              lines: _state.lines,
              matchCandidates: _state.matchCandidates,
              view: _state.view,
              loading: _state.loading,
              captureBusy: _state.captureBusy,
              capture: capture,
              captureNotice: confirmed
                  ? 'The receipt commit is synchronized.'
                  : _state.captureNotice,
              captureError: _state.captureError,
              safeError: _state.safeError,
            );
            notifyListeners();
          },
          onError: (Object error) {
            _setCaptureError(_captureSafeError(error));
          },
        );
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
    notifyListeners();
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
      queuedNotice:
          'The draft is saved locally and queued for synchronization.',
    );
  }

  Future<bool> addLine({
    required String rawDescription,
    required double quantity,
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
          originalPackText: originalPackText,
          unitPrice: unitPrice,
          lineTotal: lineTotal,
        ),
      ),
      queuedNotice:
          'The receipt line is saved locally and queued for synchronization.',
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
    final homeProductId = selectedCandidate.homeProductId;
    if (homeProductId != null) {
      return approveLine(lineId: lineId, homeProductId: homeProductId);
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
    if (capture.commitAwaitingConfirmation) {
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
    if (_state.captureBusy) return false;
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
      final result = await _captureRepository!.approveReceiptLine(
        homeId: homeId,
        receiptId: capture.id,
        lineId: lineId,
        homeProductId: homeProductId,
      );
      _state = PurchasingState(
        lines: _state.lines,
        matchCandidates: _state.matchCandidates,
        view: _state.view,
        loading: _state.loading,
        capture: _state.capture,
        captureNotice:
            result.disposition == PurchaseMutationDisposition.synchronized
            ? 'The product and line approval are synchronized.'
            : 'The product and line approval are saved locally and queued.',
        safeError: _state.safeError,
      );
      notifyListeners();
      return true;
    } on InventoryProductCreationException catch (error) {
      _setCaptureError(error.safeMessage);
      return false;
    } on PurchaseCaptureException catch (error) {
      _setCaptureError(error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _setCaptureError('Check the product name and pack details.');
      return false;
    } catch (_) {
      _setCaptureError('The product match could not be saved safely.');
      return false;
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
    notifyListeners();
  }

  Future<bool> _runCaptureMutation(
    Future<PurchaseMutationResult> Function() mutation, {
    required String queuedNotice,
  }) async {
    if (!captureEnabled) {
      return _rejectCapture(
        'Purchase capture is unavailable for this read-only home.',
      );
    }
    if (_state.captureBusy) return false;
    _setCaptureBusy(true);
    try {
      final result = await mutation();
      _state = PurchasingState(
        lines: _state.lines,
        matchCandidates: _state.matchCandidates,
        view: _state.view,
        loading: _state.loading,
        capture: _state.capture,
        captureNotice:
            result.disposition == PurchaseMutationDisposition.synchronized
            ? 'The receipt change is synchronized.'
            : queuedNotice,
        safeError: _state.safeError,
      );
      notifyListeners();
      return true;
    } on PurchaseCaptureException catch (error) {
      _setCaptureError(error.safeMessage);
      return false;
    } on ArgumentError catch (_) {
      _setCaptureError('Check the receipt values and try again.');
      return false;
    } catch (_) {
      _setCaptureError('The receipt change could not be saved safely.');
      return false;
    }
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
      safeError: _state.safeError,
    );
    notifyListeners();
  }

  void _setCaptureError(String safeMessage) {
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
    notifyListeners();
  }

  String _captureSafeError(Object error) => error is PurchaseCaptureException
      ? error.safeMessage
      : 'Receipt capture could not be loaded safely.';

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_captureSubscription?.cancel());
    unawaited(_candidateSubscription?.cancel());
    unawaited(_itemMasterSubscription?.cancel());
    super.dispose();
  }
}
