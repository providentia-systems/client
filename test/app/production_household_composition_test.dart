import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/core/database/client_local_record_types.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/sanitizing_image_media_preparer.dart';
import 'package:providentia/features/homes/infrastructure/home_data_revocation.dart';
import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia/features/shopping/application/shopping_interaction_capabilities.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

enum _MembershipProbe {
  omitted,
  member,
  unavailable,
  authentication,
  malformed,
}

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

  for (final status in <int>[403, 404]) {
    for (final receiptOnly in <bool>[true, false]) {
      testWidgets(
        'production ${receiptOnly ? 'receipt' : 'photo'} AI generic $status preserves home data and pending work',
        (tester) => _verifyProductionAiDenialBoundary(
          tester,
          status: status,
          verifiedHomeDenial: false,
          receiptOnly: receiptOnly,
        ),
      );
    }
    for (final probe in _MembershipProbe.values) {
      testWidgets(
        'production typed AI denial $status verifies membership ${probe.name} before any purge',
        (tester) => _verifyProductionAiDenialBoundary(
          tester,
          status: status,
          verifiedHomeDenial: true,
          receiptOnly: true,
          membershipProbe: probe,
        ),
      );
    }
  }

  test('production AI routes share the single revocation boundary', () {
    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'onAuthorizationDenied:\s*_handleAiAuthorizationLost',
      ).hasMatch(source),
      isTrue,
    );
    expect(
      RegExp(
        r'onAuthorizationLost:\s*_handleAiAuthorizationLost',
      ).hasMatch(source),
      isTrue,
    );
    expect(source, contains('unawaited(_handleHomeAuthorizationLost());'));
    expect(source, contains('verifyProductionAiHomeRevocation('));
    expect(source, contains('ReceiptPageMediaEditor(sources: _sources)'));
    expect(source, contains('ReceiptPdfRasterizer(sources: _sources)'));
    expect(source, contains('pickMultipleImages: _pickMultipleImages'));
    expect(source, contains('pickReceiptPdf: _pickReceiptPdf'));
    expect(source, contains('receiptImportPageBuilder:'));
    expect(source, contains('receiptImportOnly: true'));
    expect(source, contains('_features.purchasing.selectReceipt(receiptId)'));
    expect(
      RegExp(
        r'_receiptPdfRasterizer\s*\.choose\(\s*homeId:\s*widget\.homeId',
      ).hasMatch(source),
      isTrue,
    );
    expect(source, contains('limit: 8'));
  });

  test(
    'AI membership verification rejects a stale binding before and after transport',
    () async {
      var current = false;
      var requests = 0;
      final api = ProvidentiaApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        httpClient: MockClient((_) async {
          requests++;
          current = false;
          return http.Response(
            jsonEncode({'data': <Object?>[]}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);
      expect(
        await verifyProductionAiHomeRevocation(
          api: api,
          homeId: _homeId,
          bindingIsCurrent: () => current,
        ),
        isFalse,
      );
      expect(requests, 0);
      current = true;
      expect(
        await verifyProductionAiHomeRevocation(
          api: api,
          homeId: _homeId,
          bindingIsCurrent: () => current,
        ),
        isFalse,
      );
      expect(requests, 1);
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

  test('production online suggestions are composed without unsafe writes', () {
    const capabilities =
        ShoppingInteractionCapabilities.durableEvidenceSuggestions;
    expect(capabilities.onlineSuggestionsComposed, isTrue);
    expect(capabilities.canEditExistingQuantities, isTrue);
    expect(capabilities.canRecordSuggestionFeedback, isTrue);
    expect(
      File('lib/app/production_bootstrap_app.dart').readAsStringSync(),
      contains('feedbackQueue: household'),
    );

    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();
    expect(source, contains('GeneratedOnlineShoppingSuggestionRepository'));
    expect(source, contains('DriftShoppingSuggestionCache'));
    expect(
      source,
      contains('ShoppingInteractionCapabilities.durableEvidenceSuggestions'),
    );
  });

  test('production purchasing composes the ordinary product creator', () {
    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();
    expect(source, contains('productCreationRepository: household'));
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

Future<void> _verifyProductionAiDenialBoundary(
  WidgetTester tester, {
  required int status,
  required bool verifiedHomeDenial,
  required bool receiptOnly,
  _MembershipProbe membershipProbe = _MembershipProbe.omitted,
}) async {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final now = DateTime.utc(2026, 8, 11, 16);
  var generated = 0;
  final repository = createProductionHouseholdRepository(
    database: database,
    deviceId: _deviceId,
    originatingAccountId: _accountId,
    clock: () => now,
    idGenerator: () => generated++ == 0 ? _productId : _operationId,
    onMutationCommitted: () async {},
  );
  await repository.createPrivateHomeProduct(
    PrivateHomeProductDraft(
      homeId: _homeId,
      privateName: 'Synthetic rice',
      originalPackText: '1 kg',
      unit: 'kg',
    ),
  );
  await database
      .into(database.localRecords)
      .insert(
        LocalRecordsCompanion.insert(
          homeId: _homeId,
          entityType: ClientLocalRecordTypes.strictLocalAiConfiguration,
          entityId: 'synthetic-ai-configuration',
          payload: jsonEncode(<String, Object?>{'synthetic': true}),
          updatedAt: now,
        ),
      );
  final recordsBefore = await database.select(database.localRecords).get();
  final operationsBefore = await database
      .select(database.clientOperations)
      .get();
  expect(operationsBefore, hasLength(1));
  expect(operationsBefore.single.operationId, _operationId);
  expect(operationsBefore.single.deviceId, _deviceId);
  expect(operationsBefore.single.originatingAccountId, _accountId);
  expect(operationsBefore.single.homeId, _homeId);

  var transportRequests = 0;
  var membershipRequests = 0;
  final api = ProvidentiaApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/v1/homes') {
        membershipRequests++;
        final probeStatus = switch (membershipProbe) {
          _MembershipProbe.unavailable => 503,
          _MembershipProbe.authentication => 401,
          _ => 200,
        };
        return http.Response(
          jsonEncode(switch (membershipProbe) {
            _MembershipProbe.omitted => {'data': <Object?>[]},
            _MembershipProbe.member => {
              'data': [
                <String, Object?>{
                  'id': _homeId,
                  'name': 'Synthetic home',
                  'defaultLocale': 'en',
                  'defaultCurrency': 'NAD',
                  'defaultTimezone': 'UTC',
                  'role': 'owner',
                  'revision': 1,
                },
              ],
            },
            _MembershipProbe.malformed => <String, Object?>{},
            _ => <String, Object?>{
              'type': 'about:blank',
              'title': 'Unavailable',
              'status': probeStatus,
              'requestId': _requestId,
            },
          }),
          probeStatus,
          headers: const {'content-type': 'application/json'},
        );
      }
      transportRequests++;
      return http.Response(
        jsonEncode(<String, Object?>{
          'type': verifiedHomeDenial
              ? 'https://providentia.invalid/problems/sync_home_access_denied'
              : 'about:blank',
          'title': status == 403 ? 'Forbidden' : 'Not Found',
          'status': status,
          'detail': verifiedHomeDenial
              ? 'Household membership was denied.'
              : 'The requested AI resource is unavailable.',
          'requestId': _requestId,
        }),
        status,
        headers: const <String, String>{
          'content-type': 'application/problem+json',
        },
      );
    }),
  );
  addTearDown(api.close);
  final revocationGate = HomeSyncRevocationGate();
  var purgeCalls = 0;
  var routeCalls = 0;
  var resumeRefreshes = 0;
  final resumeGate = ProductionResumeSyncGate(
    refresh: () async => resumeRefreshes++,
  )..markReady();
  addTearDown(resumeGate.dispose);
  final boundary = ProductionHomeRevocationBoundary(
    purge: (homeId) async {
      expect(homeId, _homeId);
      purgeCalls++;
      await revocationGate.revokeAndWait(homeId);
      await RevokedHomeDataPurger(database).purge(homeId);
      return true;
    },
  );
  final revoked = Completer<void>();
  final verificationComplete = Completer<void>();
  var authorizationCallbacks = 0;
  await tester.pumpWidget(
    MaterialApp(
      home: ProductionServerAiRoute(
        api: api,
        homeId: _homeId,
        receiptImportOnly: receiptOnly,
        capabilities: AiHomeCapabilities.fromPermissions(
          homeId: _homeId,
          permissions: const <String>{
            'ai.read',
            'ai.use',
            'ai.credentials.use',
          },
        ),
        protectedRouteRegistry: ProductionProtectedRouteRegistry(),
        onAuthorizationLost: () async {
          authorizationCallbacks++;
          final membershipRevoked = await verifyProductionAiHomeRevocation(
            api: api,
            homeId: _homeId,
            bindingIsCurrent: () => true,
          );
          if (membershipRevoked) {
            await boundary.revokePurgeAndRoute(
              homeId: _homeId,
              resumeSyncGate: resumeGate,
              routeAway: () async => routeCalls++,
            );
            if (!revoked.isCompleted) revoked.complete();
          }
          if (!verificationComplete.isCompleted) {
            verificationComplete.complete();
          }
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (verifiedHomeDenial) {
    await tester.runAsync(
      () => verificationComplete.future.timeout(const Duration(seconds: 5)),
    );
    await tester.pumpAndSettle();
  }
  final shouldPurge =
      verifiedHomeDenial && membershipProbe == _MembershipProbe.omitted;
  if (shouldPurge) {
    expect(transportRequests, 1);
    expect(authorizationCallbacks, 1);
    expect(purgeCalls, 1);
    expect(routeCalls, 1);
    expect(await database.select(database.localRecords).get(), isEmpty);
    expect(await database.select(database.clientOperations).get(), isEmpty);
    expect(find.textContaining('Access to this household'), findsOneWidget);
  } else {
    expect(transportRequests, 1);
    expect(authorizationCallbacks, verifiedHomeDenial ? 1 : 0);
    expect(purgeCalls, 0);
    expect(routeCalls, 0);
    expect(revoked.isCompleted, isFalse);
    if (verifiedHomeDenial) {
      expect(find.textContaining('Access to this household'), findsOneWidget);
      expect(find.text('AI access unavailable'), findsOneWidget);
    } else {
      expect(find.textContaining('Access to this household'), findsNothing);
      expect(
        find.text(
          status == 403
              ? 'Your current household role does not allow this AI action.'
              : 'Household AI is temporarily unavailable.',
        ),
        findsOneWidget,
      );
      // Generic failures remain retryable without changing the home or queue.
      await tester.tap(find.byTooltip('Refresh AI settings'));
      await tester.pumpAndSettle();
      expect(transportRequests, 2);
      expect(authorizationCallbacks, 0);
    }
    expect(await database.select(database.localRecords).get(), recordsBefore);
    expect(
      await database.select(database.clientOperations).get(),
      operationsBefore,
    );
    final items = await tester.runAsync(
      () => repository
          .watchItems(homeId: _homeId)
          .first
          .timeout(const Duration(seconds: 5)),
    );
    final product = items!.single;
    expect(product.id, _productId);
    expect(product.canonicalName, 'Synthetic rice');
    expect(product.unit, 'kg');
  }

  resumeGate.resume();
  await resumeGate.settle();
  expect(membershipRequests, verifiedHomeDenial ? 1 : 0);
  expect(resumeRefreshes, shouldPurge ? 0 : 1);
  expect(tester.takeException(), isNull);
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
const _accountId = '0198a0b1-c2d3-7e4f-8345-6789abcdef12';
const _productId = '0198a0b1-c2d3-7e4f-8456-789abcdef123';
const _requestId = '0198a0b1-c2d3-7e4f-8678-9abcdef01234';
const _deviceId = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const _listId = '0198a0b1-c2d3-7e4f-8567-89abcdef0123';
const _operationId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
