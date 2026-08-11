import 'package:providentia/features/purchasing/domain/purchase_models.dart';

final class PurchaseMatchRanker {
  const PurchaseMatchRanker();

  List<RankedPurchaseMatchCandidate> rank({
    required PurchaseReceiptLineCapture line,
    required Iterable<PurchaseMatchCandidate> candidates,
  }) {
    final raw = _normalizeMatchText(line.rawDescription);
    final originalPack = _normalizeMatchText(line.originalPackText ?? '');
    final ranked = <RankedPurchaseMatchCandidate>[];
    for (final candidate in candidates) {
      if (candidate.homeId != line.homeId) {
        throw StateError('Cross-home purchase matching is not permitted.');
      }
      final names = <String>{
        _normalizeMatchText(candidate.name),
        for (final alias in candidate.aliases) _normalizeMatchText(alias),
        if (candidate.brand.trim().isNotEmpty)
          _normalizeMatchText('${candidate.brand} ${candidate.name}'),
        if (candidate.brand.trim().isNotEmpty)
          _normalizeMatchText('${candidate.name} ${candidate.brand}'),
      }..remove('');
      final pack = _normalizeMatchText(candidate.packSize);
      final packAliases = <String>{
        pack,
        for (final alias in candidate.aliases) _normalizeMatchText(alias),
      }..remove('');
      final combined = <String>{
        for (final name in names) _normalizeMatchText('$name $pack'),
        for (final name in names) _normalizeMatchText('$pack $name'),
      };
      final descriptionExact = names.contains(raw);
      final packExact =
          originalPack.isNotEmpty && packAliases.contains(originalPack);
      late final PurchaseMatchBasis basis;
      late final int score;
      if (combined.contains(raw) || (descriptionExact && packExact)) {
        basis = PurchaseMatchBasis.exactDescriptionAndPack;
        score = 1000;
      } else if (descriptionExact) {
        basis = PurchaseMatchBasis.exactDescriptionOrAlias;
        score = 900;
      } else if (packExact) {
        basis = PurchaseMatchBasis.exactPack;
        score = 800;
      } else if (names.any(
        (name) => raw.contains(name) || name.contains(raw),
      )) {
        basis = PurchaseMatchBasis.partialDescription;
        score = 600;
      } else {
        final rawTokens = raw.split(' ').where((token) => token.length > 1);
        final metadata = _normalizeMatchText(
          <String>[
            candidate.name,
            candidate.brand,
            candidate.category,
            candidate.packSize,
            ...candidate.aliases,
          ].join(' '),
        );
        final overlap = rawTokens
            .where((token) => metadata.split(' ').contains(token))
            .toSet()
            .length;
        if (overlap > 0) {
          basis = PurchaseMatchBasis.metadataOverlap;
          score = 400 + overlap;
        } else {
          basis = PurchaseMatchBasis.itemMasterFallback;
          score = 0;
        }
      }
      final homeSelectionBias = switch (candidate.kind) {
        PurchaseMatchCandidateKind.selectedCatalogPack => 2,
        PurchaseMatchCandidateKind.privateHomeProduct => 1,
        PurchaseMatchCandidateKind.unselectedPublishedPack => 0,
      };
      ranked.add(
        RankedPurchaseMatchCandidate(
          candidate: candidate,
          basis: basis,
          score: score + homeSelectionBias,
        ),
      );
    }
    ranked.sort((left, right) {
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      final name = left.candidate.name.compareTo(right.candidate.name);
      if (name != 0) return name;
      final pack = left.candidate.packSize.compareTo(right.candidate.packSize);
      return pack != 0 ? pack : left.candidate.id.compareTo(right.candidate.id);
    });
    return List<RankedPurchaseMatchCandidate>.unmodifiable(ranked);
  }
}

String _normalizeMatchText(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

final class PurchaseHistoryGrouper {
  const PurchaseHistoryGrouper();

  List<PurchaseGroup> groupRecent({
    required String homeId,
    required Iterable<PurchaseLine> lines,
  }) {
    final groups = <String, List<PurchaseLine>>{};
    for (final line in lines) {
      _requireHome(homeId, line.homeId);
      if (line.source != PurchaseSource.recentReceipt) {
        continue;
      }
      final date = line.purchasedAt.toUtc();
      final dateKey =
          '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final key = line.receiptId?.trim().isNotEmpty == true
          ? 'receipt:${line.receiptId}'
          : 'legacy:$dateKey:${line.storeName}';
      groups.putIfAbsent(key, () => <PurchaseLine>[]).add(line);
    }
    final result =
        groups.entries
            .map((entry) {
              final first = entry.value.first;
              return PurchaseGroup(
                id: entry.key,
                purchasedAt: first.purchasedAt,
                storeName: first.storeName,
                lines: entry.value,
                inferred: entry.key.startsWith('legacy:'),
              );
            })
            .toList(growable: false)
          ..sort((left, right) {
            final date = right.purchasedAt.compareTo(left.purchasedAt);
            return date != 0 ? date : left.id.compareTo(right.id);
          });
    return List<PurchaseGroup>.unmodifiable(result);
  }

  List<MonthlyPurchaseSummary> summarizeHistory({
    required String homeId,
    required Iterable<PurchaseLine> lines,
  }) {
    final totals = <String, (DateTime, int, double)>{};
    for (final line in lines) {
      _requireHome(homeId, line.homeId);
      if (line.source != PurchaseSource.historicalImport) {
        continue;
      }
      final date = line.purchasedAt.toUtc();
      final month = DateTime.utc(date.year, date.month);
      final key = '${month.year}-${month.month}';
      final current = totals[key] ?? (month, 0, 0.0);
      totals[key] = (month, current.$2 + 1, current.$3 + line.quantity);
    }
    final summaries =
        totals.values
            .map(
              (value) => MonthlyPurchaseSummary(
                month: value.$1,
                lineCount: value.$2,
                quantity: value.$3,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.month.compareTo(left.month));
    return List<MonthlyPurchaseSummary>.unmodifiable(summaries);
  }

  Money? recentSpend({
    required String homeId,
    required Iterable<PurchaseLine> lines,
  }) {
    final priced = <Money>[];
    for (final line in lines) {
      _requireHome(homeId, line.homeId);
      if (line.source == PurchaseSource.recentReceipt &&
          line.lineTotal != null) {
        priced.add(line.lineTotal!);
      }
    }
    if (priced.isEmpty) return null;
    return priced.reduce((left, right) => left + right);
  }

  void _requireHome(String expected, String actual) {
    if (expected != actual) {
      throw StateError('Cross-home purchase data is not permitted.');
    }
  }
}

final class PrivateHomePriceComparison {
  const PrivateHomePriceComparison();

  PriceStatistics summarize({
    required String homeId,
    required String productPackId,
    required Iterable<PriceObservation> observations,
  }) {
    final matching = observations
        .where((observation) {
          if (observation.homeId != homeId) {
            throw StateError('Cross-home price data is not permitted.');
          }
          return observation.productPackId == productPackId;
        })
        .toList(growable: false);
    if (matching.isEmpty) {
      throw StateError('At least one matching price observation is required.');
    }
    final currency = matching.first.total.currency;
    if (matching.any((entry) => entry.total.currency != currency)) {
      throw StateError('Price statistics require one currency.');
    }
    final sortedByPrice = matching.toList()
      ..sort((left, right) {
        final price = left.minorUnitsPerBaseUnit.compareTo(
          right.minorUnitsPerBaseUnit,
        );
        return price != 0 ? price : left.id.compareTo(right.id);
      });
    final latest = matching.toList()
      ..sort((left, right) {
        final date = right.observedAt.compareTo(left.observedAt);
        return date != 0 ? date : left.id.compareTo(right.id);
      });
    return PriceStatistics(
      homeId: homeId,
      productPackId: productPackId,
      currency: currency,
      observationCount: matching.length,
      averageMinorUnitsPerBaseUnit:
          matching
              .map((entry) => entry.minorUnitsPerBaseUnit)
              .reduce((left, right) => left + right) /
          matching.length,
      lowest: sortedByPrice.first,
      highest: sortedByPrice.last,
      latest: latest.first,
    );
  }

  List<PriceObservation> rankCurrentOffers({
    required String homeId,
    required String productPackId,
    required Iterable<PriceObservation> observations,
  }) {
    final matching =
        observations
            .where((observation) {
              if (observation.homeId != homeId) {
                throw StateError('Cross-home price data is not permitted.');
              }
              return observation.productPackId == productPackId;
            })
            .toList(growable: false)
          ..sort((left, right) {
            final price = left.minorUnitsPerBaseUnit.compareTo(
              right.minorUnitsPerBaseUnit,
            );
            if (price != 0) return price;
            final date = right.observedAt.compareTo(left.observedAt);
            return date != 0 ? date : left.id.compareTo(right.id);
          });
    return List<PriceObservation>.unmodifiable(matching);
  }
}
