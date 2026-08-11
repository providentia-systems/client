import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/purchasing/application/purchase_repository.dart';
import 'package:providentia/features/purchasing/domain/purchase_models.dart';

enum ReceiptAiHandoffStatus {
  awaitingConfirmation,
  confirming,
  readyForPurchasingReview,
  invalidated,
  failed,
}

/// Converts an accepted AI receipt review into ordinary Phase 5 purchasing
/// commands only after a second explicit confirmation.
///
/// It deliberately has no inventory, matching, approval, or commit port.
final class ReceiptAiHandoffController extends ChangeNotifier {
  factory ReceiptAiHandoffController({
    required AiReviewHandoff handoff,
    required PurchaseCaptureRepository repository,
    required String activeHomeId,
    required bool mayWritePurchases,
    Duration recoveryTimeout = const Duration(seconds: 2),
  }) => ReceiptAiHandoffController._(
    handoff: handoff,
    repository: repository,
    activeHomeId: activeHomeId,
    mayWritePurchases: mayWritePurchases,
    recoveryTimeout: recoveryTimeout,
  );

  ReceiptAiHandoffController._({
    required this.handoff,
    required this._repository,
    required this._activeHomeId,
    required this._mayWritePurchases,
    required this.recoveryTimeout,
  }) {
    if (!_hasTypedAcceptedReceiptLines || !_hasConsistentHeaders) {
      _invalidate('The reviewed receipt payload is incomplete or unsafe.');
    } else if (!_hasActiveAccess) {
      _invalidate(
        'The reviewed receipt is no longer valid for the active household.',
      );
    }
  }

  final AiReviewHandoff handoff;
  final PurchaseCaptureRepository _repository;
  final Duration recoveryTimeout;
  String _activeHomeId;
  bool _mayWritePurchases;
  int _accessEpoch = 0;
  bool _disposed = false;
  ReceiptAiHandoffStatus _status = ReceiptAiHandoffStatus.awaitingConfirmation;
  String? _safeMessage;
  String? _receiptId;

  ReceiptAiHandoffStatus get status => _status;
  String? get safeMessage => _safeMessage;
  String? get receiptId => _receiptId;
  String get sourceReference => 'ai-extraction:${handoff.extractionId}';
  bool get isBusy => _status == ReceiptAiHandoffStatus.confirming;
  bool get canConfirm =>
      (_status == ReceiptAiHandoffStatus.awaitingConfirmation ||
          _status == ReceiptAiHandoffStatus.failed) &&
      _hasActiveAccess &&
      _hasTypedAcceptedReceiptLines;
  List<AiReceiptCandidatePayload> get lines => handoff.acceptedReceiptPayloads;
  AiReceiptHeaderPayload? get header =>
      lines.isEmpty ? null : lines.first.header;

  void updateAccess({
    required String activeHomeId,
    required bool mayWritePurchases,
  }) {
    if (_disposed) return;
    _activeHomeId = activeHomeId;
    _mayWritePurchases = mayWritePurchases;
    if (!_hasActiveAccess) {
      _accessEpoch++;
      _invalidate(
        'The reviewed receipt was discarded after household access changed.',
      );
    }
  }

  Future<bool> confirm({DateTime? purchaseDate, String? currency}) async {
    if (_status == ReceiptAiHandoffStatus.readyForPurchasingReview) return true;
    if (!canConfirm) return false;
    final resolvedDate = purchaseDate ?? header?.purchaseDate;
    final resolvedCurrency = (currency ?? header?.currency)
        ?.trim()
        .toUpperCase();
    if (resolvedDate == null ||
        resolvedCurrency == null ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(resolvedCurrency)) {
      _fail(
        'Confirm a valid purchase date and three-letter currency before creating the draft.',
      );
      return false;
    }
    if (lines.any(
      (line) =>
          line.unitPriceMinorUnits == null && line.lineTotalMinorUnits == null,
    )) {
      _fail(
        'Every accepted receipt line needs a unit price or line total before handoff.',
      );
      return false;
    }

    final epoch = _accessEpoch;
    _status = ReceiptAiHandoffStatus.confirming;
    _safeMessage = null;
    _notify();
    try {
      var capture = await _activeCapture();
      if (!_stillAuthorized(epoch)) return false;
      if (capture != null && !_isThisDraft(capture)) {
        throw const PurchaseCaptureException(
          'Finish the active receipt before importing this reviewed receipt.',
        );
      }
      var receiptId = capture?.id;
      if (receiptId == null) {
        try {
          final created = await _repository.createReceiptDraft(
            PurchaseReceiptDraftRequest(
              homeId: handoff.homeId,
              purchaseDate: resolvedDate,
              currency: resolvedCurrency,
              total: header?.totalMinorUnits == null
                  ? null
                  : Money(
                      minorUnits: header!.totalMinorUnits!,
                      currency: resolvedCurrency,
                    ),
              notes: _draftNotes(),
              sourceReference: sourceReference,
            ),
          );
          receiptId = created.entityId;
        } catch (_) {
          capture = await _activeCapture();
          if (capture == null || !_isThisDraft(capture)) rethrow;
          receiptId = capture.id;
        }
      }
      if (!_stillAuthorized(epoch)) return false;
      final receiptCurrency = capture?.currency ?? resolvedCurrency;
      for (var index = 0; index < lines.length; index++) {
        await _ensureLine(
          receiptId: receiptId,
          currency: receiptCurrency,
          line: lines[index],
          desiredOccurrence: _desiredOccurrence(index),
        );
        if (!_stillAuthorized(epoch)) return false;
      }
      _receiptId = receiptId;
      _status = ReceiptAiHandoffStatus.readyForPurchasingReview;
      _safeMessage =
          'Draft created. Match every line in purchasing review, then commit explicitly.';
      _notify();
      return true;
    } on PurchaseCaptureException catch (error) {
      if (_stillAuthorized(epoch)) _fail(error.safeMessage);
      return false;
    } on ArgumentError {
      if (_stillAuthorized(epoch)) {
        _fail('The reviewed receipt contains an invalid purchasing value.');
      }
      return false;
    } catch (_) {
      if (_stillAuthorized(epoch)) {
        _fail('The reviewed receipt draft could not be created safely.');
      }
      return false;
    }
  }

  Future<void> _ensureLine({
    required String receiptId,
    required String currency,
    required AiReceiptCandidatePayload line,
    required int desiredOccurrence,
  }) async {
    var capture = await _activeCapture();
    if (capture != null && capture.id != receiptId) {
      throw const PurchaseCaptureException(
        'The active receipt changed before handoff completed.',
      );
    }
    if (_matchingLineCount(capture, line, currency) >= desiredOccurrence) {
      return;
    }
    final request = _lineRequest(receiptId, line, currency);
    try {
      await _repository.addReceiptLine(request);
    } catch (_) {
      capture = await _activeCapture();
      if (_matchingLineCount(capture, line, currency) < desiredOccurrence) {
        rethrow;
      }
    }
  }

  PurchaseReceiptLineRequest _lineRequest(
    String receiptId,
    AiReceiptCandidatePayload line,
    String currency,
  ) => PurchaseReceiptLineRequest(
    homeId: handoff.homeId,
    receiptId: receiptId,
    rawDescription: line.description,
    quantity: line.quantity,
    originalPackText: line.packText,
    unitPrice: line.unitPriceMinorUnits == null
        ? null
        : Money(minorUnits: line.unitPriceMinorUnits!, currency: currency),
    lineTotal: line.lineTotalMinorUnits == null
        ? null
        : Money(minorUnits: line.lineTotalMinorUnits!, currency: currency),
  );

  int _desiredOccurrence(int index) {
    var count = 0;
    final target = lines[index];
    for (var candidateIndex = 0; candidateIndex <= index; candidateIndex++) {
      if (_samePayload(lines[candidateIndex], target)) count++;
    }
    return count;
  }

  int _matchingLineCount(
    PurchaseReceiptCapture? capture,
    AiReceiptCandidatePayload line,
    String currency,
  ) {
    if (capture == null) return 0;
    return capture.lines.where((existing) {
      return existing.rawDescription.trim() == line.description.trim() &&
          existing.quantity == line.quantity &&
          _normalized(existing.originalPackText) ==
              _normalized(line.packText) &&
          existing.unitPrice == _money(line.unitPriceMinorUnits, currency) &&
          existing.lineTotal == _money(line.lineTotalMinorUnits, currency);
    }).length;
  }

  bool _samePayload(
    AiReceiptCandidatePayload first,
    AiReceiptCandidatePayload second,
  ) =>
      first.description.trim() == second.description.trim() &&
      first.quantity == second.quantity &&
      _normalized(first.packText) == _normalized(second.packText) &&
      first.unitPriceMinorUnits == second.unitPriceMinorUnits &&
      first.lineTotalMinorUnits == second.lineTotalMinorUnits;

  Money? _money(int? minorUnits, String currency) => minorUnits == null
      ? null
      : Money(minorUnits: minorUnits, currency: currency);

  Future<PurchaseReceiptCapture?> _activeCapture() async {
    try {
      return await _repository
          .watchActiveReceiptCapture(homeId: handoff.homeId)
          .first
          .timeout(recoveryTimeout);
    } on TimeoutException {
      return null;
    }
  }

  bool _isThisDraft(PurchaseReceiptCapture capture) =>
      capture.homeId == handoff.homeId &&
      capture.status == PurchaseReceiptStatus.draft &&
      capture.sourceReference == sourceReference;

  String _draftNotes() {
    final parts = <String>[
      if (header?.merchant case final merchant?) 'AI merchant: $merchant',
      if (header?.receiptNumber case final number?) 'Receipt: $number',
      ?header?.notes,
    ];
    final joined = parts.join('\n').trim();
    return joined.length <= 2000 ? joined : joined.substring(0, 2000);
  }

  bool get _hasTypedAcceptedReceiptLines =>
      handoff.kind == AiExtractionKind.receipt &&
      handoff.acceptedCandidates.isNotEmpty &&
      handoff.acceptedCandidates.every(
        (candidate) =>
            candidate.type == AiCandidateType.receiptLine &&
            candidate.status == AiCandidateReviewStatus.accepted &&
            candidate.receiptPayload != null,
      ) &&
      handoff.acceptedReceiptPayloads.length ==
          handoff.acceptedCandidates.length;

  bool get _hasConsistentHeaders {
    if (!_hasTypedAcceptedReceiptLines) return false;
    final signature = _headerSignature(lines.first.header);
    return lines.every((line) => _headerSignature(line.header) == signature);
  }

  String _headerSignature(AiReceiptHeaderPayload? value) => value == null
      ? ''
      : <Object?>[
          value.merchant,
          value.receiptNumber,
          value.purchaseDate?.toIso8601String(),
          value.currency,
          value.totalMinorUnits,
          value.taxMinorUnits,
          value.notes,
        ].join('\u0000');

  bool get _hasActiveAccess =>
      _mayWritePurchases &&
      _activeHomeId.isNotEmpty &&
      _activeHomeId == handoff.homeId;

  bool _stillAuthorized(int epoch) =>
      !_disposed && epoch == _accessEpoch && _hasActiveAccess;

  void _invalidate(String message) {
    _status = ReceiptAiHandoffStatus.invalidated;
    _safeMessage = message;
    _notify();
  }

  void _fail(String message) {
    _status = ReceiptAiHandoffStatus.failed;
    _safeMessage = message;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _accessEpoch++;
    super.dispose();
  }
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
