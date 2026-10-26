import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:providentia/features/purchasing/application/purchase_receipt_history.dart';
import 'package:providentia/features/purchasing/infrastructure/generated_purchase_receipt_history_reader.dart';
import 'package:providentia_api_client/providentia_api_client.dart';

const _home = '10000000-0000-4000-8000-000000000001';
const _receipt = '10000000-0000-4000-8000-000000000002';
const _audit = '10000000-0000-4000-8000-000000000003';
const _actor = '10000000-0000-4000-8000-000000000004';
const _line = '10000000-0000-4000-8000-000000000005';
const _other = '10000000-0000-4000-8000-000000000006';

void main() {
  Map<String, Object?> receipt({String home = _home}) => {
    'id': _receipt,
    'homeId': home,
    'purchaseDate': '2026-10-01',
    'currency': 'NAD',
    'status': 'committed',
    'source': 'manual',
    'revision': 4,
    'createdAt': '2026-10-02 08:00:00.000000',
  };
  http.Response json(Map<String, Object?> value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json'},
  );
  Map<String, Object?> lineAudit() => {
    'id': _audit,
    'receiptId': _receipt,
    'lineId': _line,
    'reason': 'Resolve omitted purchase',
    'receiptRevision': 5,
    'actorUserId': _actor,
    'correctedAt': '2026-10-03T12:00:00Z',
    'originalLine': {
      'id': _line,
      'receiptId': _receipt,
      'homeId': _home,
      'rawDescription': 'Original line',
    },
    'nextLine': {
      'id': _line,
      'receiptId': _receipt,
      'homeId': _home,
      'rawDescription': 'Resolved line',
    },
  };
  GeneratedPurchaseReceiptHistoryReader fixtureReader({
    required List<Map<String, Object?>> lines,
    List<Map<String, Object?>> dates = const [],
    String envelope = 'data',
    Map<String, Object?> extraEnvelope = const {},
  }) => GeneratedPurchaseReceiptHistoryReader(
    ProvidentiaApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/date-corrections')) {
          return json({envelope: dates, ...extraEnvelope});
        }
        if (request.url.path.endsWith('/line-corrections')) {
          return json({envelope: lines, ...extraEnvelope});
        }
        return json(receipt());
      }),
    ),
  );

  for (final envelope in ['data', 'corrections']) {
    for (final omitted in [false, true]) {
      test(
        '$envelope history preserves validated ${omitted ? 'omitted' : 'unresolved'} line identity',
        () async {
          final audit = lineAudit();
          if (omitted) audit['originalLine'] = null;
          final history = await fixtureReader(
            lines: [audit],
            envelope: envelope,
          ).load(homeId: _home, receiptId: _receipt);
          expect(history.entries.single.id, _audit);
          expect(history.entries.single.lineDescription, 'Resolved line');
        },
      );
    }
  }

  final invalidLineAudit = <(String, void Function(Map<String, Object?>))>[
    ('non UUID audit ID', (audit) => audit['id'] = 'not-an-audit-id'),
    ('missing audit ID', (audit) => audit.remove('id')),
    ('non UUID line ID', (audit) => audit['lineId'] = 'not-a-line-id'),
    ('missing outer line ID', (audit) => audit.remove('lineId')),
    ('missing resulting line', (audit) => audit.remove('nextLine')),
    ('malformed resulting line', (audit) => audit['nextLine'] = 'foreign line'),
    (
      'malformed original line',
      (audit) => audit['originalLine'] = 'foreign line',
    ),
    for (final field in ['originalLine', 'nextLine']) ...[
      (
        '$field foreign receipt',
        (audit) => (audit[field] as Map<String, Object?>)['receiptId'] = _other,
      ),
      (
        '$field foreign home',
        (audit) => (audit[field] as Map<String, Object?>)['homeId'] = _other,
      ),
      (
        '$field different line ID',
        (audit) => (audit[field] as Map<String, Object?>)['id'] = _other,
      ),
      (
        '$field conflicting lineId alias',
        (audit) => (audit[field] as Map<String, Object?>)['lineId'] = _other,
      ),
      (
        '$field missing receipt ID',
        (audit) => (audit[field] as Map<String, Object?>).remove('receiptId'),
      ),
      (
        '$field missing line ID',
        (audit) => (audit[field] as Map<String, Object?>).remove('id'),
      ),
    ],
  ];
  for (final (name, mutate) in invalidLineAudit) {
    test('rejects $name without returning a partial history', () async {
      final audit = lineAudit();
      mutate(audit);
      await expectLater(
        fixtureReader(lines: [audit]).load(homeId: _home, receiptId: _receipt),
        throwsA(
          isA<PurchaseReceiptHistoryException>().having(
            (error) => error.safeMessage,
            'safeMessage',
            contains('Saved history is retained'),
          ),
        ),
      );
    });
  }
  test('duplicate audit IDs inside one collection are rejected', () async {
    await expectLater(
      fixtureReader(
        lines: [lineAudit(), lineAudit()],
      ).load(homeId: _home, receiptId: _receipt),
      throwsA(isA<PurchaseReceiptHistoryException>()),
    );
  });
  test(
    'duplicate audit IDs across date and line collections are rejected',
    () async {
      await expectLater(
        fixtureReader(
          lines: [lineAudit()],
          dates: [
            {
              'id': _audit,
              'receiptId': _receipt,
              'originalPurchaseDate': '2026-10-02',
              'purchaseDate': '2026-10-01',
              'reason': 'Correct day',
              'correctedAt': '2026-10-03T12:00:00Z',
            },
          ],
        ).load(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
    },
  );
  for (final extra in <String, Map<String, Object?>>{
    'foreign home envelope': {'homeId': _other},
    'foreign receipt envelope': {'receiptId': _other},
    'ambiguous canonical and legacy envelope': {'corrections': []},
  }.entries) {
    test('rejects ${extra.key}', () async {
      await expectLater(
        fixtureReader(
          lines: [lineAudit()],
          extraEnvelope: extra.value,
        ).load(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
    });
  }

  test(
    'real generated reads preserve backend UTC creation timestamp and audited calendar days',
    () async {
      final paths = <String>[];
      final reader = GeneratedPurchaseReceiptHistoryReader(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path.endsWith('/date-corrections')) {
              return json({
                'corrections': [
                  {
                    'id': _audit,
                    'receiptId': _receipt,
                    'originalPurchaseDate': '2026-10-02',
                    'purchaseDate': '2026-10-01',
                    'reason': 'Receipt was entered the following day',
                    'receiptRevision': 4,
                    'actorUserId': _actor,
                    'correctedAt': '2026-10-03T12:00:00Z',
                  },
                ],
              });
            }
            if (request.url.path.endsWith('/line-corrections')) {
              return json({'corrections': []});
            }
            return json(receipt());
          }),
        ),
      );
      final result = await reader.load(homeId: _home, receiptId: _receipt);
      expect(result.createdAt, DateTime.utc(2026, 10, 2, 8));
      expect(result.entries.single.originalPurchaseDay, '2026-10-02');
      expect(result.entries.single.purchaseDay, '2026-10-01');
      expect(
        result.entries.single.reason,
        'Receipt was entered the following day',
      );
      expect(
        paths,
        containsAll([
          '/api/v1/homes/$_home/receipts/$_receipt',
          '/api/v1/homes/$_home/receipts/$_receipt/date-corrections',
          '/api/v1/homes/$_home/receipts/$_receipt/line-corrections',
        ]),
      );
    },
  );
  test(
    'foreign receipt metadata is rejected before any history can be cached',
    () async {
      final reader = GeneratedPurchaseReceiptHistoryReader(
        ProvidentiaApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          httpClient: MockClient(
            (request) async => request.url.path.endsWith('corrections')
                ? json({'corrections': []})
                : json(receipt(home: _actor)),
          ),
        ),
      );
      await expectLater(
        reader.load(homeId: _home, receiptId: _receipt),
        throwsA(isA<PurchaseReceiptHistoryException>()),
      );
    },
  );
  for (final status in [401, 403, 404]) {
    test(
      'history denial $status explains access without exposing server detail',
      () async {
        final reader = GeneratedPurchaseReceiptHistoryReader(
          ProvidentiaApiClient(
            baseUri: Uri.parse('https://api.example.test'),
            httpClient: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'type': 'about:blank',
                  'title': 'Not available',
                  'status': status,
                  'detail': 'sensitive synthetic detail',
                }),
                status,
                headers: {'content-type': 'application/problem+json'},
              ),
            ),
          ),
        );
        await expectLater(
          reader.load(homeId: _home, receiptId: _receipt),
          throwsA(
            isA<PurchaseReceiptHistoryException>().having(
              (error) => error.safeMessage,
              'safe error',
              isNot(contains('sensitive synthetic detail')),
            ),
          ),
        );
      },
    );
  }
}
