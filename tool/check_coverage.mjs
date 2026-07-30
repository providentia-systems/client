#!/usr/bin/env node

import {readFile} from 'node:fs/promises';
import {pathToFileURL} from 'node:url';
import path from 'node:path';

export const defaultMinimumCoverage = 80;

export function summarizeLcov(source) {
  let currentFile;
  let found = 0;
  let hit = 0;

  for (const line of source.split(/\r?\n/u)) {
    if (line.startsWith('SF:')) {
      currentFile = line.slice(3).replaceAll('\\', '/');
      continue;
    }
    if (currentFile === undefined || isExcluded(currentFile)) {
      continue;
    }
    if (line.startsWith('LF:')) {
      found += parseCounter(line, 'LF');
    } else if (line.startsWith('LH:')) {
      hit += parseCounter(line, 'LH');
    }
  }

  if (found === 0) {
    throw new Error('LCOV contains no measurable handwritten production lines.');
  }
  if (hit > found) {
    throw new Error(`LCOV hit count ${hit} exceeds line count ${found}.`);
  }

  return Object.freeze({
    found,
    hit,
    percentage: (hit / found) * 100,
  });
}

export function assertCoverage(summary, minimum = defaultMinimumCoverage) {
  if (!Number.isFinite(minimum) || minimum < 0 || minimum > 100) {
    throw new RangeError('Coverage minimum must be a number from 0 through 100.');
  }
  if (summary.percentage + Number.EPSILON < minimum) {
    throw new Error(
      `Handwritten production coverage ${format(summary.percentage)}% ` +
        `(${summary.hit}/${summary.found}) is below ${format(minimum)}%.`,
    );
  }
}

function isExcluded(file) {
  return (
    file.endsWith('.g.dart') ||
    file.includes('/contracts/generated/') ||
    file.startsWith('contracts/generated/')
  );
}

function parseCounter(line, label) {
  const value = Number.parseInt(line.slice(label.length + 1), 10);
  if (!Number.isSafeInteger(value) || value < 0) {
    throw new Error(`Invalid ${label} counter: ${line}`);
  }
  return value;
}

function format(value) {
  return value.toFixed(2).replace(/\.00$/u, '');
}

async function main() {
  const input = process.argv[2] ?? 'coverage/lcov.info';
  const minimum = process.argv[3] === undefined
    ? defaultMinimumCoverage
    : Number(process.argv[3]);
  const summary = summarizeLcov(await readFile(input, 'utf8'));
  assertCoverage(summary, minimum);
  process.stdout.write(
    `Handwritten production coverage: ${format(summary.percentage)}% ` +
      `(${summary.hit}/${summary.found}); minimum ${format(minimum)}%.\n`,
  );
}

const invokedPath = process.argv[1] === undefined
  ? undefined
  : pathToFileURL(path.resolve(process.argv[1])).href;
if (invokedPath === import.meta.url) {
  await main();
}
