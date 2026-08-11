import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/database/app_database.dart';
import 'package:providentia/features/shopping/application/online_shopping_suggestion_repository.dart';
import 'package:providentia/features/shopping/domain/online_shopping_suggestion_models.dart';
import 'package:providentia/features/shopping/infrastructure/drift_shopping_suggestion_cache.dart';

void main() {
  late AppDatabase database;
  late DriftShoppingSuggestionCache cache;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = DriftShoppingSuggestionCache(database);
  });

  tearDown(() => database.close());

  test(
    'round-trips exact verified values and stays home partitioned',
    () async {
      await cache.replace(
        VerifiedShoppingSuggestionSnapshot(
          homeId: _homeId,
          verifiedAt: DateTime.utc(2026, 8, 11, 12),
          suggestions: <OnlineShoppingSuggestion>[_suggestion()],
        ),
      );

      final restored = await cache.read(homeId: _homeId);
      expect(restored!.verifiedAt, DateTime.utc(2026, 8, 11, 12));
      expect(restored.suggestions.single.requiredQuantity.value, '3.12500001');
      expect(restored.suggestions.single.homeId, _homeId);
      expect(await cache.read(homeId: _otherHomeId), isNull);
    },
  );

  test('corrupt or cross-home cache is purged instead of displayed', () async {
    await database
        .into(database.localRecords)
        .insert(
          LocalRecordsCompanion.insert(
            homeId: _homeId,
            entityType: DriftShoppingSuggestionCache.entityType,
            entityId: 'verified-feed',
            payload: '{"homeId":"$_otherHomeId","suggestions":[]}',
            updatedAt: DateTime.utc(2026, 8, 11),
          ),
        );

    expect(await cache.read(homeId: _homeId), isNull);
    expect(
      await (database.select(database.localRecords)..where(
            (row) =>
                row.entityType.equals(DriftShoppingSuggestionCache.entityType),
          ))
          .get(),
      isEmpty,
    );
  });
}

const _homeId = '0198a0b1-c2d3-7e4f-8123-456789abcdef';
const _otherHomeId = '0198a0b1-c2d3-7e4f-9234-56789abcdef0';

OnlineShoppingSuggestion _suggestion() => OnlineShoppingSuggestion(
  id: '0198a0b1-c2d3-7e4f-a345-6789abcdef01',
  homeId: _homeId,
  homeProductId: '0198a0b1-c2d3-7e4f-b456-789abcdef012',
  productName: 'Oats',
  packText: '1 kg',
  expectedDemand: ExactDecimal('4.12500001'),
  safetyStock: ExactDecimal('1'),
  factualStock: ExactDecimal('2'),
  usableStock: ExactDecimal('2'),
  requiredQuantity: ExactDecimal('3.12500001'),
  selectedPackId: '0198a0b1-c2d3-7e4f-9567-89abcdef0123',
  packCount: 4,
  confidenceScore: ExactDecimal('0.25'),
  confidenceBand: ShoppingSuggestionConfidenceBand.low,
  status: OnlineShoppingSuggestionStatus.active,
  expiresAt: DateTime.utc(2026, 8, 12),
  modelVersion: 'suggestion-v1',
  asOf: DateTime.utc(2026, 8, 11, 12),
  inputWatermark:
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
);
