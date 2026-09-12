import 'package:providentia/features/inventory/domain/stock_preference.dart';

abstract interface class StockPreferenceReader {
  Future<StockPreference> read({
    required String homeId,
    required String productId,
  });
}

abstract interface class StockPreferenceRepository {
  bool get supportsStockPreferences;
  Future<StockPreference> loadStockPreference({
    required String homeId,
    required String productId,
  });
  Future<void> saveStockPreference(StockPreference preference);
}

/// Only connectivity failures permit a previously verified offline policy.
final class StockPreferenceUnavailable implements Exception {
  const StockPreferenceUnavailable();
}
