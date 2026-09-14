import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/drift_household_repository.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/generated_server_ai_repository.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

const home = '11111111-1111-4111-8111-111111111111';
const product = '22222222-2222-4222-8222-222222222222';
const family = '33333333-3333-4333-8333-333333333333';
const pack = '44444444-4444-4444-8444-444444444444';
const privateProduct = '55555555-5555-4555-8555-555555555555';

void main() {
  for (final mode in ['manual_only', 'server_proxy']) {
    for (final available in [false, true]) {
      test('Step 2 $mode setup reopens with adapters=$available', () async {
        var requests = 0;
        final body = snapshot(mode: mode, available: available);
        final repository = GeneratedServerAiRepository(
          ProvidentiaApiClient(
            baseUri: Uri.parse('https://api.example.test'),
            httpClient: MockClient((request) async {
              requests++;
              expect(request.url.path, '/api/v1/homes/$home/ai/settings');
              return jsonResponse(body);
            }),
          ),
        );
        for (var reopen = 0; reopen < 2; reopen++) {
          final workspace = await repository.loadWorkspace(homeId: home);
          expect(workspace.settings.transmissionPlan, isNull);
          expect(workspace.profiles, isEmpty);
          expect(workspace.policy.extractionProfileIds, isEmpty);
          expect(workspace.policy.revision, 7);
          expect(workspace.settings.credentialEncryptionAvailable, isFalse);
        }
        expect(requests, 2);
      });
    }
  }

  test(
    'Step 2 each viewer receives only their own effective recipient',
    () async {
      for (final viewer in ['alice', 'bob']) {
        final shared = profile('shared', 'home');
        final personal = profile('private-$viewer', 'private');
        final body = snapshot(available: true)
          ..['providerProfiles'] = [shared, personal]
          ..['orchestrationPolicy'] = policy(['shared'])
          ..['transmissionPlan'] = {
            'settingsRevision': 4,
            'policyRevision': 7,
            'extractionProfiles': [
              {
                'profileId': personal['id'],
                'revision': 2,
                'provider': 'ollama',
                'model': 'synthetic-vision',
                'endpoint': 'https://ai.example.test/ollama',
              },
            ],
            'validationProfile': null,
            'sha256': 'a' * 64,
          };
        final repository = GeneratedServerAiRepository(
          ProvidentiaApiClient(
            baseUri: Uri.parse('https://api.example.test'),
            httpClient: MockClient((request) async {
              expect(request.url.path, '/api/v1/homes/$home/ai/settings');
              return jsonResponse(body);
            }),
          ),
        );
        final workspace = await repository.loadWorkspace(homeId: home);
        expect(workspace.policy.extractionProfileIds, ['shared']);
        expect(workspace.profiles.map((p) => p.id), [
          'shared',
          'private-$viewer',
        ]);
        expect(
          workspace.settings.transmissionPlan!.primary.profileId,
          'private-$viewer',
        );
        expect(
          workspace.settings.transmissionPlan!.primary.endpoint,
          'https://ai.example.test/ollama',
        );
      }
    },
  );

  for (final corruption in ['private-policy', 'foreign-home', 'stale-plan']) {
    test('Step 2 rejects $corruption rather than hiding a mismatch', () async {
      final body = snapshot(available: true)
        ..['providerProfiles'] = [profile('private-alice', 'private')];
      if (corruption == 'private-policy') {
        body['orchestrationPolicy'] = policy(['private-alice']);
      } else if (corruption == 'foreign-home') {
        body['providerProfiles'] = [
          {...profile('shared', 'home'), 'homeId': product},
        ];
      } else {
        body['transmissionPlan'] = {
          'settingsRevision': 3,
          'policyRevision': 7,
          'extractionProfiles': [
            {
              'profileId': 'private-alice',
              'revision': 1,
              'provider': 'ollama',
              'model': 'synthetic-vision',
              'endpoint': 'https://ai.example.test/ollama',
            },
          ],
          'validationProfile': null,
          'sha256': 'b' * 64,
        };
      }
      final repository = GeneratedServerAiRepository(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((_) async => jsonResponse(body)),
        ),
      );
      await expectLater(
        repository.loadWorkspace(homeId: home),
        throwsA(
          isA<AiServerException>().having(
            (error) => error.kind,
            'kind',
            AiServerFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test(
    'Step 2 family identity and quantities survive cache refresh and restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'providentia-step2-',
      );
      final file = File('${directory.path}/household.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      try {
        var repository = DriftHouseholdRepository(database);
        await seed(database, 'inventory-home-product', family, {
          'productId': product,
          'packId': null,
          'privateName': null,
          'productName': 'Synthetic family',
          'originalPackText': 'Unresolved source pack',
          'status': 'active',
        });
        await seed(database, 'inventory-balance', family, {
          'homeProductId': family,
          'quantity': '7.5',
        });
        await seed(database, 'inventory-home-product', privateProduct, {
          'productId': null,
          'packId': null,
          'privateName': 'Private original description',
          'originalPackText': 'Original jar',
          'status': 'active',
        });
        final master = [
          InventoryItem(
            id: family,
            homeId: home,
            canonicalName: 'Synthetic family',
            packSize: 'Unresolved source pack',
            category: 'Uncategorized',
            isHomeProduct: true,
            productId: product,
            currentQuantity: 7.5,
          ),
          InventoryItem(
            id: pack,
            homeId: home,
            canonicalName: 'Synthetic family',
            packSize: 'Explicit 1 kg pack',
            category: 'Uncategorized',
            productId: product,
            packId: pack,
          ),
        ];
        await repository.replaceCatalogItemMaster(homeId: home, items: master);
        for (var reopened = 0; reopened < 2; reopened++) {
          final items = await repository.watchItems(homeId: home).first;
          expect(items, hasLength(3));
          final unresolved = items.singleWhere((item) => item.id == family);
          expect(unresolved.productId, product);
          expect(unresolved.packId, isNull);
          expect(unresolved.packSize, 'Unresolved source pack');
          expect(unresolved.currentQuantity, 7.5);
          expect(
            items
                .singleWhere((item) => item.id == privateProduct)
                .canonicalName,
            'Private original description',
          );
          expect(items.singleWhere((item) => item.id == pack).packId, pack);
          final cached =
              await (database.select(database.localRecords)..where(
                    (row) =>
                        row.entityType.equals('inventory-item-master-product'),
                  ))
                  .get();
          expect(cached, hasLength(1));
          expect(cached.single.entityId, pack);
          if (reopened == 0) {
            await database.close();
            database = AppDatabase(NativeDatabase(file));
            repository = DriftHouseholdRepository(database);
            await repository.replaceCatalogItemMaster(
              homeId: home,
              items: master,
            );
          }
        }
        expect(await database.select(database.clientOperations).get(), isEmpty);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

Future<void> seed(
  AppDatabase db,
  String type,
  String id,
  Map<String, Object?> value,
) async {
  await db
      .into(db.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: home,
          entityType: type,
          entityId: id,
          payload: jsonEncode({...value, 'id': id, 'revision': 1}),
          revision: const Value(1),
          updatedAt: DateTime.utc(2026, 9, 14),
          synchronizedAt: Value(DateTime.utc(2026, 9, 14)),
        ),
      );
}

http.Response jsonResponse(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json'},
);

Map<String, Object?> snapshot({
  String mode = 'server_proxy',
  bool available = false,
}) => {
  'mode': mode,
  'provider': null,
  'model': null,
  'revision': 4,
  'availableServerProviders': [
    if (available) {'id': 'ollama', 'requiresCredential': false},
  ],
  'cloudByokOnNativeClients': false,
  'humanReviewRequired': true,
  'serverPersistsUploadedMedia': false,
  'credentialEncryptionAvailable': false,
  'mediaHandling': {
    'directExtractionUpload': 'transient_not_persisted',
    'privateMediaStorage': 'explicit_encrypted_opt_in',
    'privateMediaRetentionOptions': ['transient', 'retained'],
    'plaintextMediaAtRest': false,
    'cloudProviderTransmissionRequiresConsent': true,
  },
  'providerProfiles': <Object?>[],
  'orchestrationPolicy': policy([]),
  'transmissionPlan': null,
};
Map<String, Object?> profile(String id, String scope) => {
  'id': id,
  'label': id,
  'provider': 'ollama',
  'model': 'synthetic-vision',
  'ownerScope': scope,
  'endpoint': 'https://ai.example.test/ollama',
  'credentialConfigured': false,
  'lastFour': null,
  'estimatedCostMicros': 0,
  'revision': 2,
};
Map<String, Object?> policy(List<String> ids) => {
  'extractionProfileIds': ids,
  'validationProfileId': null,
  'maxAttempts': 4,
  'maxTotalTokens': 50000,
  'maxEstimatedCostMicros': 1000000,
  'revision': 7,
};
