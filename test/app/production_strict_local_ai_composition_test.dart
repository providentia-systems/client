import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/app/production_bootstrap_app.dart';
import 'package:providentia/features/ai_integration/application/ai_ports.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/ai_integration/domain/ai_policy.dart';
import 'package:providentia/features/inventory/application/stock_photo_count_controller.dart';

void main() {
  test(
    'production stock route prefers a verified strict-local profile',
    () async {
      var serverLoads = 0;
      final local = StockPhotoAiRoute(
        profile: _profile(strictLocal: true),
        gateway: const _ReadinessGateway(
          route: AiGatewayRoute.directStrictLocal,
          readinessResult: AiGatewayReadiness.ready(),
        ),
        privacyMode: AiPrivacyMode.strictLocal,
      );

      final selected = await selectProductionStockAiRoute(
        strictLocalProfileSelected: true,
        loadStrictLocalRoute: () async => local,
        loadServerRoute: () async {
          serverLoads++;
          return _serverRoute();
        },
      );

      expect(selected, same(local));
      expect(serverLoads, 0);
    },
  );

  test(
    'selected strict-local route fails closed when local is unready',
    () async {
      var serverLoads = 0;
      await expectLater(
        selectProductionStockAiRoute(
          strictLocalProfileSelected: true,
          loadStrictLocalRoute: () async => StockPhotoAiRoute(
            profile: _profile(strictLocal: true),
            gateway: const _ReadinessGateway(
              route: AiGatewayRoute.directStrictLocal,
              readinessResult: AiGatewayReadiness(
                state: AiGatewayReadinessState.unavailable,
                safeMessage: 'LAN peer unavailable.',
              ),
            ),
            privacyMode: AiPrivacyMode.strictLocal,
          ),
          loadServerRoute: () async {
            serverLoads++;
            return _serverRoute();
          },
        ),
        throwsA(
          isA<AiPolicyViolation>().having(
            (error) => error.safeMessage,
            'safeMessage',
            'LAN peer unavailable.',
          ),
        ),
      );

      expect(serverLoads, 0);
    },
  );

  test(
    'no local selection uses the server route without probing local',
    () async {
      var localLoads = 0;
      var serverLoads = 0;
      final server = _serverRoute();

      final selected = await selectProductionStockAiRoute(
        strictLocalProfileSelected: false,
        loadStrictLocalRoute: () async {
          localLoads++;
          throw StateError('must not load');
        },
        loadServerRoute: () async {
          serverLoads++;
          return server;
        },
      );

      expect(selected, same(server));
      expect(localLoads, 0);
      expect(serverLoads, 1);
    },
  );

  test(
    'misconfigured selected local profile never falls back to cloud',
    () async {
      var serverLoads = 0;

      await expectLater(
        selectProductionStockAiRoute(
          strictLocalProfileSelected: true,
          loadStrictLocalRoute: () async => throw const FormatException(
            'The selected local AI profile is unavailable.',
          ),
          loadServerRoute: () async {
            serverLoads++;
            return _serverRoute();
          },
        ),
        throwsFormatException,
      );
      expect(serverLoads, 0);
    },
  );

  test('production bootstrap exposes local settings and route cleanup', () {
    final source = File(
      'lib/app/production_bootstrap_app.dart',
    ).readAsStringSync();

    expect(source, contains('StrictLocalHomeAiComposition.create('));
    expect(source, contains('HomeAiHubPage('));
    expect(source, contains('loadStrictLocalRoute:'));
    expect(source, contains('loadRoute: loadPreferredRoute'));
    expect(source, contains('_strictLocalAi?.dispose()'));
  });
}

StockPhotoAiRoute _serverRoute() => StockPhotoAiRoute(
  profile: _profile(strictLocal: false),
  gateway: const _ReadinessGateway(
    route: AiGatewayRoute.serverProxyCloud,
    readinessResult: AiGatewayReadiness.ready(),
  ),
  privacyMode: AiPrivacyMode.serverProxyCloud,
);

AiProviderProfile _profile({required bool strictLocal}) => AiProviderProfile(
  id: strictLocal ? 'local-profile' : 'server-profile',
  homeId: 'home-a',
  displayName: strictLocal ? 'Kitchen Ollama' : 'Household AI',
  kind: strictLocal ? AiProviderKind.ollama : AiProviderKind.openAi,
  transport: strictLocal ? AiTransport.directNative : AiTransport.serverProxy,
  protocol: strictLocal
      ? AiEndpointProtocol.ollamaChat
      : AiEndpointProtocol.openAiResponses,
  endpoint: strictLocal ? Uri.parse('http://127.0.0.1:11434') : null,
  model: strictLocal ? 'llava:latest' : 'gpt-5-mini',
  capabilities: const <AiCapability>{
    AiCapability.vision,
    AiCapability.strictJsonSchema,
    AiCapability.multiImage,
  },
  availability: AiProviderAvailability.available,
  strictLocalAttestedAt: strictLocal ? DateTime.utc(2026, 8, 11) : null,
);

final class _ReadinessGateway implements AiProviderGateway {
  const _ReadinessGateway({required this.route, required this.readinessResult});

  @override
  final AiGatewayRoute route;

  final AiGatewayReadiness readinessResult;

  @override
  Future<AiGatewayReadiness> readiness(AiProviderProfile profile) async =>
      readinessResult;

  @override
  Future<AiExtractionResult<ReceiptProposal>> extractReceipt(
    AiExtractionRequest request,
  ) => throw UnsupportedError('not used');

  @override
  Future<AiExtractionResult<StockPhotoProposal>> extractStockPhoto(
    AiExtractionRequest request,
  ) => throw UnsupportedError('not used');
}
