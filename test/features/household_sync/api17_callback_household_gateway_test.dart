import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/household_sync/application/household_api17_ports.dart';
import 'package:providentia/features/household_sync/infrastructure/api17_callback_household_gateway.dart';
import 'package:providentia/features/identity/application/identity_ports.dart';
import 'package:providentia/features/identity/domain/identity_models.dart';

void main() {
  test('stock reads authorize and parse the API 1.7 envelope', () async {
    Map<String, String>? capturedHeaders;
    final gateway = Api17CallbackHouseholdGateway(
      authorizer: _Authorizer(),
      listHomeStock: ({required homeId, required headers}) async {
        capturedHeaders = headers;
        return Api17RawResponse(
          statusCode: 200,
          body: <String, Object?>{
            'data': <Object?>[_stockJson()],
          },
        );
      },
      createStockAdjustment: _unusedAdjustment,
    );

    final records = await gateway.listHomeStock('home-1');

    expect(records.single.quantity, 2.25);
    expect(capturedHeaders?['Authorization'], 'Bearer access-token');
  });

  test('home-level adjustment sends idempotency and decimal values', () async {
    Map<String, Object?>? capturedBody;
    Map<String, String>? capturedHeaders;
    final gateway = Api17CallbackHouseholdGateway(
      authorizer: _Authorizer(),
      listHomeStock: _unusedList,
      createStockAdjustment:
          ({required homeId, required body, required headers}) async {
            capturedBody = body;
            capturedHeaders = headers;
            return Api17RawResponse(
              statusCode: 201,
              body: <String, Object?>{
                'id': 'movement-1',
                'homeId': homeId,
                'homeProductId': body['homeProductId'],
                'quantityDelta': body['quantityDelta'],
                'sourceId': body['operationId'],
                'occurredAt': '2026-08-04T12:00:00Z',
              },
            );
          },
    );

    final receipt = await gateway.createHomeLevelStockAdjustment(
      Api17HomeLevelStockAdjustment(
        operationId: 'operation-1',
        homeId: 'home-1',
        homeProductId: 'home-product-1',
        quantityDelta: 1.5,
        reason: 'Count correction',
      ),
    );

    expect(capturedHeaders?['Idempotency-Key'], 'operation-1');
    expect(capturedBody?['quantityDelta'], '1.5');
    expect(receipt.quantityDelta, 1.5);
  });

  test('request is not attempted after session recovery fails', () async {
    var called = false;
    final gateway = Api17CallbackHouseholdGateway(
      authorizer: _Authorizer(fresh: false),
      listHomeStock: ({required homeId, required headers}) async {
        called = true;
        return const Api17RawResponse(
          statusCode: 200,
          body: <String, Object?>{},
        );
      },
      createStockAdjustment: _unusedAdjustment,
    );

    await expectLater(
      gateway.listHomeStock('home-1'),
      throwsA(
        isA<HouseholdApiException>().having(
          (error) => error.kind,
          'kind',
          HouseholdApiFailureKind.authentication,
        ),
      ),
    );
    expect(called, isFalse);
  });
}

Map<String, Object?> _stockJson() => <String, Object?>{
  'id': 'home-product-1',
  'homeId': 'home-1',
  'productId': 'product-1',
  'packId': 'pack-1',
  'productName': 'Rice',
  'originalPackText': '1 kg',
  'categoryId': 'category-1',
  'quantity': '2.25',
  'revision': 1,
};

Future<Api17RawResponse> _unusedList({
  required String homeId,
  required Map<String, String> headers,
}) {
  throw UnimplementedError();
}

Future<Api17RawResponse> _unusedAdjustment({
  required String homeId,
  required Map<String, Object?> body,
  required Map<String, String> headers,
}) {
  throw UnimplementedError();
}

final class _Authorizer implements SessionAuthorizer {
  _Authorizer({this.fresh = true});

  final bool fresh;

  @override
  String? get accessToken => 'access-token';

  @override
  String? get csrfToken => null;

  @override
  Future<bool> ensureFresh() async => fresh;

  @override
  ClientSessionTransport get sessionTransport =>
      ClientSessionTransport.nativeBearer;
}
