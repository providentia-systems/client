import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/administration/application/catalog_administration_ports.dart';
import 'package:providentia/features/administration/domain/catalog_administration_models.dart';
import 'package:providentia/features/administration/infrastructure/generated_catalog_administration_repository.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  group('platform role separation', () {
    test(
      'reviewer and curator capabilities derive only from platform roles',
      () {
        expect(
          GeneratedCatalogAdministrationRepository.capabilitiesForPlatformRoles(
            const <PlatformRole>{PlatformRole.catalogReviewer},
          ),
          const <CatalogCapability>{CatalogCapability.review},
        );
        expect(
          GeneratedCatalogAdministrationRepository.capabilitiesForPlatformRoles(
            const <PlatformRole>{PlatformRole.catalogCurator},
          ),
          containsAll(<CatalogCapability>{
            CatalogCapability.review,
            CatalogCapability.curate,
            CatalogCapability.manageIcons,
            CatalogCapability.previewMerges,
            CatalogCapability.executeMerges,
            CatalogCapability.reverseMerges,
          }),
        );
        expect(
          GeneratedCatalogAdministrationRepository.capabilitiesForPlatformRoles(
            const <PlatformRole>{PlatformRole.billingOperator},
          ),
          isEmpty,
        );
        expect(
          GeneratedCatalogAdministrationRepository.capabilitiesForPlatformRoles(
            const <PlatformRole>{},
          ),
          isEmpty,
        );
      },
    );

    test('reviewer cannot call curator mutation before transport', () async {
      var requestCount = 0;
      final repository = GeneratedCatalogAdministrationRepository(
        _client((_) async {
          requestCount++;
          return _json(const <String, Object?>{});
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogReviewer},
      );

      await expectLater(
        repository.putIcon(_icon()),
        throwsA(isA<CatalogForbiddenException>()),
      );
      expect(requestCount, 0);
    });
  });

  test(
    'combined review queue drops household attribution and private fields',
    () async {
      final repository = GeneratedCatalogAdministrationRepository(
        _client((request) async {
          if (request.url.path == '/api/v1/catalog-admin/workbench') {
            if (request.url.queryParameters['queue'] != 'proposals') {
              return _json(const <String, Object?>{'data': <Object?>[]});
            }
            return _json(<String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'id': _proposalId,
                  'proposalType': 'product',
                  'payload': <String, Object?>{
                    'canonicalName': 'Rolled oats',
                    'brand': 'Example',
                    'homeId': _homeId,
                    'privateNote': 'Bottom shelf',
                  },
                  'moderationStatus': 'pending',
                  'revision': 2,
                  'submittedByUserId': _userId,
                },
              ],
            });
          }
          expect(request.url.path, '/api/v1/catalog-contributions/review');
          return _json(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': _contributionId,
                'contributionType': 'product_identity',
                'payload': <String, Object?>{
                  'canonicalName': 'Brown rice',
                  'quantity': '12',
                  'privateNote': 'Cupboard detail',
                },
                'status': 'pending',
                'revision': 1,
                'homeId': _homeId,
                'submittedByUserId': _userId,
                'consentReceiptId': _consentReceiptId,
              },
            ],
          });
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogReviewer},
      );

      final items = await repository.loadQueue();

      expect(items, hasLength(2));
      expect(
        items.map((item) => item.source),
        containsAll(<CatalogQueueSource>{
          CatalogQueueSource.governanceProposal,
          CatalogQueueSource.consentContribution,
        }),
      );
      final visible = items
          .expand((item) => <String>[item.title, item.summary])
          .join('|');
      expect(visible, contains('Rolled oats'));
      expect(visible, contains('Brown rice'));
      expect(visible, isNot(contains(_homeId)));
      expect(visible, isNot(contains(_userId)));
      expect(visible, isNot(contains('Bottom shelf')));
      expect(visible, isNot(contains('Cupboard detail')));
      expect(visible, isNot(contains(_consentReceiptId)));
    },
  );

  test(
    'proposal and contribution decisions use their exact wire enums',
    () async {
      final bodies = <String, Map<String, Object?>>{};
      final repository = GeneratedCatalogAdministrationRepository(
        _client((request) async {
          bodies[request.url.path] = _requestObject(request);
          if (request.url.path.endsWith('/decision') &&
              request.method == 'POST') {
            return _json(<String, Object?>{
              'status': 'approved',
              'entityType': 'product',
              'entityId': _productId,
            });
          }
          return http.Response('', 204);
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogReviewer},
      );
      const proposalDecision = CatalogReviewDecision(
        proposalId: _proposalId,
        decision: CatalogReviewDecisionKind.approve,
        reason: ' Confirmed public identity ',
        expectedRevision: 2,
      );
      const contributionDecision = CatalogReviewDecision(
        proposalId: _contributionId,
        decision: CatalogReviewDecisionKind.reject,
        reason: 'Not a stable public fact',
        expectedRevision: 1,
      );

      final result = await repository.decideProposal(proposalDecision);
      await repository.decideContribution(contributionDecision);

      expect(result.status, CatalogReviewStatus.approved);
      expect(result.entityId, _productId);
      expect(
        bodies['/api/v1/catalog-admin/proposals/$_proposalId/decision'],
        <String, Object?>{
          'decision': 'approve',
          'reason': 'Confirmed public identity',
          'expectedRevision': 2,
        },
      );
      expect(
        bodies['/api/v1/catalog-contributions/$_contributionId/decision'],
        <String, Object?>{
          'decision': 'rejected',
          'reason': 'Not a stable public fact',
          'expectedRevision': 1,
        },
      );
    },
  );

  test(
    'duplicate queue exposes only revision-bound global catalog IDs',
    () async {
      final repository = GeneratedCatalogAdministrationRepository(
        _client((request) async {
          expect(request.url.queryParameters['queue'], 'duplicates');
          return _json(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'conflict-a',
                'existingEntityId': _productId,
                'candidateEntityId': _duplicateId,
                'revision': 5,
                'homeId': _homeId,
                'submittedByUserId': _userId,
              },
            ],
          });
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogCurator},
      );

      final item = (await repository.loadWorkbenchQueue('duplicates')).single;

      expect(item.relatedCatalogIds, <String>[_productId, _duplicateId]);
      expect(item.revision, 5);
      final visible = <String>[
        item.title,
        item.summary,
        ...item.relatedCatalogIds,
      ].join('|');
      expect(visible, isNot(contains(_homeId)));
      expect(visible, isNot(contains(_userId)));
    },
  );

  test('authorization loss callback is fail-closed and emitted once', () async {
    var authorizationLosses = 0;
    final repository = GeneratedCatalogAdministrationRepository(
      _client((_) async => http.Response('Forbidden', 403)),
      platformRoles: const <PlatformRole>{PlatformRole.catalogReviewer},
      onAuthorizationLost: () async {
        authorizationLosses += 1;
      },
    );

    await expectLater(
      repository.loadWorkbenchQueue('proposals'),
      throwsA(isA<CatalogForbiddenException>()),
    );
    await expectLater(
      repository.loadContributionQueue(),
      throwsA(isA<CatalogForbiddenException>()),
    );

    expect(authorizationLosses, 1);
  });

  test(
    'curator preview and apply preserve revisions and aggregate privacy',
    () async {
      Map<String, Object?>? appliedBody;
      String? idempotencyKey;
      final repository = GeneratedCatalogAdministrationRepository(
        _client((request) async {
          if (request.url.path.endsWith('/merges/preview')) {
            expect(_requestObject(request), <String, Object?>{
              'survivorId': _productId,
              'duplicateIds': <Object?>[_duplicateId],
            });
            return _json(<String, Object?>{
              'survivorId': _productId,
              'duplicateIds': <Object?>[_duplicateId],
              'eligible': true,
              'products': <Object?>[
                <String, Object?>{
                  'id': _productId,
                  'canonicalName': 'Rolled oats',
                  'brand': 'Example',
                  'status': 'published',
                  'revision': 7,
                },
                <String, Object?>{
                  'id': _duplicateId,
                  'canonicalName': 'Oats rolled',
                  'brand': 'Example',
                  'status': 'published',
                  'revision': 3,
                },
              ],
              'affectedCounts': <String, Object?>{
                'variants': 1,
                'packs': 2,
                'aliases': 3,
                'icons': 1,
                'homeReferences': 4,
              },
              'conflicts': const <Object?>[],
            });
          }
          expect(request.url.path, '/api/v1/catalog-admin/merges');
          appliedBody = _requestObject(request);
          idempotencyKey = request.headers['Idempotency-Key'];
          return _json(<String, Object?>{
            'id': _mergeId,
            'status': 'applied',
            'revision': 1,
            'survivorId': _productId,
            'duplicateIds': <Object?>[_duplicateId],
            'affectedCounts': const <String, Object?>{},
          }, status: 201);
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogCurator},
        clock: () => DateTime.utc(2026, 8, 11, 12),
      );

      final preview = await repository.previewMerge(
        survivorProductId: _productId,
        absorbedProductIds: const <String>[_duplicateId],
      );
      final result = await repository.execute(
        preview: preview,
        idempotencyKey: 'catalog-merge-operation-1',
        reason: 'Confirmed duplicate',
      );

      expect(preview.eligible, isTrue);
      expect(preview.expectedRevisions[_productId], 7);
      expect(preview.expectedRevisions[_duplicateId], 3);
      expect(preview.impact.globalAliasCount, 3);
      expect(preview.impact.globalPackCount, 2);
      expect(preview.impact.privateReferenceCount, 4);
      expect(preview.impact.hasPrivateReferences, isTrue);
      expect(appliedBody, <String, Object?>{
        'survivorId': _productId,
        'expectedSurvivorRevision': 7,
        'duplicateRevisions': <String, Object?>{_duplicateId: 3},
        'reason': 'Confirmed duplicate',
      });
      expect(idempotencyKey, 'catalog-merge-operation-1');
      expect(result.eventId, _mergeId);
      expect(result.reversed, isFalse);
    },
  );

  test(
    'icon mutation sends bounded metadata without household fields',
    () async {
      Map<String, Object?>? body;
      final repository = GeneratedCatalogAdministrationRepository(
        _client((request) async {
          expect(
            request.url.path,
            '/api/v1/catalog-admin/icons/product/$_productId',
          );
          body = _requestObject(request);
          return _json(<String, Object?>{'id': _iconId, 'revision': 2});
        }),
        platformRoles: const <PlatformRole>{PlatformRole.catalogCurator},
      );

      final result = await repository.putIcon(_icon());

      expect(result.id, _iconId);
      expect(body!.keys.toSet(), <String>{
        'assetDigest',
        'mediaType',
        'altText',
        'width',
        'height',
        'byteSize',
        'provenance',
        'expectedRevision',
      });
      expect(body, isNot(contains('homeId')));
      expect(body, isNot(contains('userId')));
    },
  );

  test('icon queue preserves the global target type and revision', () async {
    final repository = GeneratedCatalogAdministrationRepository(
      _client((request) async {
        expect(request.url.queryParameters['queue'], 'icons');
        return _json(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'targetType': 'product',
              'targetId': _productId,
              'canonicalName': 'Rolled oats',
              'revision': 9,
              'homeId': _homeId,
            },
          ],
        });
      }),
      platformRoles: const <PlatformRole>{PlatformRole.catalogCurator},
    );

    final item = (await repository.loadWorkbenchQueue('icons')).single;

    expect(item.source, CatalogQueueSource.icon);
    expect(item.iconTargetType, CatalogIconTargetType.product);
    expect(item.id, _productId);
    expect(item.revision, 9);
    expect(
      <String>[item.title, item.summary].join('|'),
      isNot(contains(_homeId)),
    );
  });

  test('invalid icon metadata is rejected before transport', () {
    expect(
      () => CatalogIconWrite(
        targetType: CatalogIconTargetType.product,
        targetId: _productId,
        assetDigest: 'not-a-digest',
        mediaType: 'image/png',
        altText: 'Rolled oats',
        width: 256,
        height: 256,
        byteSize: 1024,
        provenance: 'Catalog asset',
        expectedRevision: 1,
      ),
      throwsArgumentError,
    );
  });
}

const String _homeId = '01912345-6789-7abc-8def-0123456789ab';
const String _userId = '01912345-6789-7abc-8def-1123456789ab';
const String _consentReceiptId = '01912345-6789-7abc-8def-2123456789ab';
const String _proposalId = '01912345-6789-7abc-8def-3123456789ab';
const String _contributionId = '01912345-6789-7abc-8def-4123456789ab';
const String _productId = '01912345-6789-7abc-8def-5123456789ab';
const String _duplicateId = '01912345-6789-7abc-8def-6123456789ab';
const String _mergeId = '01912345-6789-7abc-8def-7123456789ab';
const String _iconId = '01912345-6789-7abc-8def-8123456789ab';

CatalogIconWrite _icon() => CatalogIconWrite(
  targetType: CatalogIconTargetType.product,
  targetId: _productId,
  assetDigest:
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  mediaType: 'image/png',
  altText: 'Rolled oats packet',
  width: 256,
  height: 256,
  byteSize: 1024,
  provenance: 'Commissioned public catalog asset',
  expectedRevision: 1,
);

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

Map<String, Object?> _requestObject(http.Request request) {
  final value = jsonDecode(request.body);
  if (value is! Map<String, Object?>) {
    throw StateError('Expected an object request.');
  }
  return value;
}

http.Response _json(Map<String, Object?> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: const <String, String>{'content-type': 'application/json'},
    );
