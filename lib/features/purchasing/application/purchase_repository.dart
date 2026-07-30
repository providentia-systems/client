import 'package:providentia/features/purchasing/domain/purchase_models.dart';

abstract interface class PurchaseRepository {
  Stream<List<PurchaseLine>> watchPurchaseLines({required String homeId});

  Stream<List<PriceObservation>> watchPriceObservations({
    required String homeId,
    String? productPackId,
  });
}
