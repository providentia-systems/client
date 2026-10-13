import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/synchronization/receipt_projection_validation.dart';
import 'package:providentia/core/synchronization/sync_models.dart';

void main() {
  RemoteChange line(Map<String, Object?> fields) => RemoteChange(
    cursor: 'line-cursor',
    homeId: 'home-1',
    entityType: 'purchasing-receipt-line',
    entityId: 'line-1',
    kind: RemoteChangeKind.upsert,
    revision: 1,
    serverTimestamp: DateTime.utc(2026, 10, 13),
    payload: <String, Object?>{
      'receiptId': 'receipt-1',
      'rawDescription': 'Apples',
      'quantity': '4',
      'homeProductId': 'product-1',
      'approvalStatus': 'approved',
      ...fields,
    },
  );

  test(
    'applied packs and reversed removed lines retain precise stock decimals',
    () {
      validateReceiptProjection(
        line(<String, Object?>{
          'packId': 'pack-1',
          'stockQuantity': '4.000',
          'stockQuantityPerPack': '1.000',
        }),
      );
      validateReceiptProjection(
        line(<String, Object?>{
          'approvalStatus': 'removed',
          'stockQuantity': '0',
          'stockQuantityPerPack': '1',
        }),
      );
    },
  );

  for (final fields in <Map<String, Object?>>[
    <String, Object?>{'stockQuantity': 4},
    <String, Object?>{'stockQuantity': '-4'},
    <String, Object?>{'stockQuantity': 'NaN'},
    <String, Object?>{'stockQuantity': '4', 'stockQuantityPerPack': '0'},
    <String, Object?>{'stockQuantityPerPack': '1'},
    <String, Object?>{'stockQuantity': '4', 'homeProductId': null},
    <String, Object?>{'stockQuantity': '4', 'approvalStatus': 'unreviewed'},
    <String, Object?>{'stockQuantity': '4', 'packId': 1},
  ]) {
    test('malformed applied-line readback is rejected: $fields', () {
      expect(
        () => validateReceiptProjection(line(fields)),
        throwsFormatException,
      );
    });
  }
}
