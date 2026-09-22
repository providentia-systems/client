import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/inventory/infrastructure/generated_home_item_master_source.dart';
import 'package:providentia/features/inventory/infrastructure/generated_published_category_source.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

void main() {
  for (final count in [0, 1, 100, 101, 203]) {
    test(
      'loads all $count published categories independently of home stock',
      () async {
        final offsets = <int>[];
        final source = _source((request) async {
          expect(request.url.path, '/api/v1/catalog/categories');
          final offset = int.parse(request.url.queryParameters['offset']!);
          offsets.add(offset);
          final end = (offset + 100).clamp(0, count);
          return _page([
            for (var i = offset; i < end; i++) _category(i),
          ], offset);
        });
        final categories = await source.loadAll();
        expect(categories, hasLength(count));
        expect(offsets, [for (var i = 0; i <= count ~/ 100; i++) i * 100]);
        if (count > 0) expect(categories.last.name, 'Category ${count - 1}');
      },
    );
  }
  for (final invalid in <Map<String, Object?>>[
    {'id': 'not-a-uuid'},
    {'canonicalName': ''},
    {'revision': 0},
    {'revision': 1.5},
  ]) {
    test('rejects invalid published category $invalid', () async {
      final source = _source(
        (_) async => _page([
          {..._category(0), ...invalid},
        ], 0),
      );
      await expectLater(source.loadAll(), throwsFormatException);
    });
  }
  test(
    'rejects repeated IDs across pages instead of caching a truncated list',
    () async {
      final source = _source((request) async {
        final offset = int.parse(request.url.queryParameters['offset']!);
        return _page(
          offset == 0
              ? [for (var i = 0; i < 100; i++) _category(i)]
              : [_category(0)],
          offset,
        );
      });
      await expectLater(source.loadAll(), throwsFormatException);
    },
  );
  test('rejects a wrong page offset', () async {
    await expectLater(
      _source((_) async => _page([], 100)).loadAll(),
      throwsFormatException,
    );
  });
  for (final code in [401, 403, 404, 500]) {
    test('public category HTTP $code cannot revoke household access', () async {
      final source = _source((_) async => http.Response('{}', code));
      await expectLater(
        source.loadAll(),
        throwsA(
          isA<HomeItemMasterSourceException>().having(
            (error) => error.failure,
            'failure',
            HomeItemMasterSourceFailure.unavailable,
          ),
        ),
      );
    });
  }
}

GeneratedPublishedCategorySource _source(
  Future<http.Response> Function(http.Request) handler,
) => GeneratedPublishedCategorySource(
  ProvidentiaApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    httpClient: MockClient(handler),
  ),
);
http.Response _page(List<Object?> data, int offset) => http.Response(
  jsonEncode({
    'data': data,
    'pagination': {'limit': 100, 'offset': offset},
  }),
  200,
);
Map<String, Object?> _category(int index) => {
  'id': '10000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  'canonicalName': 'Category $index',
  'revision': 1,
};
