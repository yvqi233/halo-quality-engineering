import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';
import { validateQuarantine } from './validate-quarantine.mjs';

const NOW = new Date('2026-09-01T00:00:00Z');
const repositoryRoot = resolve(import.meta.dirname, '..');
const validatorPath = join(repositoryRoot, 'scripts/validate-quarantine.mjs');

const validCase = `cases:
  - testId: api.posts.lifecycle
    issueUrl: https://github.com/halo-dev/halo/issues/1234
    owner: quality-engineering
    reason: Intermittent upstream timeout under investigation
    expiresAt: 2026-09-15T00:00:00Z
    restoreAfterGreenRuns: 10
`;

test('accepts an empty quarantine and a complete unexpired case', () => {
  assert.deepEqual(validateQuarantine('cases: []\n', NOW), []);
  assert.deepEqual(validateQuarantine(validCase, NOW), []);
});

test('reports each required quarantine-field, public URL, expiry, and green-run violation', () => {
  const invalid = `cases:
  - testId:
    issueUrl: http://localhost/issues/1
    owner:
    reason:
    expiresAt: 2026-08-31T00:00:00Z
    restoreAfterGreenRuns: 9
`;

  assert.deepEqual(validateQuarantine(invalid, NOW), [
    'cases[0].testId is required',
    'cases[0].owner is required',
    'cases[0].reason is required',
    'cases[0].issueUrl must be a public HTTPS URL',
    'cases[0].expiresAt is expired',
    'cases[0].restoreAfterGreenRuns must be an integer between 10 and 20'
  ]);
});

test('rejects a non-ISO expiry even when the other future-entry fields are valid', () => {
  assert.deepEqual(validateQuarantine(validCase.replace('2026-09-15T00:00:00Z', '2026-09-15'), NOW), [
    'cases[0].expiresAt must be ISO-8601'
  ]);
});

test('CLI exits 2 for invalid future quarantine entries', () => {
  const directory = mkdtempSync(join(tmpdir(), 'halo-quarantine-'));
  const quarantinePath = join(directory, 'quarantine.yaml');
  writeFileSync(quarantinePath, validCase.replace('restoreAfterGreenRuns: 10', 'restoreAfterGreenRuns: 21'));
  try {
    const run = spawnSync(process.execPath, [validatorPath, '--file', quarantinePath, '--now', NOW.toISOString()], {
      cwd: repositoryRoot,
      encoding: 'utf8'
    });
    assert.equal(run.status, 2);
    assert.match(run.stderr, /restoreAfterGreenRuns/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
