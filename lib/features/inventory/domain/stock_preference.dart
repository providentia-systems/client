import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';

/// The backend replenishment policy, separate from factual stock quantities.
final class StockPreference {
  StockPreference({
    required this.homeId,
    required this.homeProductId,
    required this.revision,
    this.minimumQuantity,
    this.alwaysKeep = false,
    this.neverSuggest = false,
    this.preferredPackId,
    this.leadTimeDays = 0,
    this.targetCoverageDays,
    this.snoozeUntil,
  }) {
    if (!isUuid(homeId) ||
        !isUuid(homeProductId) ||
        revision < 0 ||
        (preferredPackId != null && !isUuid(preferredPackId!))) {
      throw ArgumentError('Invalid stock preference identity or revision.');
    }
    if (minimumQuantity != null &&
        !ExactDecimal(minimumQuantity!).isNonNegative) {
      throw ArgumentError('Minimum stock cannot be negative.');
    }
    if (leadTimeDays < 0 ||
        leadTimeDays > 365 ||
        (targetCoverageDays != null &&
            (targetCoverageDays! < 1 || targetCoverageDays! > 365))) {
      throw ArgumentError('Enter lead time 0–365 and coverage 1–365 days.');
    }
    if (snoozeUntil != null) {
      final parsed = DateTime.tryParse(snoozeUntil!);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(snoozeUntil!) ||
          parsed == null ||
          parsed.toIso8601String().substring(0, 10) != snoozeUntil) {
        throw ArgumentError('Enter a valid date as YYYY-MM-DD.');
      }
    }
  }

  factory StockPreference.fromFields({
    required String homeId,
    required String homeProductId,
    required int revision,
    required Map<String, Object?> fields,
  }) {
    if ((fields['homeId'] != null && fields['homeId'] != homeId) ||
        (fields['homeProductId'] != null &&
            fields['homeProductId'] != homeProductId)) {
      throw const FormatException('Stock preference scope does not match.');
    }
    return StockPreference(
      homeId: homeId,
      homeProductId: homeProductId,
      revision: revision,
      minimumQuantity: fields['minimumQuantity'] as String?,
      alwaysKeep: fields['alwaysKeep']! as bool,
      neverSuggest: fields['neverSuggest']! as bool,
      preferredPackId: fields['preferredPackId'] as String?,
      leadTimeDays: fields['leadTimeDays']! as int,
      targetCoverageDays: fields['targetCoverageDays'] as int?,
      snoozeUntil: fields['snoozeUntil'] as String?,
    );
  }

  final String homeId;
  final String homeProductId;
  final int revision;
  final String? minimumQuantity;
  final bool alwaysKeep;
  final bool neverSuggest;
  final String? preferredPackId;
  final int leadTimeDays;
  final int? targetCoverageDays;
  final String? snoozeUntil;

  Map<String, Object?> get fields => {
    'minimumQuantity': minimumQuantity,
    'alwaysKeep': alwaysKeep,
    'neverSuggest': neverSuggest,
    'preferredPackId': preferredPackId,
    'leadTimeDays': leadTimeDays,
    'targetCoverageDays': targetCoverageDays,
    'snoozeUntil': snoozeUntil,
  };
}
