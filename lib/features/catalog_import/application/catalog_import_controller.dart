import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:providentia/features/catalog_import/application/catalog_import_ports.dart';
import 'package:providentia/features/catalog_import/domain/catalog_import_models.dart';
import 'package:providentia/features/catalog_import/domain/spreadsheet_models.dart';

enum CatalogImportPhase {
  idle,
  loadingFile,
  mapping,
  staging,
  review,
  confirming,
  completed,
  accessDenied,
}

/// One planned batch of at most 500 records with the idempotency key that is
/// reused verbatim on every retry of the same staged content.
final class CatalogImportBatchSlot {
  CatalogImportBatchSlot({
    required this.index,
    required List<Map<String, Object?>> records,
    required this.idempotencyKey,
    this.batch,
  }) : records = UnmodifiableListView<Map<String, Object?>>(
         List<Map<String, Object?>>.of(records),
       ) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must not be negative');
    }
    if (records.isEmpty ||
        records.length > CatalogImportPolicy.maxRecordsPerStage) {
      throw ArgumentError.value(
        records.length,
        'records',
        'must contain 1 through ${CatalogImportPolicy.maxRecordsPerStage} '
            'records',
      );
    }
    if (idempotencyKey.length < 8 || idempotencyKey.length > 128) {
      throw ArgumentError.value(
        idempotencyKey,
        'idempotencyKey',
        'must be 8 through 128 characters',
      );
    }
  }

  final int index;
  final List<Map<String, Object?>> records;
  final String idempotencyKey;
  final CatalogImportBatchView? batch;

  bool get isStaged => batch != null;
  bool get isConfirmed => batch?.isConfirmed ?? false;

  CatalogImportBatchSlot withBatch(CatalogImportBatchView batch) =>
      CatalogImportBatchSlot(
        index: index,
        records: records,
        idempotencyKey: idempotencyKey,
        batch: batch,
      );
}

final class CatalogImportState {
  CatalogImportState({
    required this.phase,
    this.busy = false,
    this.grid,
    this.hasHeaderRow = true,
    this.recordType = CatalogImportRecordType.homeProduct,
    this.mapping = CatalogImportColumnMapping.empty,
    this.validation,
    List<CatalogImportBatchSlot> batches = const <CatalogImportBatchSlot>[],
    this.safeMessage,
  }) : batches = UnmodifiableListView<CatalogImportBatchSlot>(
         List<CatalogImportBatchSlot>.of(batches),
       );

  const CatalogImportState.idle()
    : phase = CatalogImportPhase.idle,
      busy = false,
      grid = null,
      hasHeaderRow = true,
      recordType = CatalogImportRecordType.homeProduct,
      mapping = CatalogImportColumnMapping.empty,
      validation = null,
      batches = const <CatalogImportBatchSlot>[],
      safeMessage = null;

  final CatalogImportPhase phase;
  final bool busy;
  final SpreadsheetGrid? grid;
  final bool hasHeaderRow;
  final CatalogImportRecordType recordType;
  final CatalogImportColumnMapping mapping;
  final CatalogImportValidation? validation;
  final List<CatalogImportBatchSlot> batches;
  final String? safeMessage;

  List<CatalogImportBatchView> get stagedBatches =>
      List<CatalogImportBatchView>.unmodifiable(<CatalogImportBatchView>[
        for (final slot in batches)
          if (slot.batch != null) slot.batch!,
      ]);

  int get stagedBatchCount => batches.where((slot) => slot.isStaged).length;

  int get confirmedBatchCount =>
      batches.where((slot) => slot.isConfirmed).length;

  /// Totals across staged batches; final once the phase is [completed].
  CatalogImportReconciliation get reconciliation =>
      CatalogImportReconciliation.of(stagedBatches);
}

/// Explicit spreadsheet-to-catalog import workflow for one authorized home:
/// pick, parse, map columns, validate, stage in contract-sized batches,
/// review the server resolutions, and apply them behind one explicit
/// confirmation.
///
/// A multi-batch import stages every batch sequentially first and then shows
/// one combined review; a single explicit confirmation applies the staged
/// batches in order. This keeps one review and one decision regardless of
/// file size, at the cost of applying batches one revision at a time.
final class CatalogImportController extends ChangeNotifier {
  factory CatalogImportController({
    required String homeId,
    required CatalogImportGateway gateway,
    required SpreadsheetFilePick pickFile,
    required SpreadsheetTableParser parser,
    required String Function() idGenerator,
    Future<void> Function()? onAuthorizationLost,
  }) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    return CatalogImportController._(
      homeId,
      gateway,
      pickFile,
      parser,
      idGenerator,
      onAuthorizationLost,
    );
  }

  CatalogImportController._(
    this.homeId,
    this._gateway,
    this._pickFile,
    this._parser,
    this._idGenerator,
    this._onAuthorizationLost,
  );

  final String homeId;
  final CatalogImportGateway _gateway;
  final SpreadsheetFilePick _pickFile;
  final SpreadsheetTableParser _parser;
  final String Function() _idGenerator;
  final Future<void> Function()? _onAuthorizationLost;

  CatalogImportState _state = const CatalogImportState.idle();
  int _generation = 0;
  bool _disposed = false;

  CatalogImportState get state => _state;

  /// Opens the platform chooser and parses the selection into a mapped
  /// preview. Cancelling keeps the current state untouched.
  Future<void> pickSpreadsheet() async {
    if (_state.busy ||
        !const <CatalogImportPhase>{
          CatalogImportPhase.idle,
          CatalogImportPhase.mapping,
          CatalogImportPhase.completed,
        }.contains(_state.phase)) {
      return;
    }
    final generation = ++_generation;
    final previous = _state;
    _setState(
      CatalogImportState(phase: CatalogImportPhase.loadingFile, busy: true),
    );
    try {
      final file = await _pickFile();
      if (!_isCurrent(generation)) return;
      if (file == null) {
        _setState(previous);
        return;
      }
      final grid = _parser.parse(file);
      if (!_isCurrent(generation)) return;
      const hasHeaderRow = true;
      final mapping = CatalogImportColumnMapping.fromHeaders(grid.rows.first);
      _setState(
        CatalogImportState(
          phase: CatalogImportPhase.mapping,
          grid: grid,
          mapping: mapping,
          validation: _validate(
            grid: grid,
            mapping: mapping,
            recordType: previous.recordType,
            hasHeaderRow: hasHeaderRow,
          ),
          recordType: previous.recordType,
        ),
      );
    } on SpreadsheetSelectionException catch (error) {
      _restoreAfterPickFailure(generation, previous, error.safeMessage);
    } on SpreadsheetParseException catch (error) {
      _restoreAfterPickFailure(generation, previous, error.safeMessage);
    } on Exception {
      _restoreAfterPickFailure(
        generation,
        previous,
        'The selected file could not be read on this device.',
      );
    }
  }

  void assignColumn(int column, CatalogImportField? field) {
    final grid = _state.grid;
    if (_state.phase != CatalogImportPhase.mapping || grid == null) return;
    final mapping = _state.mapping.assign(column, field);
    _setState(
      CatalogImportState(
        phase: CatalogImportPhase.mapping,
        grid: grid,
        hasHeaderRow: _state.hasHeaderRow,
        recordType: _state.recordType,
        mapping: mapping,
        validation: _validate(
          grid: grid,
          mapping: mapping,
          recordType: _state.recordType,
          hasHeaderRow: _state.hasHeaderRow,
        ),
      ),
    );
  }

  void selectRecordType(CatalogImportRecordType recordType) {
    final grid = _state.grid;
    if (_state.phase != CatalogImportPhase.mapping || grid == null) return;
    _setState(
      CatalogImportState(
        phase: CatalogImportPhase.mapping,
        grid: grid,
        hasHeaderRow: _state.hasHeaderRow,
        recordType: recordType,
        mapping: _state.mapping,
        validation: _validate(
          grid: grid,
          mapping: _state.mapping,
          recordType: recordType,
          hasHeaderRow: _state.hasHeaderRow,
        ),
      ),
    );
  }

  void setHasHeaderRow(bool hasHeaderRow) {
    final grid = _state.grid;
    if (_state.phase != CatalogImportPhase.mapping || grid == null) return;
    _setState(
      CatalogImportState(
        phase: CatalogImportPhase.mapping,
        grid: grid,
        hasHeaderRow: hasHeaderRow,
        recordType: _state.recordType,
        mapping: _state.mapping,
        validation: _validate(
          grid: grid,
          mapping: _state.mapping,
          recordType: _state.recordType,
          hasHeaderRow: hasHeaderRow,
        ),
      ),
    );
  }

  /// Stages the validated records in contract-sized batches. A retry after a
  /// transport failure resumes with the first unstaged batch and replays each
  /// batch's persisted idempotency key exactly.
  Future<void> stage() async {
    final resuming = _state.phase == CatalogImportPhase.staging && !_state.busy;
    List<CatalogImportBatchSlot> slots;
    if (resuming) {
      slots = _state.batches;
    } else {
      final validation = _state.validation;
      if (_state.phase != CatalogImportPhase.mapping ||
          validation == null ||
          !validation.mayStage) {
        return;
      }
      final partitions = CatalogImportPolicy.partition(<Map<String, Object?>>[
        for (final record in validation.records) record.wireRecord,
      ]);
      slots = <CatalogImportBatchSlot>[
        for (var index = 0; index < partitions.length; index++)
          CatalogImportBatchSlot(
            index: index,
            records: partitions[index],
            idempotencyKey: _idGenerator(),
          ),
      ];
    }
    final generation = ++_generation;
    _setState(
      _transferState(
        phase: CatalogImportPhase.staging,
        busy: true,
        batches: slots,
      ),
    );
    for (final slot in slots) {
      if (slot.isStaged) continue;
      try {
        final batch = await _gateway.stage(
          homeId: homeId,
          idempotencyKey: slot.idempotencyKey,
          records: slot.records,
        );
        if (!_isCurrent(generation)) return;
        slots = _replaceSlot(slots, slot.withBatch(batch));
        _setState(
          _transferState(
            phase: CatalogImportPhase.staging,
            busy: true,
            batches: slots,
          ),
        );
      } on CatalogImportAuthenticationRequiredException {
        await _denyAccess(generation);
        return;
      } on CatalogImportForbiddenException {
        await _denyAccess(generation);
        return;
      } on CatalogImportValidationException {
        _rejectStagedContent(
          generation,
          'The server rejected these rows. Adjust the mapping and try again.',
        );
        return;
      } on CatalogImportTooLargeException {
        _rejectStagedContent(
          generation,
          'This import is too large for the service. Split the file and '
          'try again.',
        );
        return;
      } on Exception {
        if (!_isCurrent(generation)) return;
        _setState(
          _transferState(
            phase: CatalogImportPhase.staging,
            busy: false,
            batches: slots,
            safeMessage:
                'Staging paused before batch ${slot.index + 1} of '
                '${slots.length}. Nothing was applied; retry to continue.',
          ),
        );
        return;
      }
    }
    if (!_isCurrent(generation)) return;
    _setState(
      _transferState(
        phase: CatalogImportPhase.review,
        busy: false,
        batches: slots,
      ),
    );
  }

  /// Applies every staged batch in order at its expected revision. A revision
  /// conflict refetches that batch and returns to review for a new explicit
  /// confirmation; batches confirmed before the conflict stay applied.
  Future<void> confirmStagedBatches() async {
    if (_state.phase != CatalogImportPhase.review || _state.busy) return;
    var slots = _state.batches;
    if (slots.isEmpty || slots.any((slot) => !slot.isStaged)) return;
    final generation = ++_generation;
    _setState(
      _transferState(
        phase: CatalogImportPhase.confirming,
        busy: true,
        batches: slots,
      ),
    );
    for (final slot in slots) {
      final staged = slot.batch;
      if (staged == null || staged.isConfirmed) continue;
      try {
        final confirmed = await _gateway.confirm(
          homeId: homeId,
          importId: staged.id,
          expectedRevision: staged.revision,
        );
        if (!_isCurrent(generation)) return;
        slots = _replaceSlot(slots, slot.withBatch(confirmed));
        _setState(
          _transferState(
            phase: CatalogImportPhase.confirming,
            busy: true,
            batches: slots,
          ),
        );
      } on CatalogImportConflictException {
        await _refetchAfterConflict(generation, slots, slot, staged.id);
        return;
      } on CatalogImportAuthenticationRequiredException {
        await _denyAccess(generation);
        return;
      } on CatalogImportForbiddenException {
        await _denyAccess(generation);
        return;
      } on Exception {
        if (!_isCurrent(generation)) return;
        _setState(
          _transferState(
            phase: CatalogImportPhase.review,
            busy: false,
            batches: slots,
            safeMessage:
                'Confirmation paused at batch ${slot.index + 1} of '
                '${slots.length}. Confirmed batches stay applied; confirm '
                'again to continue.',
          ),
        );
        return;
      }
    }
    if (!_isCurrent(generation)) return;
    _setState(
      _transferState(
        phase: CatalogImportPhase.completed,
        busy: false,
        batches: slots,
      ),
    );
  }

  /// Returns to the empty pick step, discarding parsed rows and any staged
  /// but unconfirmed review state.
  void reset() {
    _generation += 1;
    _setState(const CatalogImportState.idle());
  }

  /// Route-boundary hook: clears every parsed row, mapping, and staged
  /// review projection.
  void clearSensitiveState() => reset();

  Future<void> _refetchAfterConflict(
    int generation,
    List<CatalogImportBatchSlot> slots,
    CatalogImportBatchSlot slot,
    String importId,
  ) async {
    var refreshed = slots;
    var message =
        'This import changed elsewhere. Review the updated resolutions and '
        'confirm again.';
    try {
      final latest = await _gateway.fetch(homeId: homeId, importId: importId);
      refreshed = _replaceSlot(slots, slot.withBatch(latest));
    } on CatalogImportAuthenticationRequiredException {
      await _denyAccess(generation);
      return;
    } on CatalogImportForbiddenException {
      await _denyAccess(generation);
      return;
    } on Exception {
      message =
          'This import changed elsewhere and could not be re-read. Try '
          'confirming again.';
    }
    if (!_isCurrent(generation)) return;
    _setState(
      _transferState(
        phase: CatalogImportPhase.review,
        busy: false,
        batches: refreshed,
        safeMessage: message,
      ),
    );
  }

  void _rejectStagedContent(int generation, String message) {
    final grid = _state.grid;
    if (!_isCurrent(generation) || grid == null) return;
    _setState(
      CatalogImportState(
        phase: CatalogImportPhase.mapping,
        grid: grid,
        hasHeaderRow: _state.hasHeaderRow,
        recordType: _state.recordType,
        mapping: _state.mapping,
        validation: _validate(
          grid: grid,
          mapping: _state.mapping,
          recordType: _state.recordType,
          hasHeaderRow: _state.hasHeaderRow,
        ),
        safeMessage: message,
      ),
    );
  }

  Future<void> _denyAccess(int generation) async {
    if (!_isCurrent(generation)) return;
    _setState(
      CatalogImportState(
        phase: CatalogImportPhase.accessDenied,
        safeMessage: 'This home no longer allows spreadsheet imports for you.',
      ),
    );
    await _onAuthorizationLost?.call();
  }

  void _restoreAfterPickFailure(
    int generation,
    CatalogImportState previous,
    String message,
  ) {
    if (!_isCurrent(generation)) return;
    _setState(
      CatalogImportState(
        phase: previous.phase,
        grid: previous.grid,
        hasHeaderRow: previous.hasHeaderRow,
        recordType: previous.recordType,
        mapping: previous.mapping,
        validation: previous.validation,
        batches: previous.batches,
        safeMessage: message,
      ),
    );
  }

  CatalogImportState _transferState({
    required CatalogImportPhase phase,
    required bool busy,
    required List<CatalogImportBatchSlot> batches,
    String? safeMessage,
  }) => CatalogImportState(
    phase: phase,
    busy: busy,
    grid: _state.grid,
    hasHeaderRow: _state.hasHeaderRow,
    recordType: _state.recordType,
    mapping: _state.mapping,
    validation: _state.validation,
    batches: batches,
    safeMessage: safeMessage,
  );

  static CatalogImportValidation _validate({
    required SpreadsheetGrid grid,
    required CatalogImportColumnMapping mapping,
    required CatalogImportRecordType recordType,
    required bool hasHeaderRow,
  }) => CatalogImportValidation.of(
    grid: grid,
    mapping: mapping,
    recordType: recordType,
    hasHeaderRow: hasHeaderRow,
  );

  static List<CatalogImportBatchSlot> _replaceSlot(
    List<CatalogImportBatchSlot> slots,
    CatalogImportBatchSlot replacement,
  ) => List<CatalogImportBatchSlot>.unmodifiable(<CatalogImportBatchSlot>[
    for (final slot in slots)
      if (slot.index == replacement.index) replacement else slot,
  ]);

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(CatalogImportState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation += 1;
    super.dispose();
  }
}
