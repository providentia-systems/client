import assert from 'node:assert/strict';
import test from 'node:test';

import {
  assertCoverage,
  summarizeLcov,
} from './check_coverage.mjs';

const handwrittenAndGenerated = `
SF:lib/core/service.dart
LF:10
LH:8
end_of_record
SF:lib/core/database/app_database.g.dart
LF:100
LH:0
end_of_record
`;

test('summarizes handwritten code and excludes generated Dart', () => {
  assert.deepEqual(summarizeLcov(handwrittenAndGenerated), {
    found: 10,
    hit: 8,
    percentage: 80,
  });
});

test('accepts coverage at the configured floor', () => {
  assert.doesNotThrow(() => {
    assertCoverage(summarizeLcov(handwrittenAndGenerated), 80);
  });
});

test('rejects coverage below the configured floor', () => {
  assert.throws(
    () => assertCoverage(summarizeLcov(handwrittenAndGenerated), 80.01),
    /below 80\.01%/u,
  );
});

test('rejects empty and invalid coverage input', () => {
  assert.throws(
    () => summarizeLcov('SF:lib/empty.dart\nLF:0\nLH:0\n'),
    /no measurable/u,
  );
  assert.throws(
    () => summarizeLcov('SF:lib/broken.dart\nLF:two\nLH:1\n'),
    /Invalid LF/u,
  );
  assert.throws(
    () => assertCoverage({found: 1, hit: 1, percentage: 100}, 101),
    /from 0 through 100/u,
  );
});
