import { randomUUID } from 'node:crypto';
import { mkdir, rename, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { expect, test } from '@playwright/test';
import { attachCleanupFailures, formatCleanupFailures } from './cleanup';
import { createAuthenticatedRoles } from './role-auth';
import { authDirectory, canonicalStatePaths, type SetupManifest } from './role-state';

test('I01 setup owns and verifies canonical role states', async ({ browser, baseURL }) => {
  if (!baseURL) throw new Error('HALO baseURL is required');
  const directory = authDirectory();
  const paths = canonicalStatePaths(directory);
  const runId = `${Date.now()}-${randomUUID().slice(0, 8)}`.toLowerCase();
  const roles = await createAuthenticatedRoles(browser, baseURL, `qe-${runId}-0-setup`, {
    owner: 'setup',
    canonicalPaths: paths
  });

  try {
    const manifest: SetupManifest = {
      owner: 'setup',
      admin: roles.admin.username,
      author: roles.author.username,
      readonly: roles.readonly.username,
      createdUsers: roles.createdUsers
    };
    await mkdir(directory, { recursive: true });
    const temporary = `${paths.manifest}.writing-${process.pid}`;
    await writeFile(temporary, JSON.stringify(manifest, null, 2));
    await rename(temporary, paths.manifest);

    const failures = await roles.closeContexts();
    expect(formatCleanupFailures(failures)).toEqual([]);
  } catch (error) {
    const failures = await roles.cleanup();
    throw attachCleanupFailures(error, failures);
  }
});
