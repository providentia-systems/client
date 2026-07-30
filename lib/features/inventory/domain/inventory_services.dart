import 'package:providentia/features/inventory/domain/inventory_models.dart';

final class InventoryItemSearch {
  const InventoryItemSearch();

  List<InventoryItem> filter(
    Iterable<InventoryItem> items,
    InventorySearchCriteria criteria,
  ) {
    final query = _normalize(criteria.query);
    final category = criteria.category?.trim();
    final filtered = items
        .where((item) {
          if (criteria.view == InventoryView.counted && !item.isCounted) {
            return false;
          }
          if (category != null &&
              category.isNotEmpty &&
              category != 'All' &&
              item.category != category) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return <String>[
            item.canonicalName,
            item.brand,
            item.packSize,
            item.category,
            ...item.aliases,
          ].any((value) => _normalize(value).contains(query));
        })
        .toList(growable: false);

    filtered.sort((left, right) {
      final leftConfirmed = criteria.confirmedItemIds.contains(left.id);
      final rightConfirmed = criteria.confirmedItemIds.contains(right.id);
      if (leftConfirmed != rightConfirmed) {
        return leftConfirmed ? 1 : -1;
      }
      final name = left.canonicalName.compareTo(right.canonicalName);
      return name != 0 ? name : left.packSize.compareTo(right.packSize);
    });
    return List<InventoryItem>.unmodifiable(filtered);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'''[\s\-–—_/().,&'"]+'''), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

final class InventoryBalanceProjector {
  const InventoryBalanceProjector();

  List<InventoryBalance> project({
    required String homeId,
    required Iterable<StockMovement> movements,
    DateTime? asOf,
  }) {
    if (homeId.trim().isEmpty) {
      throw ArgumentError.value(homeId, 'homeId', 'must not be empty');
    }
    final effectiveAt = (asOf ?? DateTime.now()).toUtc();
    final ordered = movements.toList(growable: false)
      ..sort((left, right) {
        final time = left.occurredAt.compareTo(right.occurredAt);
        return time != 0 ? time : left.id.compareTo(right.id);
      });
    final totals = <String, double>{};
    final identities = <String, (String, String)>{};
    for (final movement in ordered) {
      if (movement.homeId != homeId) {
        throw StateError('Cross-home movement supplied to balance projector.');
      }
      if (movement.occurredAt.toUtc().isAfter(effectiveAt)) {
        continue;
      }
      final key = '${movement.itemId}\u0000${movement.locationId}';
      totals[key] = (totals[key] ?? 0.0) + movement.quantityDelta;
      identities[key] = (movement.itemId, movement.locationId);
    }
    final balances =
        totals.entries
            .map((entry) {
              final identity = identities[entry.key]!;
              return InventoryBalance(
                homeId: homeId,
                itemId: identity.$1,
                locationId: identity.$2,
                quantity: _normalizeZero(entry.value),
                asOf: effectiveAt,
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            final item = left.itemId.compareTo(right.itemId);
            return item != 0
                ? item
                : left.locationId.compareTo(right.locationId);
          });
    return List<InventoryBalance>.unmodifiable(balances);
  }

  double _normalizeZero(double value) => value.abs() < 1e-9 ? 0 : value;
}
