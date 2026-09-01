import { expect, test } from '@playwright/test';
import { formatCleanupFailures } from './cleanup';
import { cleanupNamedUsers } from './role-auth';
import { loadCanonicalRoles } from './role-state';

test('I02 teardown deletes setup users in reverse order', async ({ browser, baseURL }) => {
  if (!baseURL) throw new Error('HALO baseURL is required');
  const roles = await loadCanonicalRoles();
  const failures = await cleanupNamedUsers(browser, baseURL, roles.createdUsers);
  expect(formatCleanupFailures(failures)).toEqual([]);
});
