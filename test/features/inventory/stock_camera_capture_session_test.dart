import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/features/ai_integration/domain/ai_models.dart';
import 'package:providentia/features/inventory/application/stock_camera_capture_session.dart';

void main() {
  test('one capture can continue directly to review', () async {
    final result = await collectStockCameraAssets(
      homeId: 'home-1',
      capture: () async => _asset(1),
      chooseNext: (_) async => StockCameraCaptureDecision.continueToReview,
      discard: (_) async {},
    );

    expect(result.map((asset) => asset.id), <String>['capture-1']);
  });

  test('eight captures are accepted and a ninth is never requested', () async {
    var attempts = 0;
    final result = await collectStockCameraAssets(
      homeId: 'home-1',
      capture: () async => _asset(++attempts),
      chooseNext: (_) async => StockCameraCaptureDecision.takeAnother,
      discard: (_) async {},
    );

    expect(result, hasLength(8));
    expect(attempts, 8);
  });

  test('cancelling a later camera preserves earlier captures', () async {
    var attempts = 0;
    final result = await collectStockCameraAssets(
      homeId: 'home-1',
      capture: () async {
        attempts++;
        return attempts == 1 ? _asset(1) : null;
      },
      chooseNext: (_) async => StockCameraCaptureDecision.takeAnother,
      discard: (_) async {},
    );

    expect(result.map((asset) => asset.id), <String>['capture-1']);
  });

  test('explicit discard clears every selected capture', () async {
    List<AiMediaAsset>? discarded;
    final result = await collectStockCameraAssets(
      homeId: 'home-1',
      capture: () async => _asset(1),
      chooseNext: (_) async => StockCameraCaptureDecision.discard,
      discard: (assets) async => discarded = assets,
    );

    expect(result, isEmpty);
    expect(discarded?.map((asset) => asset.id), <String>['capture-1']);
  });
}

AiMediaAsset _asset(int index) => AiMediaAsset(
  id: 'capture-$index',
  homeId: 'home-1',
  localReference: 'registered://capture-$index.jpg',
  purpose: AiExtractionKind.stockPhoto,
  mimeType: 'image/jpeg',
  byteLength: 32,
  createdAt: DateTime.utc(2026, 8, 25),
);
