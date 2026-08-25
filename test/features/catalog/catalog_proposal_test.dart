import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/catalog/application/catalog_proposal_service.dart';
import 'package:providentia/features/catalog/domain/catalog_models.dart';
import 'package:providentia/features/catalog/presentation/catalog_proposal_panel.dart';

void main() {
  group('sanitized proposal privacy', () {
    test('wire representation is an exact catalog-only allowlist', () {
      final product = _privateProduct();
      final service = CatalogProposalService(_ProposalRepository());
      final proposal = service.preview(product: product, locale: 'en-NA');
      final json = proposal.toJson();

      expect(json.keys.toSet(), <String>{
        'canonicalName',
        'locale',
        'brand',
        'variant',
        'packText',
        'packAmount',
        'unitCode',
        'categoryId',
        'barcode',
      });
      expect(
        json.keys.toSet().difference(
          SanitizedCatalogProposal.allowedWireFields,
        ),
        isEmpty,
      );
      for (final forbidden in <String>[
        'homeId',
        'homeProductId',
        'privateNote',
        'price',
        'quantity',
        'receiptNumber',
        'store',
        'media',
        'aiMetadata',
      ]) {
        expect(json, isNot(contains(forbidden)));
      }
      expect(product.privateNote, 'Keep in the pantry');
    });

    test('pack amount and unit must be supplied together', () {
      expect(
        () => SanitizedCatalogProposal(
          canonicalName: 'Rice',
          locale: 'en-NA',
          packAmount: 5,
        ),
        throwsArgumentError,
      );
      expect(
        () => PrivateProduct(
          homeId: 'home-1',
          homeProductId: 'private-1',
          displayName: 'Rice',
          packAmount: 0,
        ),
        throwsArgumentError,
      );
    });

    test('submission requires explicit consent and preserves private link', () {
      final repository = _ProposalRepository();
      final service = CatalogProposalService(repository);
      final product = _privateProduct();
      final proposal = service.preview(product: product, locale: 'en-NA');

      expect(
        () => service.submit(
          submissionId: _submissionId,
          product: product,
          preview: proposal,
          explicitlyConsented: false,
        ),
        throwsA(isA<CatalogProposalConsentRequiredException>()),
      );
      expect(repository.submissionCount, 0);

      return expectLater(
        service
            .submit(
              submissionId: _submissionId,
              product: product,
              preview: proposal,
              explicitlyConsented: true,
            )
            .then((link) {
              expect(link.homeId, 'home-1');
              expect(link.homeProductId, 'private-1');
              expect(link.proposalId, 'proposal-1');
              expect(link.status, CatalogProposalStatus.pending);
              expect(repository.submissionCount, 1);
            }),
        completes,
      );
    });
  });

  testWidgets('proposal panel shows exact transmission preview and opt-in', (
    tester,
  ) async {
    final proposal = CatalogProposalService(
      _ProposalRepository(),
    ).preview(product: _privateProduct(), locale: 'en-NA');
    var submissions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogProposalPanel(
            proposal: proposal,
            consented: false,
            onConsentChanged: (_) {},
            onSubmit: () {
              submissions++;
            },
          ),
        ),
      ),
    );

    expect(find.text('Sanitized catalog proposal'), findsOneWidget);
    expect(find.textContaining('Household identity'), findsOneWidget);
    expect(find.textContaining('privateNote'), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogProposalPanel(
            proposal: proposal,
            consented: true,
            onConsentChanged: (_) {},
            onSubmit: () {
              submissions++;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Submit proposal'));
    expect(submissions, 1);
  });
}

PrivateProduct _privateProduct() {
  return PrivateProduct(
    homeId: 'home-1',
    homeProductId: 'private-1',
    displayName: 'Rice Basmati',
    brand: ' Himalaya Queen ',
    variant: 'Basmati',
    packText: '5 kg bag',
    packAmount: 5,
    unitCode: 'kg',
    categoryId: 'rice',
    barcode: '6001234567890',
    privateNote: 'Keep in the pantry',
  );
}

final class _ProposalRepository implements CatalogProposalRepository {
  int submissionCount = 0;

  @override
  Future<CatalogSubmissionLink> submit({
    required String submissionId,
    required String homeId,
    required String homeProductId,
    required SanitizedCatalogProposal proposal,
  }) async {
    submissionCount++;
    expect(submissionId, _submissionId);
    expect(proposal.toJson(), isNot(contains('homeId')));
    return CatalogSubmissionLink(
      homeId: homeId,
      homeProductId: homeProductId,
      proposalId: 'proposal-1',
      status: CatalogProposalStatus.pending,
    );
  }
}

const String _submissionId = '01912345-6789-4abc-8def-0123456789ab';
