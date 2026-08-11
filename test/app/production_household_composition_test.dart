import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';

void main() {
  test(
    'production household composition binds device and foreground sync trigger',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      var generated = 0;
      var foregroundSyncs = 0;
      final repository = createProductionHouseholdRepository(
        database: database,
        deviceId: _deviceId,
        clock: () => DateTime.utc(2026, 8, 11, 9),
        idGenerator: () => generated++ == 0 ? _listId : _operationId,
        onMutationCommitted: () async {
          foregroundSyncs++;
        },
      );

      await repository.ensureHomeInitialized(homeId: _homeId);

      final operation = await database
          .select(database.clientOperations)
          .getSingle();
      expect(operation.deviceId, _deviceId);
      expect(operation.homeId, _homeId);
      expect(operation.entityType, 'shopping-list');
      expect(operation.operationType, 'shopping.list.create');
      expect(foregroundSyncs, 1);
    },
  );

  test('production household composition rejects a non-UUID device', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    expect(
      () => createProductionHouseholdRepository(
        database: database,
        deviceId: 'browser-device',
        onMutationCommitted: () async {},
      ),
      throwsArgumentError,
    );
  });

  test('production AI extraction identifiers are distinct RFC 4122 UUIDv4', () {
    final identifiers = ProductionAiIdentifierFactory();

    final first = identifiers.nextId();
    final second = identifiers.nextId();

    expect(first, matches(_uuidV4));
    expect(second, matches(_uuidV4));
    expect(second, isNot(first));
  });

  test('production AI preparation drops picker-owned source bytes', () async {
    final sources = RegisteredMediaSourceReader();
    final asset = AiMediaAsset(
      id: 'source-private',
      homeId: _homeId,
      localReference: 'registered://private.jpg',
      purpose: AiExtractionKind.receipt,
      mimeType: 'image/jpeg',
      byteLength: 16,
      createdAt: DateTime.utc(2026, 8, 11),
    );
    sources.register(asset, Uint8List(16));
    final preparer = ProductionRegisteredSourceClearingMediaPreparer(
      delegate: _PreparedMediaDelegate(),
      sources: sources,
    );

    await preparer.prepare(
      homeId: _homeId,
      purpose: AiExtractionKind.receipt,
      assets: <AiMediaAsset>[asset],
    );

    expect(sources.registeredIds, isEmpty);
  });

  test(
    'production AI preparation drops sources after sanitizer failure',
    () async {
      final sources = RegisteredMediaSourceReader();
      final asset = AiMediaAsset(
        id: 'source-invalid',
        homeId: _homeId,
        localReference: 'registered://invalid.jpg',
        purpose: AiExtractionKind.receipt,
        mimeType: 'image/jpeg',
        byteLength: 16,
        createdAt: DateTime.utc(2026, 8, 11),
      );
      sources.register(asset, Uint8List(16));
      final preparer = ProductionRegisteredSourceClearingMediaPreparer(
        delegate: _FailingMediaDelegate(),
        sources: sources,
      );

      await expectLater(
        preparer.prepare(
          homeId: _homeId,
          purpose: AiExtractionKind.receipt,
          assets: <AiMediaAsset>[asset],
        ),
        throwsStateError,
      );

      expect(sources.registeredIds, isEmpty);
    },
  );
}

final class _PreparedMediaDelegate implements AiMediaPreparationPort {
  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async => PreparedMediaBatch(
    id: 'prepared-private',
    homeId: homeId,
    purpose: purpose,
    media: <PreparedAiMedia>[
      PreparedAiMedia(
        sourceMediaId: assets.single.id,
        ephemeralReference: 'ephemeral://private',
        previewReference: 'ephemeral://private',
        sha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        mimeType: 'image/jpeg',
        byteLength: 16,
        width: 1,
        height: 1,
        pageIndex: 0,
      ),
    ],
  );

  @override
  Future<void> discard(PreparedMediaBatch batch) async {}
}

final class _FailingMediaDelegate implements AiMediaPreparationPort {
  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async => throw StateError('invalid image');

  @override
  Future<void> discard(PreparedMediaBatch batch) async {}
}

const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _deviceId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const _listId = '0198a0b1-c2d3-7e4f-8567-89abcdef0123';
const _operationId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
