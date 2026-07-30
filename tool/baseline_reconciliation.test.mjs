import assert from 'node:assert/strict';
import test from 'node:test';

import {
  authoritativeBaseline,
  reconcileBaseline,
} from './baseline_reconciliation.mjs';

test('authoritative project constants remain explicit', () => {
  assert.deepEqual(authoritativeBaseline, {
    itemMaster: 292,
    currentStock: 60,
    currentUnits: 159,
    legacyLowStock: 44,
    recentPurchases: 16,
    purchaseHistory: 452,
    monthlyPurchases: 261,
    aliasGroups: 13,
    aliases: 19,
    identityRules: 19,
    unresolvedCurrentStock: 8,
    historicalCanonicalKeys: 249,
    recentCanonicalKeysAddedInJuly: 12,
    recentGroups: 4,
    recentSpend: 1078.38,
  });
});

test('verified handover exports reconcile without exposing private rows', () => {
  const fixture = buildReconciledFixture();
  const result = reconcileBaseline(fixture);

  assert.equal(result.status, 'reconciled');
  assert.deepEqual(result.mismatches, []);
  assert.equal(
    result.aggregateChecks.historicalPurchaseRowsMatchMonthlyAprilToJune,
    true,
  );
  assert.equal(result.aggregateChecks.recentPurchaseRowsMatchMonthlyJuly, true);
  assert.equal('itemMaster' in result, false);
  assert.equal('purchases' in result, false);
});

test('a quantity difference fails closed with machine-readable evidence', () => {
  const fixture = buildReconciledFixture();
  fixture.pantryData.currentStock[0].quantity += 1;

  const result = reconcileBaseline(fixture);

  assert.equal(result.status, 'mismatch');
  assert.deepEqual(result.mismatches[0], {
    name: 'currentUnits',
    expected: 159,
    actual: 160,
  });
});

test('historical and monthly aggregates must agree by product and pack', () => {
  const fixture = buildReconciledFixture();
  fixture.pantryData.monthlyPurchases[0].quantities['2026-04'] += 1;

  const result = reconcileBaseline(fixture);

  assert.equal(result.status, 'mismatch');
  assert.ok(
    result.mismatches.some(({ name }) => name.startsWith('aggregate:')),
  );
});

function buildReconciledFixture() {
  const historicalKeys = Array.from(
    { length: authoritativeBaseline.historicalCanonicalKeys },
    (_, index) => [`Historical ${index}`, `${index + 1} g`],
  );
  const julyOnlyKeys = Array.from(
    { length: authoritativeBaseline.recentCanonicalKeysAddedInJuly },
    (_, index) => [`July ${index}`, `${index + 1} ml`],
  );

  const history = Array.from(
    { length: authoritativeBaseline.purchaseHistory },
    (_, index) => {
      const [canonicalItem, canonicalPackSize] =
        historicalKeys[index % historicalKeys.length];
      return { canonicalItem, canonicalPackSize, quantity: 1 };
    },
  );
  const historicalTotals = aggregateFixtureRows(history);

  const recentKeys = [...historicalKeys.slice(0, 4), ...julyOnlyKeys];
  const purchases = recentKeys.map(([canonicalItem, canonicalPackSize], index) => ({
    date: `2026-07-${String(10 + Math.floor(index / 4)).padStart(2, '0')}`,
    store: `Store ${Math.floor(index / 4)}`,
    canonicalItem,
    canonicalPackSize,
    quantity: index === recentKeys.length - 1 ? 21.46 : 1,
    totalCost: index === recentKeys.length - 1 ? 1078.23 : 0.01,
  }));
  const recentTotals = aggregateFixtureRows(purchases);

  const monthlyPurchases = [
    ...historicalKeys.map(([product, packSize]) => ({
      product,
      packSize,
      quantities: {
        '2026-04': historicalTotals.get(key(product, packSize)),
        '2026-05': 0,
        '2026-06': 0,
        '2026-07': recentTotals.get(key(product, packSize)) ?? 0,
      },
    })),
    ...julyOnlyKeys.map(([product, packSize]) => ({
      product,
      packSize,
      quantities: {
        '2026-04': 0,
        '2026-05': 0,
        '2026-06': 0,
        '2026-07': recentTotals.get(key(product, packSize)),
      },
    })),
  ];

  const currentStock = Array.from(
    { length: authoritativeBaseline.currentStock },
    (_, index) => ({
      quantity: index < authoritativeBaseline.legacyLowStock
        ? index === 0
          ? 2
          : 1
          : index < 59
          ? 5
          : 39,
    }),
  );

  const aliases = Object.fromEntries(
    Array.from({ length: authoritativeBaseline.aliasGroups }, (_, index) => [
      `Canonical ${index}`,
      Array.from(
        {
          length:
            index < authoritativeBaseline.aliases -
              authoritativeBaseline.aliasGroups
              ? 2
              : 1,
        },
        (__, aliasIndex) => `Alias ${index}-${aliasIndex}`,
      ),
    ]),
  );

  return {
    pantryData: {
      itemMaster: Array.from(
        { length: authoritativeBaseline.itemMaster },
        (_, id) => ({ id }),
      ),
      currentStock,
      purchases,
      history,
      monthlyPurchases,
    },
    productRules: {
      aliases,
      identityRules: Array.from(
        { length: authoritativeBaseline.identityRules },
        (_, id) => ({ id }),
      ),
      unresolvedCurrentStock: Array.from(
        { length: authoritativeBaseline.unresolvedCurrentStock },
        (_, id) => ({ id }),
      ),
    },
    metadata: {
      sourceCommit: 'b01b5ef14783b4ad1c1bfc0be7ba0dba32629af8',
      generatedAt: '2026-07-28',
      counts: {
        itemMaster: authoritativeBaseline.itemMaster,
        currentStock: authoritativeBaseline.currentStock,
        recentPurchases: authoritativeBaseline.recentPurchases,
        purchaseHistory: authoritativeBaseline.purchaseHistory,
        monthlyPurchases: authoritativeBaseline.monthlyPurchases,
        aliasGroups: authoritativeBaseline.aliasGroups,
        aliasDescriptions: authoritativeBaseline.aliases,
        identityRules: authoritativeBaseline.identityRules,
        unresolvedCurrentStock:
          authoritativeBaseline.unresolvedCurrentStock,
      },
    },
  };
}

function aggregateFixtureRows(rows) {
  const result = new Map();
  for (const row of rows) {
    const rowKey = key(row.canonicalItem, row.canonicalPackSize);
    result.set(rowKey, (result.get(rowKey) ?? 0) + row.quantity);
  }
  return result;
}

function key(product, packSize) {
  return `${product.toLowerCase()}\u0000${packSize.toLowerCase()}`;
}
