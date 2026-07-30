#!/usr/bin/env node

import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

export const authoritativeBaseline = Object.freeze({
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

export function reconcileBaseline({ pantryData, productRules, metadata }) {
  assertRecord(pantryData, 'pantry-data.json');
  assertRecord(productRules, 'product-rules.json');
  assertRecord(metadata, 'export_metadata.json');

  const itemMaster = requiredArray(pantryData.itemMaster, 'itemMaster');
  const currentStock = requiredArray(pantryData.currentStock, 'currentStock');
  const recentPurchases = requiredArray(pantryData.purchases, 'purchases');
  const purchaseHistory = requiredArray(pantryData.history, 'history');
  const monthlyPurchases = requiredArray(
    pantryData.monthlyPurchases,
    'monthlyPurchases',
  );
  const identityRules = requiredArray(
    productRules.identityRules,
    'identityRules',
  );
  const unresolved = requiredArray(
    productRules.unresolvedCurrentStock,
    'unresolvedCurrentStock',
  );
  assertRecord(productRules.aliases, 'aliases');

  const aliasGroups = Object.entries(productRules.aliases);
  const aliases = aliasGroups.flatMap(([canonical, values]) => {
    if (!Array.isArray(values)) {
      throw new TypeError(`aliases.${canonical} must be an array`);
    }
    return values;
  });

  const currentUnits = sum(
    currentStock.map((row, index) =>
      requiredFiniteNumber(row.quantity, `currentStock[${index}].quantity`),
    ),
  );
  const legacyLowStock = currentStock.filter(
    (row) => requiredFiniteNumber(row.quantity, 'currentStock.quantity') <= 2,
  ).length;
  const recentSpend = roundMoney(
    sum(
      recentPurchases.map((row, index) =>
        requiredFiniteNumber(
          row.totalCost,
          `purchases[${index}].totalCost`,
        ),
      ),
    ),
  );
  const recentGroups = new Set(
    recentPurchases.map(
      (row, index) =>
        `${requiredText(row.date, `purchases[${index}].date`)}\u0000` +
        requiredText(row.store, `purchases[${index}].store`),
    ),
  ).size;

  const historicalQuantities = aggregateByCanonicalKey(purchaseHistory);
  const monthlyHistoricalQuantities = aggregateMonthlyHistory(monthlyPurchases);
  const monthlyJulyQuantities = aggregateMonthlyJuly(monthlyPurchases);
  const recentQuantities = aggregateByCanonicalKey(recentPurchases);
  const historicalComparison = compareAggregates(
    historicalQuantities,
    monthlyHistoricalQuantities,
  );
  const julyComparison = compareAggregates(
    recentQuantities,
    monthlyJulyQuantities,
  );
  const recentCanonicalKeysAddedInJuly = [...recentQuantities.keys()].filter(
    (key) => !historicalQuantities.has(key),
  ).length;

  const actual = {
    itemMaster: itemMaster.length,
    currentStock: currentStock.length,
    currentUnits,
    legacyLowStock,
    recentPurchases: recentPurchases.length,
    purchaseHistory: purchaseHistory.length,
    monthlyPurchases: monthlyPurchases.length,
    aliasGroups: aliasGroups.length,
    aliases: aliases.length,
    identityRules: identityRules.length,
    unresolvedCurrentStock: unresolved.length,
    historicalCanonicalKeys: historicalQuantities.size,
    recentCanonicalKeysAddedInJuly,
    recentGroups,
    recentSpend,
  };

  const mismatches = [];
  for (const [name, expected] of Object.entries(authoritativeBaseline)) {
    if (actual[name] !== expected) {
      mismatches.push({ name, expected, actual: actual[name] });
    }
  }
  mismatches.push(...historicalComparison, ...julyComparison);

  const declaredCounts = metadata.counts;
  assertRecord(declaredCounts, 'export_metadata.counts');
  for (const [declaredName, actualName] of Object.entries({
    itemMaster: 'itemMaster',
    currentStock: 'currentStock',
    recentPurchases: 'recentPurchases',
    purchaseHistory: 'purchaseHistory',
    monthlyPurchases: 'monthlyPurchases',
    aliasGroups: 'aliasGroups',
    aliasDescriptions: 'aliases',
    identityRules: 'identityRules',
    unresolvedCurrentStock: 'unresolvedCurrentStock',
  })) {
    if (declaredCounts[declaredName] !== actual[actualName]) {
      mismatches.push({
        name: `metadata.counts.${declaredName}`,
        expected: actual[actualName],
        actual: declaredCounts[declaredName],
      });
    }
  }

  return {
    status: mismatches.length === 0 ? 'reconciled' : 'mismatch',
    sourceCommit: metadata.sourceCommit ?? null,
    generatedAt: metadata.generatedAt ?? null,
    counts: actual,
    aggregateChecks: {
      historicalPurchaseRowsMatchMonthlyAprilToJune:
        historicalComparison.length === 0,
      recentPurchaseRowsMatchMonthlyJuly: julyComparison.length === 0,
    },
    mismatches,
  };
}

export async function reconcileExportDirectory(exportDirectory) {
  const [pantryData, productRules, metadata] = await Promise.all([
    readJson(path.join(exportDirectory, 'pantry-data.json')),
    readJson(path.join(exportDirectory, 'product-rules.json')),
    readJson(path.join(exportDirectory, 'export_metadata.json')),
  ]);
  return reconcileBaseline({ pantryData, productRules, metadata });
}

function aggregateByCanonicalKey(rows) {
  const aggregate = new Map();
  for (const [index, row] of rows.entries()) {
    const product = firstNonEmptyText(
      row.canonicalItem,
      row.product,
      row.fullName,
    );
    const packSize = firstNonEmptyText(
      row.canonicalPackSize,
      row.packSize,
      row.size,
    );
    const key = canonicalKey(
      requiredText(product, `rows[${index}].product identity`),
      requiredText(packSize, `rows[${index}].pack identity`),
    );
    const quantity = requiredFiniteNumber(
      row.quantity,
      `rows[${index}].quantity`,
    );
    aggregate.set(key, roundQuantity((aggregate.get(key) ?? 0) + quantity));
  }
  return aggregate;
}

function aggregateMonthlyHistory(rows) {
  const aggregate = new Map();
  for (const [index, row] of rows.entries()) {
    const key = canonicalKey(
      requiredText(row.product, `monthlyPurchases[${index}].product`),
      requiredText(row.packSize, `monthlyPurchases[${index}].packSize`),
    );
    assertRecord(
      row.quantities,
      `monthlyPurchases[${index}].quantities`,
    );
    const quantity = ['2026-04', '2026-05', '2026-06'].reduce(
      (total, month) =>
        total +
        requiredFiniteNumber(
          row.quantities[month],
          `monthlyPurchases[${index}].quantities.${month}`,
        ),
      0,
    );
    if (quantity !== 0) {
      aggregate.set(key, roundQuantity(quantity));
    }
  }
  return aggregate;
}

function aggregateMonthlyJuly(rows) {
  const aggregate = new Map();
  for (const [index, row] of rows.entries()) {
    const key = canonicalKey(
      requiredText(row.product, `monthlyPurchases[${index}].product`),
      requiredText(row.packSize, `monthlyPurchases[${index}].packSize`),
    );
    assertRecord(
      row.quantities,
      `monthlyPurchases[${index}].quantities`,
    );
    const quantity = requiredFiniteNumber(
      row.quantities['2026-07'],
      `monthlyPurchases[${index}].quantities.2026-07`,
    );
    if (quantity !== 0) {
      aggregate.set(key, roundQuantity(quantity));
    }
  }
  return aggregate;
}

function compareAggregates(left, right) {
  const mismatches = [];
  const keys = new Set([...left.keys(), ...right.keys()]);
  for (const key of keys) {
    const expected = left.get(key) ?? 0;
    const actual = right.get(key) ?? 0;
    if (Math.abs(expected - actual) > 1e-9) {
      mismatches.push({
        name: `aggregate:${key}`,
        expected,
        actual,
      });
    }
  }
  return mismatches;
}

function canonicalKey(product, packSize) {
  return `${product.trim().toLocaleLowerCase('en')}\u0000` +
    packSize.trim().toLocaleLowerCase('en');
}

function requiredArray(value, name) {
  if (!Array.isArray(value)) {
    throw new TypeError(`${name} must be an array`);
  }
  return value;
}

function assertRecord(value, name) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} must be an object`);
  }
}

function requiredText(value, name) {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new TypeError(`${name} must be a non-empty string`);
  }
  return value;
}

function firstNonEmptyText(...values) {
  return values.find(
    (value) => typeof value === 'string' && value.trim() !== '',
  );
}

function requiredFiniteNumber(value, name) {
  if (typeof value !== 'number' || !Number.isFinite(value)) {
    throw new TypeError(`${name} must be a finite number`);
  }
  return value;
}

function sum(values) {
  return values.reduce((total, value) => total + value, 0);
}

function roundMoney(value) {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function roundQuantity(value) {
  return Math.round((value + Number.EPSILON) * 1_000_000) / 1_000_000;
}

async function readJson(file) {
  return JSON.parse(await readFile(file, 'utf8'));
}

async function main() {
  const exportDirectory = process.argv[2];
  if (!exportDirectory) {
    throw new Error(
      'Usage: node tool/baseline_reconciliation.mjs <03_data_exports>',
    );
  }
  const result = await reconcileExportDirectory(path.resolve(exportDirectory));
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (result.status !== 'reconciled') {
    process.exitCode = 1;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
