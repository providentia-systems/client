import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/core/database/drift_local_sync_repository.dart';
import 'package:providentia/core/synchronization/sync_models.dart';
import 'package:providentia/core/synchronization/sync_ports.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';

void main() {
  test(
    'feedback intent survives restart and a rejected intent stops suppressing the suggestion',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var index = 10;
      var repository = DriftHouseholdRepository(
        database,
        deviceId: _device,
        idGenerator: () => _id(index++),
      );
      final receipt = await repository.queueFeedback(
        OnlineSuggestionFeedback(
          homeId: _home,
          suggestionId: _suggestion,
          decision: OnlineSuggestionDecision.dismissed,
          resultQuantity: null,
          reason: 'Already stocked.',
        ),
      );
      repository = DriftHouseholdRepository(database, deviceId: _device);
      expect(await repository.decidedSuggestionIds(homeId: _home), {
        _suggestion,
      });
      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.entityId, receipt.id);
      expect(operation.operationType, 'shopping.suggestion-feedback.create');
      expect(
        (jsonDecode(operation.payload) as Map<String, Object?>)['suggestionId'],
        _suggestion,
      );
      final synchronization = DriftLocalSyncRepository(database);
      await synchronization.applyPushResults(
        now: DateTime.utc(2026, 9, 12),
        retryPolicy: RetryPolicy(),
        results: [
          PushOperationResult(
            operationId: operation.operationId,
            kind: PushResultKind.validationError,
            safeMessage: 'The suggestion changed.',
          ),
        ],
      );
      expect(await repository.decidedSuggestionIds(homeId: _home), isEmpty);
      expect(await repository.decidedSuggestionIds(homeId: _id(2)), isEmpty);
    },
  );

  test(
    'a second device reads verified line provenance and feedback without local metadata',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final sync = DriftLocalSyncRepository(database);
      final at = DateTime.utc(2026, 9, 12);
      await sync.applyPullPage(
        homeId: _home,
        page: PullPage(
          protocolVersion: 1,
          fromCursor: null,
          pageCursor: '3',
          highWaterCursor: '3',
          hasMore: false,
          requestId: 'test',
          changes: [
            RemoteChange(
              cursor: '1',
              homeId: _home,
              entityType: 'shopping-list',
              entityId: _id(4),
              kind: RemoteChangeKind.upsert,
              revision: 2,
              serverTimestamp: at,
              payload: {
                'name': 'Weekly shop',
                'kind': 'manual',
                'status': 'open',
              },
            ),
            RemoteChange(
              cursor: '2',
              homeId: _home,
              entityType: 'shopping-list-line',
              entityId: _id(5),
              kind: RemoteChangeKind.upsert,
              revision: 1,
              serverTimestamp: at,
              payload: {
                'listId': _id(4),
                'homeProductId': _id(6),
                'suggestionId': _suggestion,
                'selectedPackId': _id(7),
                'description': 'Rice',
                'source': 'suggested',
                'quantityToBuy': '3',
                'checked': false,
                'archived': false,
                'explanation':
                    'Suggested from household consumption and stock evidence.',
              },
            ),
            RemoteChange(
              cursor: '3',
              homeId: _home,
              entityType: 'shopping-suggestion-feedback',
              entityId: _id(5),
              kind: RemoteChangeKind.upsert,
              revision: 1,
              serverTimestamp: at,
              payload: {
                'suggestionId': _suggestion,
                'decision': 'edited',
                'resultQuantity': '3',
                'reason': 'Added.',
              },
            ),
          ],
        ),
      );
      final repository = DriftHouseholdRepository(database, deviceId: _device);
      final list = await repository.watchActiveList(homeId: _home).first;
      expect(list.lines.single.suggestionId, _suggestion);
      expect(list.lines.single.homeProductId, _id(6));
      expect(list.lines.single.selectedPackId, _id(7));
      expect(await repository.decidedSuggestionIds(homeId: _home), {
        _suggestion,
      });
      expect(
        await (database.select(database.localRecords)..where(
              (row) =>
                  row.entityType.equals('shopping-suggestion-line-link-v1'),
            ))
            .get(),
        isEmpty,
      );
    },
  );
}

String _id(int number) =>
    '01912345-6789-7abc-8def-${number.toString().padLeft(12, '0')}';
final _home = _id(1);
final _device = _id(3);
final _suggestion = _id(8);
