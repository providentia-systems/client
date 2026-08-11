import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

const String _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const String _productOne = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';
const String _productTwo = '0198a0b1-c2d3-7e4f-a345-6789abcdef01';
const String _packOne = '0198a0b1-c2d3-7e4f-b456-789abcdef012';
const String _packTwo = '0198a0b1-c2d3-7e4f-9567-89abcdef0123';
const String _homeProduct = '0198a0b1-c2d3-7e4f-a678-9abcdef01234';

void main() {
  test(
    'loads every stable item-master page without losing pack identity',
    () async {
      final offsets = <int>[];
      final source = GeneratedHomeItemMasterSource(
        _client((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          return offset == 0
              ? _page(
                  data: <Object?>[
                    _item(
                      productId: _productOne,
                      packId: _packOne,
                      homeProductId: _homeProduct,
                      quantity: '3.5',
                    ),
                  ],
                  offset: 0,
                  total: 2,
                  hasMore: true,
                  nextOffset: 1,
                )
              : _page(
                  data: <Object?>[
                    _item(
                      productId: _productTwo,
                      packId: _packTwo,
                      homeProductId: null,
                      quantity: '0',
                    ),
                  ],
                  offset: 1,
                  total: 2,
                  hasMore: false,
                  nextOffset: null,
                );
        }),
      );

      final items = await source.loadAll(homeId: _homeId);

      expect(offsets, <int>[0, 1]);
      expect(items, hasLength(2));
      expect(items.first.id, _homeProduct);
      expect(items.first.productId, _productOne);
      expect(items.first.packId, _packOne);
      expect(items.first.currentQuantity, 3.5);
      expect(items.first.isHomeProduct, isTrue);
      expect(items.last.id, _packTwo);
      expect(items.last.currentQuantity, isNull);
      expect(items.last.isHomeProduct, isFalse);
      expect(items.last.aliases, <String>['Long grain']);
    },
  );

  test('rejects an overlapping or truncated item-master feed', () async {
    final source = GeneratedHomeItemMasterSource(
      _client(
        (_) async => _page(
          data: <Object?>[
            _item(
              productId: _productOne,
              packId: _packOne,
              homeProductId: null,
              quantity: '0',
            ),
          ],
          offset: 0,
          total: 2,
          hasMore: false,
          nextOffset: null,
        ),
      ),
    );

    await expectLater(
      source.loadAll(homeId: _homeId),
      throwsA(isA<FormatException>()),
    );
  });

  for (final statusCode in <int>[403, 404]) {
    test(
      'maps HTTP $statusCode to authorization denied at the adapter boundary',
      () async {
        final source = GeneratedHomeItemMasterSource(
          _client(
            (_) async => http.Response(
              jsonEncode(<String, Object?>{
                'type': 'about:blank',
                'title': statusCode == 403 ? 'Forbidden' : 'Not Found',
                'status': statusCode,
                'requestId': 'request-1',
              }),
              statusCode,
              headers: <String, String>{
                'content-type': 'application/problem+json',
              },
            ),
          ),
        );

        await expectLater(
          source.loadAll(homeId: _homeId),
          throwsA(
            isA<HomeItemMasterSourceException>().having(
              (error) => error.failure,
              'failure',
              HomeItemMasterSourceFailure.authorizationDenied,
            ),
          ),
        );
      },
    );
  }

  test(
    'loads the 292-pack baseline across pages with 60 active rows and 159 units',
    () async {
      final records = List<Map<String, Object?>>.generate(292, (index) {
        final active = index < 60;
        final quantity = active ? (index < 39 ? 3 : 2) : 0;
        return _item(
          productId: _fixtureUuid('8', index),
          packId: _fixtureUuid('9', index),
          homeProductId: active ? _fixtureUuid('a', index) : null,
          quantity: '$quantity',
        );
      });
      final requestedOffsets = <int>[];
      final source = GeneratedHomeItemMasterSource(
        _client((request) async {
          final offset = int.parse(request.url.queryParameters['offset']!);
          final limit = int.parse(request.url.queryParameters['limit']!);
          requestedOffsets.add(offset);
          final end = (offset + limit).clamp(0, records.length);
          final data = records.sublist(offset, end);
          final hasMore = end < records.length;
          return _page(
            data: data,
            offset: offset,
            total: records.length,
            hasMore: hasMore,
            nextOffset: hasMore ? end : null,
          );
        }),
      );

      final items = await source.loadAll(homeId: _homeId);

      expect(requestedOffsets, <int>[0, 100, 200]);
      expect(items, hasLength(292));
      final active = items.where((item) => item.isHomeProduct).toList();
      expect(active, hasLength(60));
      expect(
        active.fold<double>(
          0,
          (quantity, item) => quantity + item.currentQuantity!,
        ),
        159,
      );
      expect(items.map((item) => item.packId).toSet(), hasLength(292));
    },
  );
}

ProvidentiaApiClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => ProvidentiaApiClient(
  baseUri: Uri.parse('https://api.example.test'),
  httpClient: MockClient(handler),
);

http.Response _page({
  required List<Object?> data,
  required int offset,
  required int total,
  required bool hasMore,
  required int? nextOffset,
}) => http.Response(
  jsonEncode(<String, Object?>{
    'data': data,
    'pagination': <String, Object?>{
      'limit': 100,
      'offset': offset,
      'returned': data.length,
      'total': total,
      'hasMore': hasMore,
      'nextOffset': nextOffset,
    },
  }),
  200,
);

Map<String, Object?> _item({
  required String productId,
  required String packId,
  required String? homeProductId,
  required String quantity,
}) => <String, Object?>{
  'productId': productId,
  'packId': packId,
  'canonicalName': 'Rice',
  'brand': 'Harvest',
  'categoryId': '0198a0b1-c2d3-7e4f-8789-abcdef012345',
  'categoryName': 'Grains',
  'packText': '1 kg',
  'packStatus': 'published',
  'aliases': <Object?>['Long grain'],
  'homeProductId': homeProductId,
  'homeProductStatus': homeProductId == null ? null : 'active',
  'quantity': quantity,
};

String _fixtureUuid(String family, int index) =>
    '0198a0b1-c2d3-7e4f-$family${index.toRadixString(16).padLeft(3, '0')}-'
    '${index.toRadixString(16).padLeft(12, '0')}';
