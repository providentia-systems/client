import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/core/security/intake_entity_id.dart';
import 'package:providentia/features/ai_integration/application/ai_review_resume_store.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/drift_ai_review_resume_store.dart';

void main() {
  late AppDatabase database;
  setUp(() { database = AppDatabase(NativeDatabase.memory()); });
  tearDown(() async { await database.close(); });
  test('resume IDs are durable, idempotent and account/home isolated without cached evidence', () async {
    final alice = DriftAiReviewResumeStore(database, homeId: _home, accountId: _alice);
    final bob = DriftAiReviewResumeStore(database, homeId: _home, accountId: _bob);
    const reference = AiReviewResumeReference(extractionId: _extract, kind: AiExtractionKind.receipt);
    await alice.remember(reference);
    await alice.remember(reference);
    await bob.remember(const AiReviewResumeReference(extractionId: _extract, kind: AiExtractionKind.stockPhoto));
    expect((await alice.list()).single.kind, AiExtractionKind.receipt);
    expect((await bob.list()).single.kind, AiExtractionKind.stockPhoto);
    expect(await DriftAiReviewResumeStore(database, homeId: _bob, accountId: _alice).list(), isEmpty);
    final rows = await database.select(database.localRecords).get();
    expect(rows, hasLength(2));
    for (final row in rows) {
      final payload = jsonDecode(row.payload) as Map<String, dynamic>;
      expect(payload.keys, unorderedEquals(['accountId', 'extractionId', 'kind']));
      expect(row.entityType, ClientLocalRecordTypes.aiReviewResume);
      expect(payload['extractionId'], _extract);
    }
    final reopenedStore = DriftAiReviewResumeStore(database, homeId: _home, accountId: _alice);
    expect((await reopenedStore.list()).single.extractionId, _extract);
  });
  test('corrupt, unbound, foreign and unknown-kind hints cannot become extraction requests', () async {
    final store = DriftAiReviewResumeStore(database, homeId: _home, accountId: _alice);
    final valid = {'accountId': _alice, 'extractionId': _extract, 'kind': 'receipt'};
    final payloads = ['{', '[]', jsonEncode({...valid, 'accountId': _bob}), jsonEncode({...valid, 'extractionId': 'invalid'}), jsonEncode(valid)];
    for (var i = 0; i < payloads.length; i++) {
      await database.into(database.localRecords).insert(LocalRecordsCompanion.insert(homeId: _home, entityType: ClientLocalRecordTypes.aiReviewResume, entityId: 'unbound-$i', payload: payloads[i], updatedAt: DateTime.now().toUtc()));
    }
    await database.into(database.localRecords).insert(LocalRecordsCompanion.insert(homeId: _home, entityType: ClientLocalRecordTypes.aiReviewResume, entityId: intakeEntityId(['review-resume', _home, _alice, _extract]), payload: jsonEncode({...valid, 'kind': 'unknown'}), updatedAt: DateTime.now().toUtc()));
    expect(await store.list(), isEmpty);
    await store.remember(const AiReviewResumeReference(extractionId: _extract, kind: AiExtractionKind.receipt));
    expect((await store.list()).single.extractionId, _extract);
  });
  test('recent review list is bounded without losing original stored references', () async {
    final store = DriftAiReviewResumeStore(database, homeId: _home, accountId: _alice);
    for (var i = 0; i < 22; i++) {
      await store.remember(AiReviewResumeReference(extractionId: '55555555-5555-4555-8555-${i.toString().padLeft(12, '0')}', kind: AiExtractionKind.receipt));
    }
    final references = await store.list();
    expect(references, hasLength(20));
    expect((await database.select(database.localRecords).get()), hasLength(22));
    expect(() => references.clear(), throwsUnsupportedError);
  });
  test('invalid scope and extraction identifiers fail before persistence', () async {
    expect(() => DriftAiReviewResumeStore(database, homeId: '', accountId: _alice), throwsArgumentError);
    expect(() => DriftAiReviewResumeStore(database, homeId: _home, accountId: ''), throwsArgumentError);
    final store = DriftAiReviewResumeStore(database, homeId: _home, accountId: _alice);
    await expectLater(store.remember(const AiReviewResumeReference(extractionId: 'bad', kind: AiExtractionKind.receipt)), throwsArgumentError);
    expect(await database.select(database.localRecords).get(), isEmpty);
  });
}
const _home = '11111111-1111-4111-8111-111111111111';
const _alice = '22222222-2222-4222-8222-222222222222';
const _bob = '33333333-3333-4333-8333-333333333333';
const _extract = '44444444-4444-4444-8444-444444444444';
