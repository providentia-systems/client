import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/application/server_ai_repository.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/server_ai_models.dart';
import 'package:providentia/features/ai_integration/infrastructure/receipt_page_media_editor.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_controller.dart';
import 'package:providentia/features/ai_integration/presentation/server_ai_workspace_page.dart';

import 'test_fixtures.dart';

void main() {
  test('exact permissions do not infer read access from manage', () async {
    final repository = _ServerRepository(_workspace());
    final controller = _controller(
      repository: repository,
      capabilities: AiHomeCapabilities.fromPermissions(
        homeId: 'home-1',
        permissions: const <String>{'ai.manage'},
      ),
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.updateSettings(
      const AiSettingsUpdate(
        mode: AiServerMode.manualOnly,
        provider: null,
        model: null,
        expectedRevision: 0,
      ),
    );

    expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
    expect(repository.loadCalls, 0);
  });

  test(
    'one sanitized image requires explicit consent and reaches review only',
    () async {
      final repository = _ServerRepository(_workspace());
      final media = FakeMediaPreparation(preparedBatch());
      final gateway = FakeGateway(
        route: AiGatewayRoute.serverProxyCloud,
        receiptHandler: (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(runId: request.runId),
          metadata: runMetadata,
        ),
      );
      final controller = _controller(
        repository: repository,
        media: media,
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );
      expect(controller.status, ServerAiWorkspaceStatus.awaitingConsent);
      expect(controller.transmissionConfirmed, isFalse);
      expect(gateway.requests, isEmpty);

      await controller.extract();
      expect(gateway.requests, isEmpty);
      expect(controller.status, ServerAiWorkspaceStatus.failed);

      await controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );
      controller.confirmTransmission();
      expect(controller.transmissionConfirmed, isTrue);
      await controller.extract();

      expect(gateway.requests, hasLength(1));
      expect(gateway.requests.single.homeId, 'home-1');
      expect(gateway.requests.single.media.media, hasLength(1));
      expect(gateway.requests.single.storeProviderResponse, isFalse);
      expect(controller.status, ServerAiWorkspaceStatus.reviewRequired);
      expect(controller.receiptProposal, isNotNull);
      expect(
        controller.review?.candidates.single.status,
        AiCandidateReviewStatus.pending,
      );
      expect(media.discardCalls, 1);
      expect(controller.prepared, isNotNull);
      expect(repository.reviewCalls, 0);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    },
  );

  test(
    'ordered receipt pages bind every digest and do not mutate a domain',
    () async {
      final provider = _multiImageProvider();
      final repository = _ServerRepository(
        _workspace(profiles: <AiProviderProfile>[provider]),
      );
      final media = _OrderedMediaPreparation();
      final gateway = FakeGateway(
        route: AiGatewayRoute.serverProxyCloud,
        receiptHandler: (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(runId: request.runId),
          metadata: runMetadata,
        ),
      );
      final controller = _controller(
        repository: repository,
        media: media,
        gateway: gateway,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final pages = <AiMediaAsset>[
        _receiptPage('page-b', 0),
        _receiptPage('page-a', 1),
        _receiptPage('page-c', 2),
      ];

      await controller.prepareReceiptPages(provider: provider, assets: pages);

      expect(controller.status, ServerAiWorkspaceStatus.awaitingConsent);
      expect(media.preparedSourceIds.single, <String>[
        'page-b',
        'page-a',
        'page-c',
      ]);
      expect(controller.prepared?.media.map((item) => item.pageIndex), <int>[
        0,
        1,
        2,
      ]);
      expect(gateway.requests, isEmpty);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);

      controller.confirmTransmission();
      expect(
        controller.consent?.orderedMediaHashes,
        controller.prepared?.orderedHashes,
      );
      await controller.extract();

      expect(gateway.requests, hasLength(1));
      expect(
        gateway.requests.single.media.media.map((item) => item.sourceMediaId),
        <String>['page-b', 'page-a', 'page-c'],
      );
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    },
  );

  test(
    'receipt intake rejects an unbounded selection before preparation',
    () async {
      final provider = _multiImageProvider();
      final repository = _ServerRepository(
        _workspace(profiles: <AiProviderProfile>[provider]),
      );
      final media = _OrderedMediaPreparation();
      final controller = _controller(repository: repository, media: media);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.prepareReceiptPages(
        provider: provider,
        assets: <AiMediaAsset>[
          for (var index = 0; index < 9; index++)
            _receiptPage('page-$index', index),
        ],
      );

      expect(controller.status, ServerAiWorkspaceStatus.failed);
      expect(controller.safeMessage, contains('1 and 8'));
      expect(media.preparedSourceIds, isEmpty);
    },
  );

  test(
    'candidate acceptance builds a non-mutating ordinary-command handoff',
    () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );
      controller.confirmTransmission();
      await controller.extract();

      expect(controller.buildReviewHandoff(), isNull);
      await controller.reviewCandidate(
        position: 0,
        decision: AiCandidateDecision.accept,
      );
      final handoff = controller.buildReviewHandoff();

      expect(repository.reviewCalls, 1);
      expect(handoff?.homeId, 'home-1');
      expect(handoff?.acceptedPositions, <int>[0]);
      expect(handoff?.requiresOrdinaryDomainCommand, isTrue);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    },
  );

  test('role loss discards prepared bytes and blocks review', () async {
    final repository = _ServerRepository(_workspace());
    final media = FakeMediaPreparation(preparedBatch());
    final controller = _controller(repository: repository, media: media);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.prepareOne(
      provider: controller.workspace!.profiles.single,
      asset: _asset(),
    );

    await controller.updateCapabilities(
      AiHomeCapabilities.fromPermissions(
        homeId: 'home-1',
        permissions: const <String>{'ai.read'},
      ),
    );
    await controller.reviewCandidate(
      position: 0,
      decision: AiCandidateDecision.accept,
    );

    expect(media.discardCalls, 1);
    expect(controller.prepared, isNull);
    expect(controller.transmissionConfirmed, isFalse);
    expect(repository.reviewCalls, 0);
    expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
  });

  test(
    'route-style revocation prevents late preparation after dispose',
    () async {
      final repository = _ServerRepository(_workspace());
      final media = _DelayedMediaPreparation(preparedBatch());
      final controller = _controller(repository: repository, media: media);
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      final preparation = controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );
      await media.started.future;
      await controller.updateCapabilities(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-1',
          permissions: const <String>{},
          active: false,
        ),
      );
      final notificationsAtDispose = notifications;
      controller.dispose();
      media.complete();
      await preparation;

      expect(media.discardCalls, 1);
      expect(notifications, notificationsAtDispose);
    },
  );

  test('cross-home workspace response becomes a safe failure', () async {
    final repository = _ServerRepository(_workspace(homeId: 'home-2'));
    final controller = _controller(repository: repository);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.workspace, isNull);
    expect(controller.status, ServerAiWorkspaceStatus.failed);
    expect(controller.safeMessage, isNot(contains('home-2')));
  });

  testWidgets('page makes consent and each candidate decision explicit', (
    tester,
  ) async {
    final repository = _ServerRepository(_workspace());
    final controller = _controller(repository: repository);
    addTearDown(controller.dispose);
    await controller.load();
    AiReviewHandoff? handoff;
    PreparedAiMedia? previewedMedia;
    await tester.pumpWidget(
      MaterialApp(
        home: ServerAiWorkspacePage(
          controller: controller,
          pickSingleImage: (kind) async => _asset(),
          readPreparedImage: (media) async {
            previewedMedia = media;
            return _transparentPixel;
          },
          onReviewHandoff: (value) => handoff = value,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-pick-receipt')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('ai-pick-receipt')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-transmission-consent')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('ai-transmission-consent')), findsOneWidget);
    expect(find.byKey(const Key('ai-sanitized-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-transmission-media-disclosure')),
      findsOneWidget,
    );
    expect(find.textContaining('leaves this device'), findsWidgets);
    expect(previewedMedia?.ephemeralReference, 'ephemeral://batch-1/page-1');
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('ai-send-extraction')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('ai-transmission-consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai-send-extraction')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('ai-accept-0'));
    expect(find.text('Mandatory candidate review'), findsOneWidget);
    expect(find.byKey(const Key('ai-sanitized-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('ai-review-preview-retention')),
      findsOneWidget,
    );
    expect(find.textContaining('ordinary authorized'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-accept-0')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('ai-build-review-handoff'));
    await tester.tap(find.byKey(const Key('ai-build-review-handoff')));
    await tester.pump();

    expect(handoff?.acceptedPositions, <int>[0]);
    expect(repository.inventoryOrPurchaseMutationCalls, 0);
  });

  testWidgets('stock extraction exposes camera, gallery, and file sources', (
    tester,
  ) async {
    final controller = _controller(repository: _ServerRepository(_workspace()));
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(
        home: ServerAiWorkspacePage(
          controller: controller,
          pickSingleImage: (_) async => null,
          captureSingleImage: (_) async => null,
          pickFileImage: (_) async => null,
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-capture-stock')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('ai-capture-stock')), findsOneWidget);
    expect(find.byKey(const Key('ai-pick-stock')), findsOneWidget);
    expect(find.byKey(const Key('ai-upload-stock')), findsOneWidget);
  });

  testWidgets(
    'receipt PDF pages show ordered local transforms then every sanitized preview',
    (tester) async {
      final provider = _multiImageProvider();
      final repository = _ServerRepository(
        _workspace(profiles: <AiProviderProfile>[provider]),
      );
      final media = _OrderedMediaPreparation();
      final controller = _controller(repository: repository, media: media);
      addTearDown(controller.dispose);
      await controller.load();
      final transforms = <ReceiptPageTransform>[];
      final crops = <NormalizedRegion?>[];
      final discarded = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ServerAiWorkspacePage(
            controller: controller,
            pickSingleImage: (_) async => null,
            pickMultipleImages: (_) async => <AiMediaAsset>[
              _receiptPage('first', 0),
              _receiptPage('second', 1),
            ],
            pickReceiptPdf: () async => <AiMediaAsset>[
              _receiptPage('first', 0),
              _receiptPage('second', 1),
            ],
            readLocalImage: (_) async => _transparentPixel,
            transformReceiptPage:
                ({required asset, required transform, crop}) async {
                  transforms.add(transform);
                  crops.add(crop);
                  return AiMediaAsset(
                    id: '${asset.id}-${transform.name}',
                    homeId: asset.homeId,
                    localReference: asset.localReference,
                    purpose: asset.purpose,
                    mimeType: 'image/jpeg',
                    byteLength: asset.byteLength,
                    createdAt: asset.createdAt,
                    pageIndex: asset.pageIndex,
                  );
                },
            discardLocalImages: (assets) async =>
                discarded.addAll(assets.map((asset) => asset.id)),
            readPreparedImage: (_) async => _transparentPixel,
          ),
        ),
      );

      await _scrollTo(tester, const Key('ai-pick-receipt-pdf'));
      await tester.tap(find.byKey(const Key('ai-pick-receipt-pdf')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('ai-receipt-page-draft'));
      expect(find.byKey(const Key('ai-receipt-local-preview-0')), findsOne);
      expect(find.byKey(const Key('ai-receipt-local-preview-1')), findsOne);

      await tester.tap(find.byKey(const Key('ai-receipt-rotate-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ai-receipt-crop-1')));
      await tester.pumpAndSettle();

      expect(transforms, <ReceiptPageTransform>[
        ReceiptPageTransform.rotateClockwise90,
        ReceiptPageTransform.crop,
      ]);
      expect(crops.first, isNull);
      expect(crops.last?.pageIndex, 1);
      expect(crops.last?.width, 0.9);

      await _scrollTo(tester, const Key('ai-prepare-receipt-pages'));
      await tester.tap(find.byKey(const Key('ai-prepare-receipt-pages')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('ai-transmission-consent'));

      expect(find.byKey(const Key('ai-receipt-page-draft')), findsNothing);
      expect(find.byKey(const Key('ai-sanitized-preview')), findsOne);
      expect(find.byKey(const Key('ai-sanitized-preview-1')), findsOne);
      expect(find.byKey(const Key('ai-prepared-digest-0')), findsOne);
      expect(find.byKey(const Key('ai-prepared-digest-1')), findsOne);
      expect(discarded, <String>['first-rotateClockwise90', 'second-crop']);
      expect(controller.consent, isNull);

      await tester.tap(find.byKey(const Key('ai-transmission-consent')));
      await tester.pump();
      await _scrollTo(tester, const Key('ai-send-extraction'));
      await tester.tap(find.byKey(const Key('ai-send-extraction')));
      await tester.pumpAndSettle();

      expect(controller.status, ServerAiWorkspaceStatus.reviewRequired);
      expect(find.byKey(const Key('ai-sanitized-preview')), findsOne);
      expect(find.byKey(const Key('ai-sanitized-preview-1')), findsOne);
      expect(find.byKey(const Key('ai-review-preview-retention')), findsOne);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    },
  );

  testWidgets(
    'receipt PDF staging rejects raw documents and discards them locally',
    (tester) async {
      final provider = _multiImageProvider();
      final repository = _ServerRepository(
        _workspace(profiles: <AiProviderProfile>[provider]),
      );
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      final discarded = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: ServerAiWorkspacePage(
            controller: controller,
            pickSingleImage: (_) async => null,
            pickReceiptPdf: () async => <AiMediaAsset>[
              AiMediaAsset(
                id: 'raw-pdf',
                homeId: 'home-1',
                localReference: 'registered://raw-pdf',
                purpose: AiExtractionKind.receipt,
                mimeType: 'application/pdf',
                byteLength: 100,
                createdAt: DateTime.utc(2026, 8, 11),
              ),
            ],
            discardLocalImages: (assets) async =>
                discarded.addAll(assets.map((asset) => asset.id)),
          ),
        ),
      );

      await _scrollTo(tester, const Key('ai-pick-receipt-pdf'));
      await tester.tap(find.byKey(const Key('ai-pick-receipt-pdf')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ai-receipt-page-draft')), findsNothing);
      expect(discarded, <String>['raw-pdf']);
      expect(controller.prepared, isNull);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    },
  );

  testWidgets('receipt PDF draft is discarded after preparation failure', (
    tester,
  ) async {
    final provider = _multiImageProvider();
    final repository = _ServerRepository(
      _workspace(profiles: <AiProviderProfile>[provider]),
    );
    final controller = _controller(
      repository: repository,
      media: _ThrowingMedia(prepareError: StateError('private source path')),
    );
    addTearDown(controller.dispose);
    await controller.load();
    final discarded = <String>[];
    var selection = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ServerAiWorkspacePage(
          controller: controller,
          pickSingleImage: (_) async => null,
          pickReceiptPdf: () async => <AiMediaAsset>[
            _receiptPage('pdf-page-${selection++}', 0),
          ],
          readLocalImage: (_) async => _transparentPixel,
          discardLocalImages: (assets) async =>
              discarded.addAll(assets.map((asset) => asset.id)),
        ),
      ),
    );

    await _scrollTo(tester, const Key('ai-pick-receipt-pdf'));
    await tester.tap(find.byKey(const Key('ai-pick-receipt-pdf')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('ai-prepare-receipt-pages'));
    await tester.tap(find.byKey(const Key('ai-prepare-receipt-pages')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-receipt-page-draft')), findsNothing);
    expect(discarded, contains('pdf-page-0'));
    expect(controller.prepared, isNull);
    expect(controller.safeMessage, isNot(contains('private')));
    expect(repository.inventoryOrPurchaseMutationCalls, 0);
  });

  testWidgets('receipt PDF draft is discarded when home access is revoked', (
    tester,
  ) async {
    final provider = _multiImageProvider();
    final repository = _ServerRepository(
      _workspace(profiles: <AiProviderProfile>[provider]),
    );
    final controller = _controller(repository: repository);
    addTearDown(controller.dispose);
    await controller.load();
    final discarded = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ServerAiWorkspacePage(
          controller: controller,
          pickSingleImage: (_) async => null,
          pickReceiptPdf: () async => <AiMediaAsset>[
            _receiptPage('pdf-revoked-page', 0),
          ],
          readLocalImage: (_) async => _transparentPixel,
          discardLocalImages: (assets) async =>
              discarded.addAll(assets.map((asset) => asset.id)),
        ),
      ),
    );

    await _scrollTo(tester, const Key('ai-pick-receipt-pdf'));
    await tester.tap(find.byKey(const Key('ai-pick-receipt-pdf')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const Key('ai-receipt-page-draft'));
    expect(find.byKey(const Key('ai-receipt-page-draft')), findsOneWidget);

    await controller.updateCapabilities(
      AiHomeCapabilities.fromPermissions(
        homeId: 'home-1',
        permissions: const <String>{},
        active: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ai-receipt-page-draft')), findsNothing);
    expect(discarded, contains('pdf-revoked-page'));
    expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
    expect(repository.inventoryOrPurchaseMutationCalls, 0);
  });

  group('management boundaries', () {
    test(
      'valid revisioned settings, profiles, and policy reload safely',
      () async {
        final repository = _ServerRepository(_workspace());
        final controller = _controller(repository: repository);
        addTearDown(controller.dispose);
        await controller.load();

        await controller.updateSettings(
          const AiSettingsUpdate(
            mode: AiServerMode.serverProxy,
            provider: 'openai',
            model: 'gpt-5-mini',
            expectedRevision: 1,
          ),
        );
        await controller.saveProviderProfile(
          draft: const AiProviderProfileDraft(
            id: null,
            label: 'Backup provider',
            provider: 'anthropic',
            model: 'claude-sonnet',
            estimatedCostMicros: 12,
            expectedRevision: 0,
          ),
          credential: 'write-only-secret',
        );
        await controller.saveProviderProfile(
          draft: const AiProviderProfileDraft(
            id: 'provider-1',
            label: 'Primary provider',
            provider: 'openai',
            model: 'gpt-5-mini',
            estimatedCostMicros: 0,
            expectedRevision: 1,
          ),
        );
        await controller.updatePolicy(
          AiOrchestrationPolicyUpdate(
            extractionProfileIds: const <String>['provider-1'],
            validationProfileId: 'provider-1',
            maxAttempts: 2,
            maxTotalTokens: 60000,
            maxEstimatedCostMicros: 900000,
            expectedRevision: 1,
          ),
        );

        expect(repository.settingsCalls, 1);
        expect(repository.saveProfileCalls, 2);
        expect(repository.lastCredential, isNull);
        expect(repository.policyCalls, 1);
        expect(repository.loadCalls, 5);
        expect(controller.status, ServerAiWorkspaceStatus.ready);
        expect(controller.safeMessage, isNull);
      },
    );

    test(
      'stale and cross-workspace management input never reaches server',
      () async {
        final repository = _ServerRepository(_workspace());
        final controller = _controller(repository: repository);
        addTearDown(controller.dispose);

        await controller.updateSettings(
          const AiSettingsUpdate(
            mode: AiServerMode.manualOnly,
            provider: null,
            model: null,
            expectedRevision: 1,
          ),
        );
        expect(controller.safeMessage, contains('Refresh AI settings'));
        await controller.load();

        await controller.saveProviderProfile(
          draft: const AiProviderProfileDraft(
            id: null,
            label: 'Stale',
            provider: 'openai',
            model: 'model',
            estimatedCostMicros: 0,
            expectedRevision: 4,
          ),
        );
        expect(controller.safeMessage, contains('Refresh provider profiles'));
        await controller.saveProviderProfile(
          draft: const AiProviderProfileDraft(
            id: 'another-home-profile',
            label: 'Foreign',
            provider: 'openai',
            model: 'model',
            estimatedCostMicros: 0,
            expectedRevision: 1,
          ),
        );
        expect(controller.safeMessage, contains('Refresh provider profiles'));
        await controller.updatePolicy(
          AiOrchestrationPolicyUpdate(
            extractionProfileIds: const <String>['provider-1'],
            validationProfileId: null,
            maxAttempts: 1,
            maxTotalTokens: 100,
            maxEstimatedCostMicros: 0,
            expectedRevision: 9,
          ),
        );
        expect(controller.safeMessage, contains('Refresh the AI policy'));
        await controller.updatePolicy(
          AiOrchestrationPolicyUpdate(
            extractionProfileIds: const <String>['foreign-profile'],
            validationProfileId: null,
            maxAttempts: 1,
            maxTotalTokens: 100,
            maxEstimatedCostMicros: 0,
            expectedRevision: 1,
          ),
        );
        expect(controller.safeMessage, contains('active household'));

        expect(repository.settingsCalls, 0);
        expect(repository.saveProfileCalls, 0);
        expect(repository.policyCalls, 0);
      },
    );

    test('server and unexpected management failures stay safe', () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();

      repository.settingsError = const AiServerException(
        AiServerFailureKind.conflict,
      );
      await controller.updateSettings(
        const AiSettingsUpdate(
          mode: AiServerMode.serverProxy,
          provider: 'openai',
          model: 'gpt-5-mini',
          expectedRevision: 1,
        ),
      );
      expect(controller.safeMessage, contains('another device'));

      repository.settingsError = StateError('private settings detail');
      await controller.updateSettings(
        const AiSettingsUpdate(
          mode: AiServerMode.serverProxy,
          provider: 'openai',
          model: 'gpt-5-mini',
          expectedRevision: 1,
        ),
      );
      expect(controller.safeMessage, 'AI settings could not be saved safely.');

      repository.saveProfileError = const AiServerException(
        AiServerFailureKind.forbidden,
      );
      await controller.saveProviderProfile(draft: _existingProfileDraft());
      expect(controller.safeMessage, contains('role'));
      repository.saveProfileError = StateError('private provider detail');
      await controller.saveProviderProfile(draft: _existingProfileDraft());
      expect(controller.safeMessage, 'The provider could not be saved safely.');

      repository.policyError = const AiServerException(
        AiServerFailureKind.unavailable,
      );
      await controller.updatePolicy(_policyUpdate());
      expect(controller.safeMessage, contains('temporarily unavailable'));
      repository.policyError = StateError('private policy detail');
      await controller.updatePolicy(_policyUpdate());
      expect(
        controller.safeMessage,
        'The AI policy could not be saved safely.',
      );
    });
  });

  group('media and extraction outcomes', () {
    test(
      'invalid provider/media scope and unsafe preparation are rejected',
      () async {
        final repository = _ServerRepository(_workspace());
        final unsafeMedia = FakeMediaPreparation(
          _preparedBatch(homeId: 'home-2'),
        );
        final controller = _controller(
          repository: repository,
          media: unsafeMedia,
        );
        addTearDown(controller.dispose);
        await controller.load();

        await controller.prepareOne(
          provider: serverProvider(revision: 2),
          asset: _asset(),
        );
        expect(controller.safeMessage, contains('active home'));
        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(homeId: 'home-2'),
        );
        expect(controller.safeMessage, contains('active home'));
        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(),
        );

        expect(controller.status, ServerAiWorkspaceStatus.failed);
        expect(controller.safeMessage, contains('prepared safely'));
        expect(unsafeMedia.discardCalls, 1);
        controller.confirmTransmission();
        expect(controller.safeMessage, contains('Prepare one image'));
      },
    );

    test(
      'preparation exceptions and best-effort cleanup never leak details',
      () async {
        final repository = _ServerRepository(_workspace());
        final media = _ThrowingMedia(
          prepareError: StateError('private path /secret/image.jpg'),
          discardError: StateError('private cleanup path'),
        );
        final controller = _controller(repository: repository, media: media);
        addTearDown(controller.dispose);
        await controller.load();

        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(),
        );
        expect(
          controller.safeMessage,
          'The selected image could not be prepared safely.',
        );
        expect(controller.safeMessage, isNot(contains('/secret')));

        final cleanupMedia = _ThrowingMedia(
          batch: preparedBatch(),
          discardError: StateError('private cleanup path'),
        );
        final cleanupController = _controller(
          repository: repository,
          media: cleanupMedia,
        );
        addTearDown(cleanupController.dispose);
        await cleanupController.load();
        await cleanupController.prepareOne(
          provider: cleanupController.workspace!.profiles.single,
          asset: _asset(),
        );
        await cleanupController.clearExtraction();
        expect(cleanupController.prepared, isNull);
        expect(cleanupController.status, ServerAiWorkspaceStatus.ready);
        expect(cleanupMedia.discardCalls, 1);
      },
    );

    test('consent can be revoked before any provider transmission', () async {
      final repository = _ServerRepository(_workspace());
      final gateway = _receiptGateway(
        const AiExtractionFailure<ReceiptProposal>(
          code: 'unused',
          safeMessage: 'unused',
        ),
      );
      final controller = _controller(repository: repository, gateway: gateway);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );

      controller.revokeTransmission();
      controller.confirmTransmission();
      expect(controller.consent?.confirmedAt, DateTime.utc(2026, 8, 11));
      controller.revokeTransmission();
      expect(controller.consent, isNull);
      await controller.extract();

      expect(gateway.requests, isEmpty);
      expect(controller.status, ServerAiWorkspaceStatus.failed);
    });

    for (final outcome
        in <
          ({
            String name,
            AiExtractionResult<ReceiptProposal> result,
            ServerAiWorkspaceStatus status,
            String message,
          })
        >[
          (
            name: 'quarantine',
            result: const AiExtractionQuarantined<ReceiptProposal>(
              classification: 'medicine',
            ),
            status: ServerAiWorkspaceStatus.quarantined,
            message: 'quarantined',
          ),
          (
            name: 'refusal',
            result: const AiExtractionRefused<ReceiptProposal>(
              safeReason: 'The receipt was refused safely.',
            ),
            status: ServerAiWorkspaceStatus.failed,
            message: 'refused safely',
          ),
          (
            name: 'incomplete response',
            result: const AiExtractionIncomplete<ReceiptProposal>(
              safeReason: 'The receipt was incomplete.',
            ),
            status: ServerAiWorkspaceStatus.failed,
            message: 'incomplete',
          ),
          (
            name: 'provider failure',
            result: const AiExtractionFailure<ReceiptProposal>(
              code: 'provider_failure',
              safeMessage: 'The receipt provider failed safely.',
            ),
            status: ServerAiWorkspaceStatus.failed,
            message: 'failed safely',
          ),
        ]) {
      test('receipt ${outcome.name} maps to a safe terminal state', () async {
        final repository = _ServerRepository(_workspace());
        final controller = _controller(
          repository: repository,
          gateway: _receiptGateway(outcome.result),
        );
        addTearDown(controller.dispose);

        await _loadPrepareConsentExtract(controller);

        expect(controller.status, outcome.status);
        expect(controller.safeMessage, contains(outcome.message));
        expect(controller.prepared, isNull);
      });
    }

    test(
      'stock success uses stock schema and loads only matching review',
      () async {
        final repository = _ServerRepository(_workspace());
        repository.extraction = _review(
          extractionId: 'stock-proposal-1',
          kind: AiExtractionKind.stockPhoto,
          type: AiCandidateType.stockItem,
        );
        final gateway = FakeGateway(
          route: AiGatewayRoute.serverProxyCloud,
          stockHandler: (request) async =>
              AiExtractionSuccess<StockPhotoProposal>(
                proposal: stockProposal(runId: request.runId),
                metadata: runMetadata,
              ),
        );
        final controller = _controller(
          repository: repository,
          media: FakeMediaPreparation(
            preparedBatch(purpose: AiExtractionKind.stockPhoto),
          ),
          gateway: gateway,
        );
        addTearDown(controller.dispose);

        await _loadPrepareConsentExtract(
          controller,
          asset: _asset(purpose: AiExtractionKind.stockPhoto),
        );

        expect(controller.stockProposal?.id, 'stock-proposal-1');
        expect(controller.receiptProposal, isNull);
        expect(controller.status, ServerAiWorkspaceStatus.reviewRequired);
        expect(gateway.requests.single.schemaVersion, 'stock-photo-v1');
        expect(
          gateway.requests.single.promptVersion,
          'stock-photo-extraction-v1',
        );
      },
    );

    for (final outcome
        in <
          ({
            String name,
            AiExtractionResult<StockPhotoProposal> result,
            ServerAiWorkspaceStatus status,
          })
        >[
          (
            name: 'quarantine',
            result: const AiExtractionQuarantined<StockPhotoProposal>(
              classification: 'medicine',
            ),
            status: ServerAiWorkspaceStatus.quarantined,
          ),
          (
            name: 'refusal',
            result: const AiExtractionRefused<StockPhotoProposal>(
              safeReason: 'Stock image refused.',
            ),
            status: ServerAiWorkspaceStatus.failed,
          ),
          (
            name: 'incomplete response',
            result: const AiExtractionIncomplete<StockPhotoProposal>(
              safeReason: 'Stock image incomplete.',
            ),
            status: ServerAiWorkspaceStatus.failed,
          ),
          (
            name: 'provider failure',
            result: const AiExtractionFailure<StockPhotoProposal>(
              code: 'provider_failure',
              safeMessage: 'Stock image failed safely.',
            ),
            status: ServerAiWorkspaceStatus.failed,
          ),
        ]) {
      test('stock ${outcome.name} maps to a safe terminal state', () async {
        final repository = _ServerRepository(_workspace());
        final gateway = FakeGateway(
          route: AiGatewayRoute.serverProxyCloud,
          stockHandler: (_) async => outcome.result,
        );
        final controller = _controller(
          repository: repository,
          media: FakeMediaPreparation(
            preparedBatch(purpose: AiExtractionKind.stockPhoto),
          ),
          gateway: gateway,
        );
        addTearDown(controller.dispose);

        await _loadPrepareConsentExtract(
          controller,
          asset: _asset(purpose: AiExtractionKind.stockPhoto),
        );

        expect(controller.status, outcome.status);
        expect(controller.safeMessage, isNotNull);
      });
    }

    test(
      'gateway route, readiness, and unexpected failures are contained',
      () async {
        final routeController = _controller(
          repository: _ServerRepository(_workspace()),
          gateway: FakeGateway(
            route: AiGatewayRoute.directStrictLocal,
            receiptHandler: (_) async => throw StateError('must not transmit'),
          ),
        );
        addTearDown(routeController.dispose);
        await _loadPrepareConsentExtract(routeController);
        expect(routeController.safeMessage, contains('secure AI connection'));

        final readinessController = _controller(
          repository: _ServerRepository(_workspace()),
          gateway: FakeGateway(
            route: AiGatewayRoute.serverProxyCloud,
            gatewayReadiness: const AiGatewayReadiness(
              state: AiGatewayReadinessState.unavailable,
              safeMessage: 'Provider maintenance is in progress.',
            ),
            receiptHandler: (_) async => throw StateError('must not transmit'),
          ),
        );
        addTearDown(readinessController.dispose);
        await _loadPrepareConsentExtract(readinessController);
        expect(readinessController.safeMessage, contains('maintenance'));

        final failureController = _controller(
          repository: _ServerRepository(_workspace()),
          gateway: FakeGateway(
            route: AiGatewayRoute.serverProxyCloud,
            receiptHandler: (_) async => throw StateError('private SDK error'),
          ),
        );
        addTearDown(failureController.dispose);
        await _loadPrepareConsentExtract(failureController);
        expect(
          failureController.safeMessage,
          'AI extraction could not be completed safely.',
        );

        final serverFailureController = _controller(
          repository: _ServerRepository(_workspace()),
          gateway: FakeGateway(
            route: AiGatewayRoute.serverProxyCloud,
            receiptHandler: (_) async => throw const AiServerException(
              AiServerFailureKind.invalidResponse,
            ),
          ),
        );
        addTearDown(serverFailureController.dispose);
        await _loadPrepareConsentExtract(serverFailureController);
        expect(
          serverFailureController.safeMessage,
          contains('unexpected response'),
        );
      },
    );
  });

  group('review and access lifecycle', () {
    test(
      'server authorization denial is terminal and clears private state',
      () async {
        final repository = _ServerRepository(_workspace());
        final media = FakeMediaPreparation(preparedBatch());
        final controller = _controller(repository: repository, media: media);
        addTearDown(controller.dispose);
        await controller.load();
        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(),
        );
        controller.confirmTransmission();
        expect(controller.prepared, isNotNull);
        expect(controller.consent, isNotNull);

        repository.settingsError = const AiServerException(
          AiServerFailureKind.authorizationDenied,
        );
        await controller.updateSettings(
          const AiSettingsUpdate(
            mode: AiServerMode.serverProxy,
            provider: 'openai',
            model: 'gpt-5-mini',
            expectedRevision: 1,
          ),
        );

        expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
        expect(controller.safeMessage, contains('Access to this household'));
        expect(controller.workspace, isNull);
        expect(controller.selectedProvider, isNull);
        expect(controller.prepared, isNull);
        expect(controller.consent, isNull);
        expect(controller.receiptProposal, isNull);
        expect(controller.stockProposal, isNull);
        expect(controller.review, isNull);
        expect(media.discardCalls, 1);
        expect(repository.inventoryOrPurchaseMutationCalls, 0);
      },
    );

    test('load authorization denial enters terminal access state', () async {
      final repository = _ServerRepository(_workspace())
        ..loadError = const AiServerException(
          AiServerFailureKind.authorizationDenied,
        );
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);

      await controller.load();

      expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
      expect(controller.workspace, isNull);
      expect(controller.safeMessage, contains('Access to this household'));
    });

    for (final failurePoint in <String>['readiness', 'extraction']) {
      test('gateway $failurePoint denial discards consent and media', () async {
        final repository = _ServerRepository(_workspace());
        final media = FakeMediaPreparation(preparedBatch());
        final gateway = FakeGateway(
          route: AiGatewayRoute.serverProxyCloud,
          readinessError: failurePoint == 'readiness'
              ? const AiGatewayAuthorizationDeniedException()
              : null,
          receiptHandler: (_) async {
            if (failurePoint == 'extraction') {
              throw const AiGatewayAuthorizationDeniedException();
            }
            throw StateError('Extraction must not run after readiness denial.');
          },
        );
        final controller = _controller(
          repository: repository,
          media: media,
          gateway: gateway,
        );
        addTearDown(controller.dispose);
        await controller.load();
        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(),
        );
        controller.confirmTransmission();

        await controller.extract();

        expect(controller.status, ServerAiWorkspaceStatus.accessDenied);
        expect(controller.workspace, isNull);
        expect(controller.prepared, isNull);
        expect(controller.consent, isNull);
        expect(controller.review, isNull);
        expect(media.discardCalls, 1);
        expect(repository.inventoryOrPurchaseMutationCalls, 0);
        expect(
          gateway.requests,
          hasLength(failurePoint == 'extraction' ? 1 : 0),
        );
      });
    }

    test(
      'dispose invalidates an in-flight extraction without a late review',
      () async {
        final extraction = Completer<AiExtractionResult<ReceiptProposal>>();
        final repository = _ServerRepository(_workspace());
        final media = FakeMediaPreparation(preparedBatch());
        final controller = _controller(
          repository: repository,
          media: media,
          gateway: FakeGateway(
            route: AiGatewayRoute.serverProxyCloud,
            receiptHandler: (_) => extraction.future,
          ),
        );
        await controller.load();
        await controller.prepareOne(
          provider: controller.workspace!.profiles.single,
          asset: _asset(),
        );
        controller.confirmTransmission();
        final pending = controller.extract();
        await Future<void>.delayed(Duration.zero);

        controller.dispose();
        extraction.complete(
          AiExtractionSuccess<ReceiptProposal>(
            proposal: receiptProposal(runId: 'late-run'),
            metadata: runMetadata,
          ),
        );
        await pending;

        expect(controller.workspace, isNull);
        expect(controller.prepared, isNull);
        expect(controller.consent, isNull);
        expect(controller.receiptProposal, isNull);
        expect(controller.review, isNull);
        expect(media.discardCalls, 1);
        expect(repository.reviewCalls, 0);
        expect(repository.inventoryOrPurchaseMutationCalls, 0);
      },
    );

    test(
      'review rejects missing, unknown, repeated, and invalid server data',
      () async {
        final repository = _ServerRepository(_workspace());
        final controller = _controller(repository: repository);
        addTearDown(controller.dispose);
        await controller.load();

        expect(controller.buildReviewHandoff(), isNull);
        expect(controller.safeMessage, contains('Complete'));
        await controller.reviewCandidate(
          position: 0,
          decision: AiCandidateDecision.accept,
        );
        expect(controller.safeMessage, contains('Reload'));
        await _prepareConsentExtract(controller);
        await controller.reviewCandidate(
          position: 99,
          decision: AiCandidateDecision.accept,
        );
        expect(controller.safeMessage, contains('already been reviewed'));

        repository.reviewError = const AiServerException(
          AiServerFailureKind.conflict,
        );
        await controller.reviewCandidate(
          position: 0,
          decision: AiCandidateDecision.reject,
        );
        expect(controller.safeMessage, contains('another device'));
        repository.reviewError = StateError('private review detail');
        await controller.reviewCandidate(
          position: 0,
          decision: AiCandidateDecision.reject,
        );
        expect(
          controller.safeMessage,
          'The review decision was not saved safely.',
        );

        repository.reviewError = null;
        repository.reviewResponse = _review(homeId: 'home-2');
        await controller.reviewCandidate(
          position: 0,
          decision: AiCandidateDecision.reject,
        );
        expect(controller.safeMessage, contains('unsafe or unexpected'));
      },
    );

    test('all-rejected review cannot become a domain handoff', () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await _loadPrepareConsentExtract(controller);

      await controller.reviewCandidate(
        position: 0,
        decision: AiCandidateDecision.reject,
      );
      expect(controller.buildReviewHandoff(), isNull);
      expect(controller.safeMessage, 'Review the AI settings and try again.');
      await controller.reviewCandidate(
        position: 0,
        decision: AiCandidateDecision.accept,
      );
      expect(controller.safeMessage, contains('already been reviewed'));
    });

    test('scope and use changes clear all extraction state', () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await controller.prepareOne(
        provider: controller.workspace!.profiles.single,
        asset: _asset(),
      );

      await controller.updateCapabilities(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-2',
          permissions: const <String>{'ai.read', 'ai.use', 'ai.manage'},
        ),
      );
      expect(controller.status, ServerAiWorkspaceStatus.idle);
      expect(controller.workspace, isNull);
      expect(controller.prepared, isNull);

      await controller.updateCapabilities(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-2',
          permissions: const <String>{'ai.read'},
        ),
      );
      expect(controller.status, ServerAiWorkspaceStatus.ready);
      expect(controller.safeMessage, isNull);
    });

    test(
      'load exceptions and late access changes cannot restore data',
      () async {
        final serverRepository = _ServerRepository(
          _workspace(),
        )..loadError = const AiServerException(AiServerFailureKind.unavailable);
        final serverController = _controller(repository: serverRepository);
        addTearDown(serverController.dispose);
        await serverController.load();
        expect(
          serverController.safeMessage,
          contains('temporarily unavailable'),
        );

        final privateRepository = _ServerRepository(_workspace())
          ..loadError = StateError('private connection details');
        final privateController = _controller(repository: privateRepository);
        addTearDown(privateController.dispose);
        await privateController.load();
        expect(
          privateController.safeMessage,
          'Household AI could not be loaded safely.',
        );

        final delayed = _DelayedServerRepository(_workspace());
        final delayedController = ServerAiWorkspaceController(
          repository: delayed,
          media: FakeMediaPreparation(preparedBatch()),
          gateway: _receiptGateway(
            const AiExtractionFailure<ReceiptProposal>(
              code: 'unused',
              safeMessage: 'unused',
            ),
          ),
          identifiers: FakeIdentifiers(),
          capabilities: AiHomeCapabilities.fromPermissions(
            homeId: 'home-1',
            permissions: const <String>{'ai.read'},
          ),
        );
        addTearDown(delayedController.dispose);
        final load = delayedController.load();
        await delayed.loadStarted.future;
        await delayedController.updateCapabilities(
          AiHomeCapabilities.fromPermissions(
            homeId: 'home-1',
            permissions: const <String>{},
          ),
        );
        delayed.completeLoad();
        await load;
        expect(delayedController.workspace, isNull);
        expect(delayedController.status, ServerAiWorkspaceStatus.accessDenied);
      },
    );
  });

  group('workspace page states and actions', () {
    testWidgets(
      'auto-load, denied, failed, and empty-profile states are explicit',
      (tester) async {
        final readyRepository = _ServerRepository(_workspace());
        final readyController = _controller(repository: readyRepository);
        addTearDown(readyController.dispose);
        await _pumpPage(tester, readyController);
        await tester.pumpAndSettle();
        expect(readyRepository.loadCalls, 1);
        expect(find.text('Privacy boundary'), findsOneWidget);
        expect(
          find.byKey(const Key('ai-direct-extraction-media-disclosure')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('ai-private-media-disclosure')),
          findsOneWidget,
        );

        final deniedController = _controller(
          repository: _ServerRepository(_workspace()),
          capabilities: AiHomeCapabilities.fromPermissions(
            homeId: 'home-1',
            permissions: const <String>{},
          ),
        );
        addTearDown(deniedController.dispose);
        await _pumpPage(tester, deniedController);
        expect(find.text('AI access unavailable'), findsOneWidget);
        expect(find.textContaining('ai.read'), findsOneWidget);

        final failedRepository = _ServerRepository(_workspace())
          ..loadError = StateError('private failure');
        final failedController = _controller(repository: failedRepository);
        addTearDown(failedController.dispose);
        await _pumpPage(tester, failedController);
        await tester.pumpAndSettle();
        expect(find.text('AI settings are not loaded'), findsOneWidget);
        final retry = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Try again'),
        );
        expect(retry.onPressed, isNotNull);
        retry.onPressed!();
        await tester.pumpAndSettle();
        expect(failedRepository.loadCalls, 2);

        final emptyRepository = _ServerRepository(
          _workspace(profiles: const []),
        );
        final emptyController = _controller(repository: emptyRepository);
        addTearDown(emptyController.dispose);
        await emptyController.load();
        await _pumpPage(tester, emptyController);
        expect(find.textContaining('No provider profile'), findsOneWidget);
        await _scrollTo(tester, const Key('ai-pick-receipt'));
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('ai-pick-receipt')))
              .onPressed,
          isNull,
        );
      },
    );

    testWidgets('manager controls send exact revisioned write-only requests', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-enable-profile'));
      await tester.tap(find.byKey(const Key('ai-enable-profile')));
      await tester.pumpAndSettle();
      expect(repository.lastSettingsUpdate?.expectedRevision, 1);
      await _scrollTo(tester, const Key('ai-single-profile-policy'));
      await tester.tap(find.byKey(const Key('ai-single-profile-policy')));
      await tester.pumpAndSettle();
      expect(repository.lastPolicyUpdate?.extractionProfileIds, <String>[
        'provider-1',
      ]);

      await tester.tap(find.byKey(const Key('ai-replace-credential')));
      await tester.pumpAndSettle();
      expect(find.text('Replace provider credential'), findsOneWidget);
      final credentialField = find.byKey(const Key('ai-credential-field'));
      expect(tester.widget<TextField>(credentialField).obscureText, isTrue);
      await tester.enterText(credentialField, 'rotated-write-only-secret');
      await tester.tap(find.byKey(const Key('ai-submit-credential')));
      await tester.pumpAndSettle();
      expect(repository.lastCredential, 'rotated-write-only-secret');
      expect(repository.lastProfileDraft?.expectedRevision, 1);

      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Add provider profile'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('ai-profile-label-field')),
        'Household backup',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-model-field')),
        'gpt-backup',
      );
      await tester.enterText(
        find.byKey(const Key('ai-new-profile-credential-field')),
        'new-write-only-secret',
      );
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();
      expect(repository.lastProfileDraft?.id, isNull);
      expect(repository.lastProfileDraft?.label, 'Household backup');
      expect(repository.lastProfileDraft?.expectedRevision, 0);
      expect(repository.lastCredential, 'new-write-only-secret');
    });

    testWidgets('stock quarantine and consent revocation are visible', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(
        repository: repository,
        media: FakeMediaPreparation(
          preparedBatch(purpose: AiExtractionKind.stockPhoto),
        ),
        gateway: FakeGateway(
          route: AiGatewayRoute.serverProxyCloud,
          stockHandler: (_) async =>
              const AiExtractionQuarantined<StockPhotoProposal>(
                classification: 'medicine',
              ),
        ),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(
        tester,
        controller,
        picker: (kind) async => _asset(purpose: kind),
      );

      await _scrollTo(tester, const Key('ai-pick-stock'));
      await tester.tap(find.byKey(const Key('ai-pick-stock')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('ai-transmission-consent'));
      await tester.tap(find.byKey(const Key('ai-transmission-consent')));
      await tester.pump();
      expect(controller.transmissionConfirmed, isTrue);
      await tester.tap(find.byKey(const Key('ai-transmission-consent')));
      await tester.pump();
      expect(controller.transmissionConfirmed, isFalse);
      await tester.tap(find.byKey(const Key('ai-transmission-consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-send-extraction')));
      await tester.pumpAndSettle();

      expect(find.text('Image quarantined'), findsOneWidget);
      expect(find.textContaining('No inventory, purchase'), findsOneWidget);
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    });

    testWidgets(
      'review rejection and no-consumer handoff remain non-mutating',
      (tester) async {
        final repository = _ServerRepository(_workspace());
        repository.extraction = AiExtractionReview(
          homeId: 'home-1',
          extractionId: 'receipt-proposal-1',
          kind: AiExtractionKind.receipt,
          candidates: const <AiReviewCandidate>[
            AiReviewCandidate(
              homeId: 'home-1',
              extractionId: 'receipt-proposal-1',
              position: 0,
              type: AiCandidateType.receiptLine,
              label: 'Milk',
              status: AiCandidateReviewStatus.pending,
              revision: 1,
            ),
            AiReviewCandidate(
              homeId: 'home-1',
              extractionId: 'receipt-proposal-1',
              position: 1,
              type: AiCandidateType.receiptLine,
              label: 'Bread',
              status: AiCandidateReviewStatus.pending,
              revision: 1,
            ),
          ],
        );
        final controller = _controller(repository: repository);
        addTearDown(controller.dispose);
        await controller.load();
        await _pumpPage(tester, controller);
        await _completeReceiptExtraction(tester);

        await _scrollTo(tester, const Key('ai-reject-0'));
        await tester.tap(find.byKey(const Key('ai-reject-0')));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
        await _scrollTo(tester, const Key('ai-accept-1'));
        await tester.tap(find.byKey(const Key('ai-accept-1')));
        await tester.pumpAndSettle();
        await _scrollTo(tester, const Key('ai-build-review-handoff'));
        await tester.tap(find.byKey(const Key('ai-build-review-handoff')));
        await tester.pump();

        expect(
          find.textContaining('ordinary household command'),
          findsOneWidget,
        );
        expect(repository.inventoryOrPurchaseMutationCalls, 0);
      },
    );

    testWidgets('loading and processing states expose bounded progress only', (
      tester,
    ) async {
      final delayedRepository = _DelayedServerRepository(_workspace());
      final loadingController = ServerAiWorkspaceController(
        repository: delayedRepository,
        media: FakeMediaPreparation(preparedBatch()),
        gateway: _receiptGateway(
          const AiExtractionFailure<ReceiptProposal>(
            code: 'unused',
            safeMessage: 'unused',
          ),
        ),
        identifiers: FakeIdentifiers(),
        capabilities: AiHomeCapabilities.fromPermissions(
          homeId: 'home-1',
          permissions: const <String>{'ai.read'},
        ),
      );
      addTearDown(loadingController.dispose);
      await _pumpPage(tester, loadingController);
      await delayedRepository.loadStarted.future;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      delayedRepository.completeLoad();
      await tester.pumpAndSettle();

      final extractionResult = Completer<AiExtractionResult<ReceiptProposal>>();
      final repository = _ServerRepository(_workspace());
      final processingController = _controller(
        repository: repository,
        gateway: FakeGateway(
          route: AiGatewayRoute.serverProxyCloud,
          receiptHandler: (_) => extractionResult.future,
        ),
      );
      addTearDown(processingController.dispose);
      await processingController.load();
      await _pumpPage(tester, processingController);
      await _scrollTo(tester, const Key('ai-pick-receipt'));
      await tester.tap(find.byKey(const Key('ai-pick-receipt')));
      await tester.pumpAndSettle();
      await _scrollTo(tester, const Key('ai-transmission-consent'));
      await tester.tap(find.byKey(const Key('ai-transmission-consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-send-extraction')));
      await tester.pump();

      expect(processingController.status, ServerAiWorkspaceStatus.processing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      extractionResult.complete(
        const AiExtractionQuarantined<ReceiptProposal>(
          classification: 'medicine',
        ),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('profile selection and dialog cancellation preserve intent', (
      tester,
    ) async {
      final repository = _ServerRepository(
        _workspace(
          profiles: <AiProviderProfile>[
            serverProvider(),
            _secondServerProvider(),
          ],
        ),
      );
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-profile-provider-2'));
      await tester.tap(find.byKey(const Key('ai-profile-provider-2')));
      await tester.pump();
      await _scrollTo(tester, const Key('ai-pick-receipt'));
      await tester.tap(find.byKey(const Key('ai-pick-receipt')));
      await tester.pumpAndSettle();
      expect(controller.selectedProvider?.id, 'provider-2');
      await controller.clearExtraction();
      await tester.pump();

      await _scrollTo(tester, const Key('ai-replace-credential'));
      await tester.tap(find.byKey(const Key('ai-replace-credential')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.saveProfileCalls, 0);

      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anthropic').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(repository.saveProfileCalls, 0);
    });

    testWidgets('an empty extraction review remains explicit and inert', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      repository.extraction = AiExtractionReview(
        homeId: 'home-1',
        extractionId: 'receipt-proposal-1',
        kind: AiExtractionKind.receipt,
        candidates: const <AiReviewCandidate>[],
      );
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _completeReceiptExtraction(tester);
      await tester.scrollUntilVisible(
        find.text('The extraction produced no candidates.'),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      expect(
        find.text('The extraction produced no candidates.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('ai-build-review-handoff')),
            )
            .onPressed,
        isNull,
      );
      expect(repository.inventoryOrPurchaseMutationCalls, 0);
    });
  });

  group('person-scoped BYOK profiles', () {
    test('sharing capability requires both manage and the owner role', () {
      expect(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-1',
          permissions: const <String>{'ai.read', 'ai.manage'},
        ).mayShareHomeProfiles,
        isFalse,
      );
      expect(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-1',
          permissions: const <String>{'ai.read', 'ownership.transfer'},
        ).mayShareHomeProfiles,
        isFalse,
      );
      expect(
        AiHomeCapabilities.fromPermissions(
          homeId: 'home-1',
          permissions: const <String>{
            'ai.read',
            'ai.manage',
            'ownership.transfer',
          },
        ).mayShareHomeProfiles,
        isTrue,
      );
    });

    test('home-scope sharing is refused without the owner role', () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.saveProviderProfile(
        draft: const AiProviderProfileDraft(
          id: null,
          label: 'Shared profile',
          provider: 'openai',
          model: 'gpt-5-mini',
          estimatedCostMicros: 0,
          expectedRevision: 0,
          ownerScope: AiProfileOwnerScope.home,
        ),
      );

      expect(controller.status, ServerAiWorkspaceStatus.failed);
      expect(controller.safeMessage, contains('home owner'));
      expect(repository.saveProfileCalls, 0);
    });

    test('the home owner may deliberately share a profile', () async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(
        repository: repository,
        capabilities: _ownerCapabilities(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await controller.saveProviderProfile(
        draft: const AiProviderProfileDraft(
          id: null,
          label: 'Shared profile',
          provider: 'openai-compatible',
          model: 'gpt-5-mini',
          estimatedCostMicros: 0,
          expectedRevision: 0,
          ownerScope: AiProfileOwnerScope.home,
          endpoint: 'https://ai.example.test/v1',
        ),
      );

      expect(repository.saveProfileCalls, 1);
      expect(repository.lastProfileDraft?.ownerScope, AiProfileOwnerScope.home);
      expect(
        repository.lastProfileDraft?.endpoint,
        'https://ai.example.test/v1',
      );
      expect(controller.status, ServerAiWorkspaceStatus.ready);
    });

    testWidgets('scope badges distinguish private and home profiles', (
      tester,
    ) async {
      final repository = _ServerRepository(
        _workspace(
          profiles: <AiProviderProfile>[
            serverProvider(),
            _secondServerProvider().copyWith(
              ownerScope: AiProfileOwnerScope.home,
            ),
          ],
        ),
      );
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      expect(
        find.descendant(
          of: find.byKey(const Key('ai-profile-scope-provider-1')),
          matching: find.text('Private to me'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('ai-profile-scope-provider-2')),
          matching: find.text('Shared with this home'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the shared-scope choice stays owner-gated in the dialog', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-add-profile'));
      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      final homeTile = tester.widget<RadioListTile<AiProfileOwnerScope>>(
        find.byKey(const Key('ai-profile-scope-home')),
      );
      expect(homeTile.enabled, isFalse);
      expect(
        find.text('Only the home owner can share a profile with this home.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-label-field')),
        'Personal profile',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-model-field')),
        'gpt-5-mini',
      );
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();
      expect(
        repository.lastProfileDraft?.ownerScope,
        AiProfileOwnerScope.private,
      );
    });

    testWidgets('the owner may pick the shared scope in the dialog', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(
        repository: repository,
        capabilities: _ownerCapabilities(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-add-profile'));
      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      expect(find.textContaining('explicit home-owner choice'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('ai-profile-label-field')),
        'Household profile',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-model-field')),
        'gpt-5-mini',
      );
      await tester.ensureVisible(
        find.byKey(const Key('ai-profile-scope-home')),
      );
      await tester.tap(find.byKey(const Key('ai-profile-scope-home')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();
      expect(repository.lastProfileDraft?.ownerScope, AiProfileOwnerScope.home);
    });

    testWidgets('the endpoint field is provider-gated and validated', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-add-profile'));
      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ai-profile-endpoint-field')), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI-compatible').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('ai-profile-endpoint-field')),
        findsOneWidget,
      );
      expect(find.textContaining('deployment opt-in'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('ai-profile-label-field')),
        'Compatible profile',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-model-field')),
        'compat-model',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-endpoint-field')),
        'http://ai.example.test/v1',
      );
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();
      expect(find.text('The endpoint must use HTTPS.'), findsOneWidget);
      expect(repository.saveProfileCalls, 0);

      await tester.enterText(
        find.byKey(const Key('ai-profile-endpoint-field')),
        'https://ai.example.test/v1',
      );
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();
      expect(repository.saveProfileCalls, 1);
      expect(
        repository.lastProfileDraft?.endpoint,
        'https://ai.example.test/v1',
      );
    });

    testWidgets('an ollama endpoint may use a local-network address', (
      tester,
    ) async {
      final repository = _ServerRepository(_workspace());
      final controller = _controller(repository: repository);
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-add-profile'));
      await tester.tap(find.byKey(const Key('ai-add-profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ollama').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-profile-label-field')),
        'Kitchen Ollama',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-model-field')),
        'gemma3',
      );
      await tester.enterText(
        find.byKey(const Key('ai-profile-endpoint-field')),
        'http://192.168.1.20:11434',
      );
      await tester.tap(find.byKey(const Key('ai-create-profile')));
      await tester.pumpAndSettle();

      expect(repository.saveProfileCalls, 1);
      expect(repository.lastProfileDraft?.provider, 'ollama');
      expect(
        repository.lastProfileDraft?.endpoint,
        'http://192.168.1.20:11434',
      );
    });

    testWidgets('editing keeps identity and warns about credential loss', (
      tester,
    ) async {
      final repository = _ServerRepository(
        _workspace(
          profiles: <AiProviderProfile>[
            serverProvider(ownerScope: AiProfileOwnerScope.home),
          ],
        ),
      );
      final controller = _controller(
        repository: repository,
        capabilities: _ownerCapabilities(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-edit-profile'));
      await tester.tap(find.byKey(const Key('ai-edit-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Edit provider profile'), findsOneWidget);
      expect(
        find.byKey(const Key('ai-profile-credential-clear-note')),
        findsOneWidget,
      );
      expect(find.text('OpenAI via Providentia'), findsWidgets);
      await tester.tap(find.byKey(const Key('ai-save-profile')));
      await tester.pumpAndSettle();

      expect(repository.lastProfileDraft?.id, 'provider-1');
      expect(repository.lastProfileDraft?.expectedRevision, 1);
      expect(repository.lastProfileDraft?.ownerScope, AiProfileOwnerScope.home);
      expect(repository.lastCredential, isNull);
    });

    testWidgets('credential replacement preserves scope and endpoint', (
      tester,
    ) async {
      final shared = AiProviderProfile(
        id: 'provider-1',
        homeId: 'home-1',
        displayName: 'Household compatible',
        kind: AiProviderKind.openAiCompatible,
        transport: AiTransport.serverProxy,
        protocol: AiEndpointProtocol.openAiChatCompletions,
        ownerScope: AiProfileOwnerScope.home,
        endpoint: Uri.parse('https://ai.example.test/v1'),
        model: 'compat-model',
        capabilities: const <AiCapability>{
          AiCapability.vision,
          AiCapability.strictJsonSchema,
        },
        availability: AiProviderAvailability.available,
        credentialConfigured: true,
        revision: 2,
      );
      final repository = _ServerRepository(
        _workspace(profiles: <AiProviderProfile>[shared]),
      );
      final controller = _controller(
        repository: repository,
        capabilities: _ownerCapabilities(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      await _pumpPage(tester, controller);

      await _scrollTo(tester, const Key('ai-replace-credential'));
      await tester.tap(find.byKey(const Key('ai-replace-credential')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('ai-credential-field')),
        'rotated-write-only-secret',
      );
      await tester.tap(find.byKey(const Key('ai-submit-credential')));
      await tester.pumpAndSettle();

      expect(repository.lastProfileDraft?.ownerScope, AiProfileOwnerScope.home);
      expect(
        repository.lastProfileDraft?.endpoint,
        'https://ai.example.test/v1',
      );
      expect(repository.lastCredential, 'rotated-write-only-secret');
    });
  });
}

AiHomeCapabilities _ownerCapabilities() => AiHomeCapabilities.fromPermissions(
  homeId: 'home-1',
  permissions: const <String>{
    'ai.read',
    'ai.use',
    'ai.manage',
    'ownership.transfer',
  },
);

final Uint8List _transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

AiProviderProfileDraft _existingProfileDraft() => const AiProviderProfileDraft(
  id: 'provider-1',
  label: 'Primary provider',
  provider: 'openai',
  model: 'gpt-5-mini',
  estimatedCostMicros: 0,
  expectedRevision: 1,
);

AiOrchestrationPolicyUpdate _policyUpdate() => AiOrchestrationPolicyUpdate(
  extractionProfileIds: const <String>['provider-1'],
  validationProfileId: null,
  maxAttempts: 1,
  maxTotalTokens: 50000,
  maxEstimatedCostMicros: 1000000,
  expectedRevision: 1,
);

FakeGateway _receiptGateway(AiExtractionResult<ReceiptProposal> result) =>
    FakeGateway(
      route: AiGatewayRoute.serverProxyCloud,
      receiptHandler: (_) async => result,
    );

Future<void> _loadPrepareConsentExtract(
  ServerAiWorkspaceController controller, {
  AiMediaAsset? asset,
}) async {
  await controller.load();
  await _prepareConsentExtract(controller, asset: asset);
}

Future<void> _prepareConsentExtract(
  ServerAiWorkspaceController controller, {
  AiMediaAsset? asset,
}) async {
  await controller.prepareOne(
    provider: controller.workspace!.profiles.single,
    asset: asset ?? _asset(),
  );
  controller.confirmTransmission();
  await controller.extract();
}

Future<void> _pumpPage(
  WidgetTester tester,
  ServerAiWorkspaceController controller, {
  AiSingleImagePicker? picker,
  AiPreparedImageReader? readPreparedImage,
  ValueChanged<AiReviewHandoff>? onReviewHandoff,
}) => tester.pumpWidget(
  MaterialApp(
    home: ServerAiWorkspacePage(
      key: UniqueKey(),
      controller: controller,
      pickSingleImage: picker ?? (_) async => _asset(),
      readPreparedImage: readPreparedImage ?? (_) async => _transparentPixel,
      onReviewHandoff: onReviewHandoff,
    ),
  ),
);

Future<void> _scrollTo(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _completeReceiptExtraction(WidgetTester tester) async {
  await _scrollTo(tester, const Key('ai-pick-receipt'));
  await tester.tap(find.byKey(const Key('ai-pick-receipt')));
  await tester.pumpAndSettle();
  await _scrollTo(tester, const Key('ai-transmission-consent'));
  await tester.tap(find.byKey(const Key('ai-transmission-consent')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('ai-send-extraction')));
  await tester.pumpAndSettle();
}

ServerAiWorkspaceController _controller({
  required _ServerRepository repository,
  AiHomeCapabilities? capabilities,
  AiMediaPreparationPort? media,
  FakeGateway? gateway,
}) => ServerAiWorkspaceController(
  repository: repository,
  media: media ?? FakeMediaPreparation(preparedBatch()),
  gateway:
      gateway ??
      FakeGateway(
        route: AiGatewayRoute.serverProxyCloud,
        receiptHandler: (request) async => AiExtractionSuccess<ReceiptProposal>(
          proposal: receiptProposal(runId: request.runId),
          metadata: runMetadata,
        ),
      ),
  identifiers: FakeIdentifiers(),
  capabilities:
      capabilities ??
      AiHomeCapabilities.fromPermissions(
        homeId: 'home-1',
        permissions: const <String>{'ai.read', 'ai.use', 'ai.manage'},
      ),
  clock: () => DateTime.utc(2026, 8, 11),
);

final class _DelayedMediaPreparation implements AiMediaPreparationPort {
  _DelayedMediaPreparation(this.batch);

  final PreparedMediaBatch batch;
  final Completer<void> started = Completer<void>();
  final Completer<PreparedMediaBatch> _completion =
      Completer<PreparedMediaBatch>();
  int discardCalls = 0;

  void complete() => _completion.complete(batch);

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) {
    if (!started.isCompleted) started.complete();
    return _completion.future;
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    discardCalls++;
  }
}

final class _OrderedMediaPreparation implements AiMediaPreparationPort {
  final List<List<String>> preparedSourceIds = <List<String>>[];
  int discardCalls = 0;

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    preparedSourceIds.add(
      assets.map((asset) => asset.id).toList(growable: false),
    );
    return PreparedMediaBatch(
      id: 'ordered-${assets.length}',
      homeId: homeId,
      purpose: purpose,
      media: <PreparedAiMedia>[
        for (var index = 0; index < assets.length; index++)
          PreparedAiMedia(
            sourceMediaId: assets[index].id,
            ephemeralReference: 'ephemeral://ordered/$index',
            previewReference: 'ephemeral://ordered/$index',
            sha256: List<String>.filled(
              64,
              String.fromCharCode(97 + index),
            ).join(),
            mimeType: 'image/jpeg',
            byteLength: 1024,
            width: 100,
            height: 200,
            pageIndex: assets[index].pageIndex ?? index,
          ),
      ],
    );
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    discardCalls++;
  }
}

final class _ThrowingMedia implements AiMediaPreparationPort {
  _ThrowingMedia({this.batch, this.prepareError, this.discardError});

  final PreparedMediaBatch? batch;
  final Object? prepareError;
  final Object? discardError;
  int discardCalls = 0;

  @override
  Future<PreparedMediaBatch> prepare({
    required String homeId,
    required AiExtractionKind purpose,
    required List<AiMediaAsset> assets,
  }) async {
    if (prepareError case final error?) throw error;
    return batch!;
  }

  @override
  Future<void> discard(PreparedMediaBatch batch) async {
    discardCalls++;
    if (discardError case final error?) throw error;
  }
}

AiMediaAsset _asset({
  String homeId = 'home-1',
  AiExtractionKind purpose = AiExtractionKind.receipt,
}) => AiMediaAsset(
  id: 'source-1',
  homeId: homeId,
  localReference: 'registered://source-1',
  purpose: purpose,
  mimeType: 'image/jpeg',
  byteLength: 12000,
  createdAt: DateTime.utc(2026, 8, 11),
);

AiMediaAsset _receiptPage(String id, int pageIndex) => AiMediaAsset(
  id: id,
  homeId: 'home-1',
  localReference: 'registered://$id',
  purpose: AiExtractionKind.receipt,
  mimeType: 'image/jpeg',
  byteLength: 12000,
  createdAt: DateTime.utc(2026, 8, 11),
  pageIndex: pageIndex,
);

AiProviderProfile _multiImageProvider() {
  final base = serverProvider();
  return base.copyWith(
    capabilities: <AiCapability>{...base.capabilities, AiCapability.multiImage},
  );
}

PreparedMediaBatch _preparedBatch({
  String homeId = 'home-1',
  AiExtractionKind purpose = AiExtractionKind.receipt,
}) => PreparedMediaBatch(
  id: 'batch-custom',
  homeId: homeId,
  purpose: purpose,
  media: const <PreparedAiMedia>[
    PreparedAiMedia(
      sourceMediaId: 'media-1',
      ephemeralReference: 'ephemeral://batch-custom/page-1',
      previewReference: 'preview://batch-custom/page-1',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      mimeType: 'image/jpeg',
      byteLength: 12000,
      width: 1200,
      height: 1600,
      pageIndex: 0,
    ),
  ],
);

AiExtractionReview _review({
  String homeId = 'home-1',
  String extractionId = 'receipt-proposal-1',
  AiExtractionKind kind = AiExtractionKind.receipt,
  AiCandidateType type = AiCandidateType.receiptLine,
}) => AiExtractionReview(
  homeId: homeId,
  extractionId: extractionId,
  kind: kind,
  candidates: <AiReviewCandidate>[
    AiReviewCandidate(
      homeId: homeId,
      extractionId: extractionId,
      position: 0,
      type: type,
      label: 'Candidate',
      status: AiCandidateReviewStatus.pending,
      revision: 1,
    ),
  ],
);

AiProviderProfile _secondServerProvider() => AiProviderProfile(
  id: 'provider-2',
  homeId: 'home-1',
  displayName: 'Anthropic via Providentia',
  kind: AiProviderKind.anthropic,
  transport: AiTransport.serverProxy,
  protocol: AiEndpointProtocol.anthropicMessages,
  model: 'claude-sonnet',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
  },
  availability: AiProviderAvailability.available,
  credentialConfigured: true,
  revision: 1,
);

AiServerWorkspace _workspace({
  String homeId = 'home-1',
  List<AiProviderProfile>? profiles,
}) {
  final profile = serverProvider();
  final scoped = homeId == profile.homeId
      ? profile
      : AiProviderProfile(
          id: profile.id,
          homeId: homeId,
          displayName: profile.displayName,
          kind: profile.kind,
          transport: profile.transport,
          protocol: profile.protocol,
          model: profile.model,
          capabilities: profile.capabilities,
          availability: profile.availability,
          credentialConfigured: profile.credentialConfigured,
          revision: profile.revision,
        );
  final scopedProfiles = profiles ?? <AiProviderProfile>[scoped];
  return AiServerWorkspace(
    homeId: homeId,
    settings: AiServerSettings(
      homeId: homeId,
      mode: AiServerMode.serverProxy,
      provider: 'openai',
      model: profile.model,
      revision: 1,
      availableProviders: const <AiAvailableServerProvider>[
        AiAvailableServerProvider(id: 'openai', requiresCredential: true),
      ],
      credentialEncryptionAvailable: true,
      humanReviewRequired: true,
      serverPersistsUploadedMedia: false,
      mediaHandling: AiMediaHandling(
        directExtractionUpload: AiDirectExtractionUpload.transientNotPersisted,
        privateMediaStorage: AiPrivateMediaStorage.explicitEncryptedOptIn,
        privateMediaRetentionOptions: const <AiPrivateMediaRetention>{
          AiPrivateMediaRetention.transient,
          AiPrivateMediaRetention.retained,
        },
        plaintextMediaAtRest: false,
        cloudProviderTransmissionRequiresConsent: true,
      ),
    ),
    profiles: scopedProfiles,
    policy: AiOrchestrationPolicy(
      homeId: homeId,
      extractionProfileIds: scopedProfiles
          .map((profile) => profile.id)
          .toList(),
      validationProfileId: null,
      maxAttempts: 1,
      maxTotalTokens: 50000,
      maxEstimatedCostMicros: 1000000,
      revision: 1,
    ),
  );
}

final class _ServerRepository implements ServerAiRepository {
  _ServerRepository(this.value)
    : extraction = AiExtractionReview(
        homeId: value.homeId,
        extractionId: 'receipt-proposal-1',
        kind: AiExtractionKind.receipt,
        candidates: <AiReviewCandidate>[
          AiReviewCandidate(
            homeId: value.homeId,
            extractionId: 'receipt-proposal-1',
            position: 0,
            type: AiCandidateType.receiptLine,
            label: 'Milk',
            status: AiCandidateReviewStatus.pending,
            revision: 1,
          ),
        ],
      );

  AiServerWorkspace value;
  AiExtractionReview extraction;
  int loadCalls = 0;
  int settingsCalls = 0;
  int saveProfileCalls = 0;
  int policyCalls = 0;
  int reviewCalls = 0;
  int inventoryOrPurchaseMutationCalls = 0;
  Object? loadError;
  Object? settingsError;
  Object? saveProfileError;
  Object? policyError;
  Object? loadReviewError;
  Object? reviewError;
  AiExtractionReview? reviewResponse;
  AiSettingsUpdate? lastSettingsUpdate;
  AiProviderProfileDraft? lastProfileDraft;
  String? lastCredential;
  AiOrchestrationPolicyUpdate? lastPolicyUpdate;

  @override
  Future<void> deleteProviderProfile({
    required String homeId,
    required String profileId,
    required int expectedRevision,
  }) async {}

  @override
  Future<AiExtractionReview> loadExtractionReview({
    required String homeId,
    required String extractionId,
  }) async {
    if (loadReviewError case final error?) throw error;
    return extraction;
  }

  @override
  Future<AiServerWorkspace> loadWorkspace({required String homeId}) async {
    loadCalls++;
    if (loadError case final error?) throw error;
    return value;
  }

  @override
  Future<AiExtractionReview> reviewCandidate({
    required AiReviewCandidate candidate,
    required AiCandidateDecision decision,
  }) async {
    reviewCalls++;
    if (reviewError case final error?) throw error;
    if (reviewResponse case final response?) return response;
    final updatedCandidates = extraction.candidates
        .map(
          (item) => item.position == candidate.position
              ? AiReviewCandidate(
                  homeId: candidate.homeId,
                  extractionId: candidate.extractionId,
                  position: candidate.position,
                  type: candidate.type,
                  label: candidate.label,
                  status: decision == AiCandidateDecision.accept
                      ? AiCandidateReviewStatus.accepted
                      : AiCandidateReviewStatus.rejected,
                  revision: candidate.revision + 1,
                )
              : item,
        )
        .toList(growable: false);
    extraction = AiExtractionReview(
      homeId: candidate.homeId,
      extractionId: candidate.extractionId,
      kind: extraction.kind,
      candidates: updatedCandidates,
    );
    return extraction;
  }

  @override
  Future<AiProviderProfile> saveProviderProfile({
    required String homeId,
    required AiProviderProfileDraft draft,
    String? credential,
  }) async {
    saveProfileCalls++;
    lastProfileDraft = draft;
    lastCredential = credential;
    if (saveProfileError case final error?) throw error;
    return value.profiles.single;
  }

  @override
  Future<AiOrchestrationPolicy> updatePolicy({
    required String homeId,
    required AiOrchestrationPolicyUpdate update,
  }) async {
    policyCalls++;
    lastPolicyUpdate = update;
    if (policyError case final error?) throw error;
    return value.policy;
  }

  @override
  Future<AiServerSettings> updateSettings({
    required String homeId,
    required AiSettingsUpdate update,
  }) async {
    settingsCalls++;
    lastSettingsUpdate = update;
    if (settingsError case final error?) throw error;
    return value.settings;
  }
}

final class _DelayedServerRepository implements ServerAiRepository {
  _DelayedServerRepository(this.workspace);

  final AiServerWorkspace workspace;
  final Completer<void> loadStarted = Completer<void>();
  final Completer<AiServerWorkspace> _loadResult =
      Completer<AiServerWorkspace>();

  void completeLoad() => _loadResult.complete(workspace);

  @override
  Future<void> deleteProviderProfile({
    required String homeId,
    required String profileId,
    required int expectedRevision,
  }) async {}

  @override
  Future<AiExtractionReview> loadExtractionReview({
    required String homeId,
    required String extractionId,
  }) => throw UnimplementedError();

  @override
  Future<AiServerWorkspace> loadWorkspace({required String homeId}) {
    if (!loadStarted.isCompleted) loadStarted.complete();
    return _loadResult.future;
  }

  @override
  Future<AiExtractionReview> reviewCandidate({
    required AiReviewCandidate candidate,
    required AiCandidateDecision decision,
  }) => throw UnimplementedError();

  @override
  Future<AiProviderProfile> saveProviderProfile({
    required String homeId,
    required AiProviderProfileDraft draft,
    String? credential,
  }) => throw UnimplementedError();

  @override
  Future<AiOrchestrationPolicy> updatePolicy({
    required String homeId,
    required AiOrchestrationPolicyUpdate update,
  }) => throw UnimplementedError();

  @override
  Future<AiServerSettings> updateSettings({
    required String homeId,
    required AiSettingsUpdate update,
  }) => throw UnimplementedError();
}
