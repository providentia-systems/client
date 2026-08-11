import 'dart:collection';

import 'package:providentia/features/inventory/domain/inventory_models.dart';
import 'package:providentia_api_client/providentia_api_client.dart'
    as generated;

abstract interface class HomeItemMasterSource {
  Future<List<InventoryItem>> loadAll({required String homeId});
}

enum HomeItemMasterSourceFailure {
  authenticationRequired,
  authorizationDenied,
  unavailable,
}

final class HomeItemMasterSourceException implements Exception {
  const HomeItemMasterSourceException(this.failure);

  final HomeItemMasterSourceFailure failure;
}

/// Reads the complete backend-owned item master for one authorized home.
///
/// The source validates every pagination field before returning a snapshot so
/// callers never cache a truncated, overlapping, or cross-contract result.
final class GeneratedHomeItemMasterSource implements HomeItemMasterSource {
  const GeneratedHomeItemMasterSource(this._client);

  final generated.ProvidentiaApiClient _client;

  @override
  Future<List<InventoryItem>> loadAll({required String homeId}) async {
    if (!_uuid.hasMatch(homeId)) {
      throw const FormatException(
        'The item-master home identifier is invalid.',
      );
    }
    const limit = 100;
    final items = <InventoryItem>[];
    final packIds = <String>{};
    var offset = 0;
    int? total;
    var pages = 0;
    while (true) {
      pages++;
      if (pages > 1000) {
        throw const FormatException('The item master returned too many pages.');
      }
      late final generated.ApiResponse response;
      try {
        response = await _client.listHomeProducts(
          homeId: homeId,
          query: <String, String>{'limit': '$limit', 'offset': '$offset'},
        );
      } on generated.ProvidentiaApiException catch (error) {
        throw HomeItemMasterSourceException(switch (error.statusCode) {
          401 => HomeItemMasterSourceFailure.authenticationRequired,
          403 || 404 => HomeItemMasterSourceFailure.authorizationDenied,
          _ => HomeItemMasterSourceFailure.unavailable,
        });
      }
      final body = response.requireObject();
      final data = _objectList(body, 'data');
      final pagination = _object(body['pagination'], 'item-master pagination');
      final responseLimit = _integer(pagination, 'limit');
      final responseOffset = _integer(pagination, 'offset');
      final returned = _integer(pagination, 'returned');
      final responseTotal = _integer(pagination, 'total');
      final hasMore = _boolean(pagination, 'hasMore');
      final nextOffset = _nullableInteger(pagination, 'nextOffset');
      final expectedTotal = total ?? responseTotal;
      if (responseLimit != limit ||
          responseOffset != offset ||
          returned != data.length ||
          responseTotal < data.length ||
          expectedTotal != responseTotal) {
        throw const FormatException(
          'The item-master page envelope is invalid.',
        );
      }
      total = expectedTotal;
      for (final record in data) {
        final item = _item(record, homeId);
        final packId = item.packId!;
        if (!packIds.add(packId)) {
          throw const FormatException(
            'The item master returned the same pack more than once.',
          );
        }
        items.add(item);
      }
      if (!hasMore) {
        if (nextOffset != null || items.length != expectedTotal) {
          throw const FormatException(
            'The item master ended before its declared total.',
          );
        }
        return UnmodifiableListView<InventoryItem>(items);
      }
      if (nextOffset == null ||
          nextOffset <= offset ||
          nextOffset != offset + returned ||
          nextOffset >= expectedTotal) {
        throw const FormatException(
          'The item-master continuation did not advance safely.',
        );
      }
      offset = nextOffset;
    }
  }
}

InventoryItem _item(Map<String, Object?> record, String homeId) {
  final productId = _identifier(record, 'productId');
  final packId = _identifier(record, 'packId');
  _identifier(record, 'categoryId');
  final homeProductId = _nullableIdentifier(record, 'homeProductId');
  final homeProductStatus = record['homeProductStatus'];
  if ((homeProductId == null && homeProductStatus != null) ||
      (homeProductId != null && homeProductStatus != 'active')) {
    throw const FormatException(
      'The item-master home-product state is invalid.',
    );
  }
  final packStatus = _string(record, 'packStatus');
  if (packStatus != 'published' && packStatus != 'pending-normalization') {
    throw const FormatException('The item-master pack status is invalid.');
  }
  final quantity = double.tryParse(_string(record, 'quantity'));
  if (quantity == null || !quantity.isFinite) {
    throw const FormatException('The item-master quantity is invalid.');
  }
  final packText = _string(record, 'packText').trim();
  return InventoryItem(
    id: homeProductId ?? packId,
    homeId: homeId,
    productId: productId,
    packId: packId,
    canonicalName: _string(record, 'canonicalName'),
    packSize: packText.isEmpty ? 'Unspecified pack' : packText,
    category: _string(record, 'categoryName'),
    brand: _string(record, 'brand'),
    aliases: _stringList(record, 'aliases'),
    currentQuantity: homeProductId == null ? null : quantity,
    isHomeProduct: homeProductId != null,
  );
}

List<Map<String, Object?>> _objectList(
  Map<String, Object?> object,
  String key,
) {
  final value = object[key];
  if (value is! List<Object?>) {
    throw FormatException('Expected "$key" to be a list.');
  }
  return value.map((entry) => _object(entry, key)).toList(growable: false);
}

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw FormatException('Expected $label to be an object.');
  }
  return value;
}

String _string(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! String) {
    throw FormatException('Expected "$key" to be a string.');
  }
  return value;
}

String _identifier(Map<String, Object?> object, String key) {
  final value = _string(object, key);
  if (!_uuid.hasMatch(value)) {
    throw FormatException('Expected "$key" to be a UUID.');
  }
  return value;
}

String? _nullableIdentifier(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! String || !_uuid.hasMatch(value)) {
    throw FormatException('Expected "$key" to be a UUID or null.');
  }
  return value;
}

int _integer(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! int || value < 0) {
    throw FormatException('Expected "$key" to be a non-negative integer.');
  }
  return value;
}

int? _nullableInteger(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FormatException('Expected "$key" to be an integer or null.');
  }
  return value;
}

bool _boolean(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! bool) {
    throw FormatException('Expected "$key" to be a boolean.');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> object, String key) {
  final value = object[key];
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw FormatException('Expected "$key" to be a string list.');
  }
  final values = value.cast<String>();
  if (values.toSet().length != values.length) {
    throw FormatException('Expected "$key" to contain unique values.');
  }
  return List<String>.unmodifiable(values);
}

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
