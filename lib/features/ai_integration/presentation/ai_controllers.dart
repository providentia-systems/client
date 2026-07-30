import 'package:flutter/foundation.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/ai_use_cases.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';

final class AiConsentController extends ChangeNotifier {
  factory AiConsentController({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    DateTime Function()? clock,
  }) => AiConsentController._(
    provider,
    privacyMode,
    media,
    clock ?? DateTime.now,
  );

  AiConsentController._(
    this._provider,
    this._privacyMode,
    this._media,
    this._clock,
  );

  final DateTime Function() _clock;
  AiProviderProfile _provider;
  AiPrivacyMode _privacyMode;
  PreparedMediaBatch _media;
  AiConsent? _consent;

  AiProviderProfile get provider => _provider;
  AiPrivacyMode get privacyMode => _privacyMode;
  PreparedMediaBatch get media => _media;
  AiConsent? get consent => _consent;
  bool get isConfirmed => _consent != null;

  void confirm() {
    _consent = AiConsent(
      providerId: _provider.id,
      providerRevision: _provider.revision,
      privacyMode: _privacyMode,
      purpose: _media.purpose,
      orderedMediaHashes: _media.orderedHashes,
      disclosureVersion: AiPrivacyPolicy.disclosureVersion,
      confirmedAt: _clock().toUtc(),
    );
    notifyListeners();
  }

  void revoke() {
    if (_consent == null) {
      return;
    }
    _consent = null;
    notifyListeners();
  }

  void updateContext({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
  }) {
    final changed =
        provider.id != _provider.id ||
        provider.revision != _provider.revision ||
        privacyMode != _privacyMode ||
        media.purpose != _media.purpose ||
        !_sameHashes(media.orderedHashes, _media.orderedHashes);
    _provider = provider;
    _privacyMode = privacyMode;
    _media = media;
    if (changed) {
      _consent = null;
      notifyListeners();
    }
  }

  bool _sameHashes(List<String> first, List<String> second) {
    if (first.length != second.length) {
      return false;
    }
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }
    return true;
  }
}

final class AiProviderConfigurationController extends ChangeNotifier {
  AiProviderConfigurationController(this._configure);

  final ConfigureAiProvider _configure;
  bool _isSaving = false;
  String? _safeError;
  AiProviderProfile? _savedProfile;

  bool get isSaving => _isSaving;
  String? get safeError => _safeError;
  AiProviderProfile? get savedProfile => _savedProfile;

  Future<void> save({
    required AiProviderProfile profile,
    String? replacementSecret,
  }) async {
    if (_isSaving) {
      return;
    }
    _isSaving = true;
    _safeError = null;
    notifyListeners();
    try {
      _savedProfile = await _configure.execute(
        profile: profile,
        replacementSecret: replacementSecret,
      );
    } on AiPolicyViolation catch (error) {
      _safeError = error.safeMessage;
    } catch (_) {
      _safeError = 'The provider could not be saved safely.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}

enum ExtractionControllerState {
  ready,
  processing,
  reviewRequired,
  quarantined,
  failed,
}

final class ReceiptExtractionController extends ChangeNotifier {
  ReceiptExtractionController(this._extract);

  final ExtractReceiptProposal _extract;
  ExtractionControllerState _state = ExtractionControllerState.ready;
  ReceiptProposal? _proposal;
  String? _safeMessage;

  ExtractionControllerState get state => _state;
  ReceiptProposal? get proposal => _proposal;
  String? get safeMessage => _safeMessage;

  Future<void> extract({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
  }) async {
    if (_state == ExtractionControllerState.processing) {
      return;
    }
    _state = ExtractionControllerState.processing;
    _safeMessage = null;
    notifyListeners();
    try {
      final result = await _extract.execute(
        provider: provider,
        privacyMode: privacyMode,
        media: media,
        consent: consent,
      );
      switch (result) {
        case AiExtractionSuccess<ReceiptProposal>():
          _proposal = result.proposal;
          _state = ExtractionControllerState.reviewRequired;
        case AiExtractionQuarantined<ReceiptProposal>():
          _proposal = null;
          _state = ExtractionControllerState.quarantined;
          _safeMessage =
              'This image is not an eligible receipt and was quarantined.';
        case AiExtractionRefused<ReceiptProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeReason;
        case AiExtractionIncomplete<ReceiptProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeReason;
        case AiExtractionFailure<ReceiptProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeMessage;
      }
    } on AiPolicyViolation catch (error) {
      _state = ExtractionControllerState.failed;
      _safeMessage = error.safeMessage;
    } catch (_) {
      _state = ExtractionControllerState.failed;
      _safeMessage = 'Receipt extraction could not be completed safely.';
    }
    notifyListeners();
  }
}

final class StockPhotoExtractionController extends ChangeNotifier {
  StockPhotoExtractionController(this._extract);

  final ExtractStockPhotoProposal _extract;
  ExtractionControllerState _state = ExtractionControllerState.ready;
  StockPhotoProposal? _proposal;
  String? _safeMessage;

  ExtractionControllerState get state => _state;
  StockPhotoProposal? get proposal => _proposal;
  String? get safeMessage => _safeMessage;

  Future<void> extract({
    required AiProviderProfile provider,
    required AiPrivacyMode privacyMode,
    required PreparedMediaBatch media,
    required AiConsent consent,
  }) async {
    if (_state == ExtractionControllerState.processing) {
      return;
    }
    _state = ExtractionControllerState.processing;
    _safeMessage = null;
    notifyListeners();
    try {
      final result = await _extract.execute(
        provider: provider,
        privacyMode: privacyMode,
        media: media,
        consent: consent,
      );
      switch (result) {
        case AiExtractionSuccess<StockPhotoProposal>():
          _proposal = result.proposal;
          _state = ExtractionControllerState.reviewRequired;
        case AiExtractionQuarantined<StockPhotoProposal>():
          _proposal = null;
          _state = ExtractionControllerState.quarantined;
          _safeMessage =
              'This image is unrelated or medical and was quarantined.';
        case AiExtractionRefused<StockPhotoProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeReason;
        case AiExtractionIncomplete<StockPhotoProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeReason;
        case AiExtractionFailure<StockPhotoProposal>():
          _state = ExtractionControllerState.failed;
          _safeMessage = result.safeMessage;
      }
    } on AiPolicyViolation catch (error) {
      _state = ExtractionControllerState.failed;
      _safeMessage = error.safeMessage;
    } catch (_) {
      _state = ExtractionControllerState.failed;
      _safeMessage = 'Stock extraction could not be completed safely.';
    }
    notifyListeners();
  }
}

final class CatalogCandidateController extends ChangeNotifier {
  CatalogCandidateController(this._lookup);

  final CatalogCandidateLookupPort _lookup;
  List<CatalogCandidate> _candidates = const <CatalogCandidate>[];
  bool _isSearching = false;
  String? _safeError;

  List<CatalogCandidate> get candidates => _candidates;
  bool get isSearching => _isSearching;
  String? get safeError => _safeError;

  Future<void> search({required String homeId, required String query}) async {
    if (query.trim().length < 2) {
      _candidates = const <CatalogCandidate>[];
      _safeError = null;
      notifyListeners();
      return;
    }
    _isSearching = true;
    _safeError = null;
    notifyListeners();
    try {
      _candidates = await _lookup.search(homeId: homeId, query: query.trim());
    } catch (_) {
      _candidates = const <CatalogCandidate>[];
      _safeError = 'Catalog search is temporarily unavailable.';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }
}

final class ReceiptReviewController extends ChangeNotifier {
  factory ReceiptReviewController({
    required ReceiptProposal proposal,
    required String homeId,
    required String approvedBy,
    required ApproveReceiptProposal approval,
    required String Function() idempotencyKey,
    DateTime Function()? clock,
  }) => ReceiptReviewController._(
    proposal,
    homeId,
    approvedBy,
    approval,
    idempotencyKey,
    clock ?? DateTime.now,
  );

  ReceiptReviewController._(
    this.proposal,
    this.homeId,
    this.approvedBy,
    this._approval,
    this._idempotencyKey,
    this._clock,
  );

  final ReceiptProposal proposal;
  final String homeId;
  final String approvedBy;
  final ApproveReceiptProposal _approval;
  final String Function() _idempotencyKey;
  final DateTime Function() _clock;
  final Map<String, ReviewedReceiptLine> _selected =
      <String, ReviewedReceiptLine>{};

  bool _isApproving = false;
  String? _safeError;
  CommitOutcome? _outcome;

  bool get isApproving => _isApproving;
  String? get safeError => _safeError;
  CommitOutcome? get outcome => _outcome;
  bool get isCommitted => _outcome != null;
  bool get canApprove =>
      !proposal.requiresQuarantine &&
      proposal.classification != ReceiptDocumentClassification.unknown &&
      _selected.isNotEmpty &&
      !_isApproving &&
      !isCommitted;
  Set<String> get selectedLineIds => Set<String>.unmodifiable(_selected.keys);

  void resolveLine({
    required ReceiptLineProposal line,
    required CatalogResolution resolution,
    required double quantity,
    String? unitPrice,
    String? lineTotal,
  }) {
    if (!proposal.lines.any((candidate) => candidate.lineId == line.lineId)) {
      return;
    }
    if (resolution.kind == CatalogResolutionKind.unresolved) {
      _selected.remove(line.lineId);
    } else {
      _selected[line.lineId] = ReviewedReceiptLine(
        proposalLineId: line.lineId,
        resolution: resolution,
        quantity: quantity,
        unitPrice: unitPrice,
        lineTotal: lineTotal,
      );
    }
    _safeError = null;
    notifyListeners();
  }

  void removeLine(String lineId) {
    if (_selected.remove(lineId) != null) {
      notifyListeners();
    }
  }

  Future<void> approve() async {
    if (!canApprove) {
      _safeError = proposal.requiresQuarantine
          ? 'Quarantined content cannot be approved.'
          : 'Resolve at least one receipt line before approval.';
      notifyListeners();
      return;
    }
    _isApproving = true;
    _safeError = null;
    notifyListeners();
    try {
      _outcome = await _approval.execute(
        review: ReviewedReceipt(
          proposalId: proposal.id,
          runId: proposal.runId,
          homeId: homeId,
          approvedBy: approvedBy,
          approvedAt: _clock().toUtc(),
          humanConfirmed: true,
          lines: _selected.values.toList(growable: false),
        ),
        idempotencyKey: _idempotencyKey(),
      );
    } on AiPolicyViolation catch (error) {
      _safeError = error.safeMessage;
    } catch (_) {
      _safeError = 'The receipt could not be approved safely.';
    } finally {
      _isApproving = false;
      notifyListeners();
    }
  }
}

final class StockPhotoReviewController extends ChangeNotifier {
  factory StockPhotoReviewController({
    required StockPhotoProposal proposal,
    required String homeId,
    required String sessionId,
    required String locationId,
    required String closedBy,
    required CloseStockPhotoCount closeCount,
    required String Function() idempotencyKey,
    DateTime Function()? clock,
  }) => StockPhotoReviewController._(
    proposal,
    homeId,
    sessionId,
    locationId,
    closedBy,
    closeCount,
    idempotencyKey,
    clock ?? DateTime.now,
  );

  StockPhotoReviewController._(
    this.proposal,
    this.homeId,
    this.sessionId,
    this.locationId,
    this.closedBy,
    this._closeCount,
    this._idempotencyKey,
    this._clock,
  );

  final StockPhotoProposal proposal;
  final String homeId;
  final String sessionId;
  final String locationId;
  final String closedBy;
  final CloseStockPhotoCount _closeCount;
  final String Function() _idempotencyKey;
  final DateTime Function() _clock;
  final Map<String, ConfirmedStockItem> _confirmed =
      <String, ConfirmedStockItem>{};

  bool _isClosing = false;
  String? _safeError;
  CommitOutcome? _outcome;

  bool get isClosing => _isClosing;
  String? get safeError => _safeError;
  CommitOutcome? get outcome => _outcome;
  bool get isCommitted => _outcome != null;
  bool get canClose =>
      !proposal.requiresQuarantine &&
      proposal.classification != StockImageClassification.unknown &&
      !_isClosing &&
      !isCommitted;
  Set<String> get confirmedCandidateIds =>
      Set<String>.unmodifiable(_confirmed.keys);

  void confirmCandidate({
    required StockCandidateProposal candidate,
    required CatalogResolution resolution,
    required double quantity,
  }) {
    if (!proposal.candidates.any(
      (item) => item.candidateId == candidate.candidateId,
    )) {
      return;
    }
    if (resolution.kind == CatalogResolutionKind.unresolved) {
      _confirmed.remove(candidate.candidateId);
    } else {
      _confirmed[candidate.candidateId] = ConfirmedStockItem(
        proposalCandidateId: candidate.candidateId,
        resolution: resolution,
        quantity: quantity,
      );
    }
    _safeError = null;
    notifyListeners();
  }

  void unconfirmCandidate(String candidateId) {
    if (_confirmed.remove(candidateId) != null) {
      notifyListeners();
    }
  }

  Future<void> close() async {
    if (!canClose) {
      _safeError = proposal.requiresQuarantine
          ? 'Quarantined content cannot be used for a stock count.'
          : 'This count can no longer be closed.';
      notifyListeners();
      return;
    }
    _isClosing = true;
    _safeError = null;
    notifyListeners();
    try {
      _outcome = await _closeCount.execute(
        review: ReviewedStockCount(
          proposalId: proposal.id,
          runId: proposal.runId,
          homeId: homeId,
          sessionId: sessionId,
          locationId: locationId,
          closedBy: closedBy,
          closedAt: _clock().toUtc(),
          explicitlyClosed: true,
          items: _confirmed.values.toList(growable: false),
        ),
        idempotencyKey: _idempotencyKey(),
      );
    } on AiPolicyViolation catch (error) {
      _safeError = error.safeMessage;
    } catch (_) {
      _safeError = 'The stock count could not be closed safely.';
    } finally {
      _isClosing = false;
      notifyListeners();
    }
  }
}
