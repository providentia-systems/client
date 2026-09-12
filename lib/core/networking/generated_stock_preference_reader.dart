import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:providentia/features/inventory/application/stock_preference_repository.dart';
import 'package:providentia/features/inventory/domain/stock_preference.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

final class GeneratedStockPreferenceReader implements StockPreferenceReader {
  const GeneratedStockPreferenceReader(this._client);
  final ProvidentiaApiClient _client;

  @override
  Future<StockPreference> read({
    required String homeId,
    required String productId,
  }) async {
    try {
      final fields = (await _client.getStockPreference(
        homeId: homeId,
        homeProductId: productId,
      )).requireObject();
      if (fields['homeProductId'] != productId) {
        throw const FormatException('Unexpected stock preference identity.');
      }
      return StockPreference.fromFields(
        homeId: homeId,
        homeProductId: productId,
        revision: fields['revision']! as int,
        fields: fields,
      );
    } on ProvidentiaApiException catch (error) {
      if (error.statusCode >= 500 || error.statusCode == 429) {
        throw const StockPreferenceUnavailable();
      }
      rethrow;
    } on TimeoutException {
      throw const StockPreferenceUnavailable();
    } on http.ClientException {
      throw const StockPreferenceUnavailable();
    }
  }
}
