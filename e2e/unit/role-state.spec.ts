import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { expect, test } from '@playwright/test';
import { canonicalStatePaths, loadCanonicalRoles, stateDestination } from '../fixtures/role-state';

test('only setup ownership can resolve canonical role paths', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'halo-qe-state-'));
  try {
    const paths = canonicalStatePaths(directory);
    expect(stateDestination('setup', paths, 'author')).toBe(paths.author);
    expect(stateDestination('test', paths, 'author')).toBeUndefined();
    await expect(Promise.all(
      Array.from({ length: 20 }, async () => stateDestination('test', paths, 'readonly'))
    )).resolves.toEqual(Array(20).fill(undefined));
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('loads setup-owned verified principals from the manifest and canonical states', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'halo-qe-manifest-'));
  try {
    const paths = canonicalStatePaths(directory);
    const emptyState = JSON.stringify({ cookies: [], origins: [] });
    await Promise.all([paths.admin, paths.author, paths.readonly].map(file => writeFile(file, emptyState)));
    await writeFile(paths.manifest, JSON.stringify({
      owner: 'setup',
      admin: 'qe-admin',
      author: 'qe-run-0-setup-author',
      readonly: 'qe-run-0-setup-readonly',
      createdUsers: ['qe-run-0-setup-author', 'qe-run-0-setup-readonly']
    }));

    const roles = await loadCanonicalRoles(directory);
    expect(roles.author.username).toBe('qe-run-0-setup-author');
    expect(roles.readonly.storageStatePath).toBe(paths.readonly);
    expect(roles.createdUsers).toEqual(['qe-run-0-setup-author', 'qe-run-0-setup-readonly']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
