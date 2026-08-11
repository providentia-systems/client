import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/ai_integration/application/strict_local_provider_configuration.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/api17_ai_gateway.dart';
import 'package:providentia/features/ai_integration/infrastructure/drift_strict_local_provider_configuration_store.dart';
import 'package:providentia/features/ai_integration/infrastructure/strict_local_home_ai_composition.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';

void main() {
  late AppDatabase database;
  late DriftStrictLocalProviderConfigurationStore store;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftStrictLocalProviderConfigurationStore(
      database,
      clock: () => DateTime.utc(2026, 8, 11),
    );
  });

  tearDown(() => database.close());

  test('profiles and active selection are isolated by home', () async {
    await store.save(_configuration(homeId: 'home-a', profileId: 'profile-a'));
    await store.save(_configuration(homeId: 'home-b', profileId: 'profile-b'));
    await store.setActiveProfileId(homeId: 'home-a', profileId: 'profile-a');

    expect(await store.listForHome('home-a'), hasLength(1));
    expect(await store.listForHome('home-b'), hasLength(1));
    expect(await store.readActiveProfileId('home-a'), 'profile-a');
    expect(await store.readActiveProfileId('home-b'), isNull);
    final operations = await database.select(database.clientOperations).get();
    expect(operations, isEmpty, reason: 'local settings must never enter sync');
  });

  test('atomic replacement rejects stale and split-brain revisions', () async {
    final initial = _configuration(homeId: 'home-a', profileId: 'profile-a');
    await store.save(initial);
    await expectLater(
      store.save(
        _configuration(
          homeId: 'home-a',
          profileId: 'profile-a',
          displayName: 'Different same revision',
        ),
      ),
      throwsStateError,
    );
    await store.save(
      _configuration(
        homeId: 'home-a',
        profileId: 'profile-a',
        displayName: 'Updated',
        revision: 2,
      ),
    );

    expect(
      (await store.findById(
        homeId: 'home-a',
        profileId: 'profile-a',
      ))!.displayName,
      'Updated',
    );
  });

  test('strict decode rejects payload/key mismatch', () async {
    final configuration = _configuration(
      homeId: 'home-a',
      profileId: 'payload-profile',
    );
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: 'home-a',
            entityType: DriftStrictLocalProviderConfigurationStore
                .configurationRecordType,
            entityId: 'storage-profile',
            payload: jsonEncode(configuration.toJson()),
            revision: const Value<int>(1),
            updatedAt: DateTime.utc(2026, 8, 11),
          ),
        );

    await expectLater(store.listForHome('home-a'), throwsFormatException);
  });

  test('dangling active local selection fails closed', () async {
    await store.save(_configuration(homeId: 'home-a', profileId: 'profile-a'));
    await store.setActiveProfileId(homeId: 'home-a', profileId: 'profile-a');
    await (database.delete(database.localRecords)
          ..where((row) => row.homeId.equals('home-a'))
          ..where(
            (row) => row.entityType.equals(
              DriftStrictLocalProviderConfigurationStore
                  .configurationRecordType,
            ),
          ))
        .go();

    await expectLater(
      store.readActiveProfileId('home-a'),
      throwsFormatException,
    );
  });

  test(
    'delete clears active selection and revocation purges all rows',
    () async {
      await store.save(
        _configuration(homeId: 'home-a', profileId: 'profile-a'),
      );
      await store.setActiveProfileId(homeId: 'home-a', profileId: 'profile-a');
      await store.delete(homeId: 'home-a', profileId: 'profile-a');
      expect(await store.readActiveProfileId('home-a'), isNull);

      await store.save(
        _configuration(homeId: 'home-a', profileId: 'profile-a'),
      );
      await store.setActiveProfileId(homeId: 'home-a', profileId: 'profile-a');
      await RevokedHomeDataPurger(database).purge('home-a');

      expect(await store.listForHome('home-a'), isEmpty);
      expect(await store.readActiveProfileId('home-a'), isNull);
    },
  );

  test('home composition exposes active strict-local stock route', () async {
    final composition = StrictLocalHomeAiComposition.create(
      database: database,
      homeId: 'home-a',
      mediaReader: const _NoMediaReader(),
      idGenerator: () => 'profile-a',
    );
    addTearDown(composition.dispose);
    await composition.store.save(
      _configuration(homeId: 'home-a', profileId: 'profile-a'),
    );
    await composition.store.setActiveProfileId(
      homeId: 'home-a',
      profileId: 'profile-a',
    );

    final route = await composition.loadActiveStockRoute();

    expect(route.privacyMode, AiPrivacyMode.strictLocal);
    expect(route.profile.id, 'profile-a');
    expect(route.gateway, same(composition.gateway));
  });
}

StrictLocalProviderConfiguration _configuration({
  required String homeId,
  required String profileId,
  String displayName = 'Kitchen Ollama',
  int revision = 1,
}) => StrictLocalProviderConfiguration(
  profileId: profileId,
  homeId: homeId,
  displayName: displayName,
  kind: AiProviderKind.ollama,
  endpoint: Uri.parse('http://127.0.0.1:11434'),
  model: 'llava:latest',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.multiImage,
  },
  credentialConfigured: false,
  attestedAt: DateTime.utc(2026, 8, 11),
  revision: revision,
);

final class _NoMediaReader implements PreparedMediaByteReader {
  const _NoMediaReader();

  @override
  Future<Uint8List> read(PreparedAiMedia media) =>
      throw UnsupportedError('not used');
}
