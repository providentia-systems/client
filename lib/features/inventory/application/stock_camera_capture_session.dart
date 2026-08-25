import 'dart:collection';

import 'package:providentia/features/ai_integration/domain/ai_models.dart';

enum StockCameraCaptureDecision { takeAnother, continueToReview, discard }

typedef StockCameraAssetCapture = Future<AiMediaAsset?> Function();
typedef StockCameraCaptureDecisionPicker =
    Future<StockCameraCaptureDecision> Function(List<AiMediaAsset> captured);
typedef StockCameraAssetDiscarder =
    Future<void> Function(List<AiMediaAsset> captured);

/// Collects a bounded sequence of camera observations before the ordinary
/// stock-photo controller takes ownership of preparation and consent.
/// Cancelling a later camera preserves earlier captures for review; explicit
/// discard removes every registered source.
Future<List<AiMediaAsset>> collectStockCameraAssets({
  required String homeId,
  required StockCameraAssetCapture capture,
  required StockCameraCaptureDecisionPicker chooseNext,
  required StockCameraAssetDiscarder discard,
  int maximumImages = 8,
}) async {
  if (homeId.trim().isEmpty || maximumImages < 1 || maximumImages > 8) {
    throw ArgumentError('A home and a 1–8 camera bound are required.');
  }
  final captured = <AiMediaAsset>[];
  while (captured.length < maximumImages) {
    final asset = await capture();
    if (asset == null) break;
    if (asset.homeId != homeId ||
        asset.purpose != AiExtractionKind.stockPhoto ||
        captured.any((existing) => existing.id == asset.id)) {
      await discard(<AiMediaAsset>[...captured, asset]);
      throw StateError('A camera capture crossed its stock workflow boundary.');
    }
    captured.add(asset);
    if (captured.length == maximumImages) break;
    final decision = await chooseNext(
      UnmodifiableListView<AiMediaAsset>(captured),
    );
    switch (decision) {
      case StockCameraCaptureDecision.takeAnother:
        continue;
      case StockCameraCaptureDecision.continueToReview:
        return List<AiMediaAsset>.unmodifiable(captured);
      case StockCameraCaptureDecision.discard:
        await discard(List<AiMediaAsset>.unmodifiable(captured));
        return const <AiMediaAsset>[];
    }
  }
  return List<AiMediaAsset>.unmodifiable(captured);
}
