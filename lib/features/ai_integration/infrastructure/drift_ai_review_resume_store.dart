import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/security/intake_entity_id.dart';
import 'package:providentia/core/security/uuid_v4.dart';
import 'package:providentia/features/ai_integration/application/ai_review_resume_store.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';

final class DriftAiReviewResumeStore implements AiReviewResumeStore {
  DriftAiReviewResumeStore(
    this._database, {
    required this.homeId,
    required this.accountId,
  }) {
    if (!isUuid(homeId) || !isUuid(accountId))
      throw ArgumentError('Invalid AI resume scope.');
  }
  final AppDatabase _database;
  final String homeId;
  final String accountId;
  static const _type = ClientLocalRecordTypes.aiReviewResume;

  @override
  Future<List<AiReviewResumeReference>> list() async {
    final rows =
        await (_database.select(_database.localRecords)
              ..where(
                (row) =>
                    row.homeId.equals(homeId) & row.entityType.equals(_type),
              )
              ..orderBy(<OrderingTerm Function(LocalRecords)>[
                (row) => OrderingTerm.desc(row.updatedAt),
              ]))
            .get();
    final result = <AiReviewResumeReference>[];
    for (final row in rows) {
      final Object? decoded = jsonDecode(row.payload);
      if (decoded is! Map<String, Object?> || decoded['accountId'] != accountId)
        continue;
      final id = decoded['extractionId'];
      if (id is! String || !isUuid(id) || row.entityId != _id(id)) continue;
      final kind = switch (decoded['kind']) {
        'receipt' => AiExtractionKind.receipt,
        'stockPhoto' => AiExtractionKind.stockPhoto,
        _ => null,
      };
      if (kind != null)
        result.add(AiReviewResumeReference(extractionId: id, kind: kind));
      if (result.length == 20) break;
    }
    return List<AiReviewResumeReference>.unmodifiable(result);
  }

  @override
  Future<void> remember(AiReviewResumeReference reference) async {
    if (!isUuid(reference.extractionId))
      throw ArgumentError('Invalid extraction reference.');
    await _database
        .into(_database.localRecords)
        .insertOnConflictUpdate(
          LocalRecordsCompanion.insert(
            homeId: homeId,
            entityType: _type,
            entityId: _id(reference.extractionId),
            payload: jsonEncode(<String, Object?>{
              'accountId': accountId,
              'extractionId': reference.extractionId,
              'kind': reference.kind.name,
            }),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  String _id(String extractionId) => intakeEntityId(<String>[
    'review-resume',
    homeId,
    accountId,
    extractionId,
  ]);
}
