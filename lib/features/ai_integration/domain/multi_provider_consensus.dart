import 'dart:collection';

enum AiFieldImportance { supplementary, standard, critical }

enum AiDisagreementSeverity { none, notice, material, critical }

enum AiConsensusStatus { unanimous, qualified, disputed }

final class ComparableAiField {
  const ComparableAiField._({
    required this.path,
    required this.normalizedValue,
    required this.numericValue,
    required this.numericTolerance,
    required this.confidence,
    required this.importance,
  });

  factory ComparableAiField.text({
    required String path,
    required String? value,
    required double confidence,
    AiFieldImportance importance = AiFieldImportance.standard,
  }) => ComparableAiField._(
    path: _validatePath(path),
    normalizedValue: value == null ? null : _normalizeText(value),
    numericValue: null,
    numericTolerance: 0,
    confidence: _validateConfidence(confidence),
    importance: importance,
  );

  factory ComparableAiField.number({
    required String path,
    required double? value,
    required double confidence,
    double tolerance = 0.000001,
    AiFieldImportance importance = AiFieldImportance.standard,
  }) {
    if (value != null && !value.isFinite ||
        !tolerance.isFinite ||
        tolerance < 0) {
      throw const AiConsensusViolation(
        code: 'invalid_numeric_field',
        safeMessage: 'Numeric comparison metadata is invalid.',
      );
    }
    return ComparableAiField._(
      path: _validatePath(path),
      normalizedValue: value?.toString(),
      numericValue: value,
      numericTolerance: tolerance,
      confidence: _validateConfidence(confidence),
      importance: importance,
    );
  }

  final String path;
  final String? normalizedValue;
  final double? numericValue;
  final double numericTolerance;
  final double confidence;
  final AiFieldImportance importance;
}

final class AiProposalSnapshot<T> {
  AiProposalSnapshot({
    required this.providerId,
    required this.providerRevision,
    required this.proposal,
    required List<ComparableAiField> fields,
    required this.estimatedCostMinorUnits,
    required this.processingTime,
  }) : fields = UnmodifiableListView<ComparableAiField>(
         List<ComparableAiField>.of(fields),
       ) {
    if (providerId.trim().isEmpty ||
        providerRevision <= 0 ||
        fields.isEmpty ||
        estimatedCostMinorUnits < 0 ||
        processingTime < Duration.zero) {
      throw const AiConsensusViolation(
        code: 'invalid_proposal_snapshot',
        safeMessage: 'The provider proposal metadata is invalid.',
      );
    }
    final paths = <String>{};
    if (this.fields.any((field) => !paths.add(field.path))) {
      throw const AiConsensusViolation(
        code: 'duplicate_field_path',
        safeMessage: 'A provider returned the same field more than once.',
      );
    }
  }

  final String providerId;
  final int providerRevision;
  final T proposal;
  final List<ComparableAiField> fields;
  final int estimatedCostMinorUnits;
  final Duration processingTime;
}

final class AiFieldComparison {
  const AiFieldComparison({
    required this.path,
    required this.primary,
    required this.validator,
    required this.agreed,
    required this.severity,
    required this.consensusValue,
    required this.reasonCode,
  });

  final String path;
  final ComparableAiField? primary;
  final ComparableAiField? validator;
  final bool agreed;
  final AiDisagreementSeverity severity;
  final String? consensusValue;
  final String reasonCode;
}

final class AiConsensusReport {
  AiConsensusReport({
    required this.status,
    required List<AiFieldComparison> comparisons,
    required this.highestSeverity,
  }) : comparisons = UnmodifiableListView<AiFieldComparison>(comparisons);

  final AiConsensusStatus status;
  final List<AiFieldComparison> comparisons;
  final AiDisagreementSeverity highestSeverity;

  bool get hasMaterialDisagreement =>
      highestSeverity == AiDisagreementSeverity.material ||
      highestSeverity == AiDisagreementSeverity.critical;
}

final class AiConsensusViolation implements Exception {
  const AiConsensusViolation({required this.code, required this.safeMessage});

  final String code;
  final String safeMessage;

  @override
  String toString() => 'AiConsensusViolation($code): $safeMessage';
}

final class DeterministicAiConsensusEngine {
  const DeterministicAiConsensusEngine({
    this.confidenceNoticeThreshold = 0.35,
    this.materialConfidenceThreshold = 0.65,
  });

  final double confidenceNoticeThreshold;
  final double materialConfidenceThreshold;

  AiConsensusReport compare<T>({
    required AiProposalSnapshot<T> primary,
    required AiProposalSnapshot<T> validator,
  }) {
    if (primary.providerId == validator.providerId) {
      throw const AiConsensusViolation(
        code: 'validator_not_independent',
        safeMessage: 'The validator must be a different provider profile.',
      );
    }
    if (!_unitInterval(confidenceNoticeThreshold) ||
        !_unitInterval(materialConfidenceThreshold)) {
      throw const AiConsensusViolation(
        code: 'invalid_consensus_threshold',
        safeMessage: 'The consensus thresholds are invalid.',
      );
    }
    final primaryByPath = <String, ComparableAiField>{
      for (final field in primary.fields) field.path: field,
    };
    final validatorByPath = <String, ComparableAiField>{
      for (final field in validator.fields) field.path: field,
    };
    final paths = <String>{
      ...primaryByPath.keys,
      ...validatorByPath.keys,
    }.toList()..sort();
    final comparisons = <AiFieldComparison>[];
    var highest = AiDisagreementSeverity.none;
    for (final path in paths) {
      final comparison = _compareField(
        path,
        primaryByPath[path],
        validatorByPath[path],
      );
      comparisons.add(comparison);
      if (comparison.severity.index > highest.index) {
        highest = comparison.severity;
      }
    }
    final status = switch (highest) {
      AiDisagreementSeverity.none => AiConsensusStatus.unanimous,
      AiDisagreementSeverity.notice => AiConsensusStatus.qualified,
      AiDisagreementSeverity.material ||
      AiDisagreementSeverity.critical => AiConsensusStatus.disputed,
    };
    return AiConsensusReport(
      status: status,
      comparisons: comparisons,
      highestSeverity: highest,
    );
  }

  AiFieldComparison _compareField(
    String path,
    ComparableAiField? primary,
    ComparableAiField? validator,
  ) {
    if (primary == null || validator == null) {
      final present = primary ?? validator!;
      final severity = _severityForMissing(present);
      return AiFieldComparison(
        path: path,
        primary: primary,
        validator: validator,
        agreed: false,
        severity: severity,
        consensusValue: null,
        reasonCode: 'field_missing_from_one_provider',
      );
    }
    final valuesAgree = _valuesAgree(primary, validator);
    if (!valuesAgree) {
      return AiFieldComparison(
        path: path,
        primary: primary,
        validator: validator,
        agreed: false,
        severity: _severityForMismatch(primary, validator),
        consensusValue: null,
        reasonCode: 'value_mismatch',
      );
    }
    final confidenceGap = (primary.confidence - validator.confidence).abs();
    final severity = confidenceGap > confidenceNoticeThreshold
        ? AiDisagreementSeverity.notice
        : AiDisagreementSeverity.none;
    return AiFieldComparison(
      path: path,
      primary: primary,
      validator: validator,
      agreed: true,
      severity: severity,
      consensusValue: primary.normalizedValue,
      reasonCode: severity == AiDisagreementSeverity.none
          ? 'values_agree'
          : 'values_agree_confidence_differs',
    );
  }

  bool _valuesAgree(ComparableAiField left, ComparableAiField right) {
    if (left.numericValue != null || right.numericValue != null) {
      if (left.numericValue == null || right.numericValue == null) {
        return false;
      }
      final tolerance = left.numericTolerance > right.numericTolerance
          ? left.numericTolerance
          : right.numericTolerance;
      return (left.numericValue! - right.numericValue!).abs() <= tolerance;
    }
    return left.normalizedValue == right.normalizedValue;
  }

  AiDisagreementSeverity _severityForMissing(ComparableAiField present) =>
      switch (present.importance) {
        AiFieldImportance.critical => AiDisagreementSeverity.critical,
        AiFieldImportance.standard =>
          present.confidence >= materialConfidenceThreshold
              ? AiDisagreementSeverity.material
              : AiDisagreementSeverity.notice,
        AiFieldImportance.supplementary => AiDisagreementSeverity.notice,
      };

  AiDisagreementSeverity _severityForMismatch(
    ComparableAiField primary,
    ComparableAiField validator,
  ) {
    final importance = primary.importance.index > validator.importance.index
        ? primary.importance
        : validator.importance;
    return switch (importance) {
      AiFieldImportance.critical => AiDisagreementSeverity.critical,
      AiFieldImportance.standard =>
        primary.confidence >= materialConfidenceThreshold ||
                validator.confidence >= materialConfidenceThreshold
            ? AiDisagreementSeverity.material
            : AiDisagreementSeverity.notice,
      AiFieldImportance.supplementary => AiDisagreementSeverity.notice,
    };
  }
}

String _validatePath(String value) {
  final path = value.trim();
  if (path.isEmpty || path.length > 240) {
    throw const AiConsensusViolation(
      code: 'invalid_field_path',
      safeMessage: 'A comparison field path is invalid.',
    );
  }
  return path;
}

String _normalizeText(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double _validateConfidence(double value) {
  if (!_unitInterval(value)) {
    throw const AiConsensusViolation(
      code: 'invalid_field_confidence',
      safeMessage: 'A provider field confidence is invalid.',
    );
  }
  return value;
}

bool _unitInterval(double value) => value.isFinite && value >= 0 && value <= 1;
