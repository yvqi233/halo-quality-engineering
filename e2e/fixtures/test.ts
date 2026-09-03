import { randomUUID } from 'node:crypto';
import { test as base, type Page, type TestInfo } from '@playwright/test';
import { formatCleanupFailures } from './cleanup';
import { HaloApi } from './halo-api';
import { createAuthenticatedRoles, type AuthenticatedRoles } from './role-auth';
import { loadCanonicalRoles, type CanonicalRoles } from './role-state';

interface Fixtures {
  roles: AuthenticatedRoles;
  canonicalRoles: CanonicalRoles;
  haloApi: HaloApi;
  adminPage: Page;
  authorPage: Page;
  readonlyPage: Page;
  canonicalAuthorPage: Page;
  canonicalReadonlyPage: Page;
}

const runId = (process.env.QE_RUN_ID ?? `${Date.now()}-${randomUUID().slice(0, 8)}`)
  .toLowerCase()
  .replace(/[^a-z0-9-]/g, '-');

export const test = base.extend<Fixtures>({
  roles: async ({ browser, baseURL }, use, testInfo) => {
    if (!baseURL) throw new Error('HALO baseURL is required');
    const scenarioId = testInfo.title.match(/E\d{2}/)?.[0]?.toLowerCase() ?? 'scenario';
    const prefix = `qe-${runId}-${testInfo.workerIndex}-${scenarioId}`;
    const roles = await createAuthenticatedRoles(browser, baseURL, prefix);
    try {
      await use(roles);
    } finally {
      reportCleanup(formatCleanupFailures(await roles.cleanup()), testInfo);
    }
  },

  canonicalRoles: async ({}, use) => {
    await use(await loadCanonicalRoles());
  },

  haloApi: async ({ roles }, use, testInfo) => {
    const scenarioId = testInfo.title.match(/E\d{2}/)?.[0]?.toLowerCase() ?? 'scenario';
    const prefix = `qe-${runId}-${testInfo.workerIndex}-${scenarioId}`;
    const api = new HaloApi(roles.adminContext.request, prefix);
    try {
      await use(api);
    } finally {
      const failures = await api.cleanup();
      reportCleanup(
        failures.map(failure => `delete post ${failure.resourceName}: ${failure.message}`),
        testInfo
      );
    }
  },

  adminPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.admin.storageState });
    try {
      await use(await context.newPage());
    } finally {
      await context.close();
    }
  },

  authorPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.author.storageState });
    try {
      await use(await context.newPage());
    } finally {
      await context.close();
    }
  },

  readonlyPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.readonly.storageState });
    try {
      await use(await context.newPage());
    } finally {
      await context.close();
    }
  },

  canonicalAuthorPage: async ({ browser, canonicalRoles }, use) => {
    const context = await browser.newContext({ storageState: canonicalRoles.author.storageStatePath });
    try {
      await use(await context.newPage());
    } finally {
      await context.close();
    }
  },

  canonicalReadonlyPage: async ({ browser, canonicalRoles }, use) => {
    const context = await browser.newContext({ storageState: canonicalRoles.readonly.storageStatePath });
    try {
      await use(await context.newPage());
    } finally {
      await context.close();
    }
  }
});

function reportCleanup(failures: string[], testInfo: TestInfo): void {
  if (failures.length === 0) return;
  testInfo.annotations.push({ type: 'cleanup', description: failures.join('; ') });
  if (testInfo.status === testInfo.expectedStatus) throw new Error(`cleanup failed: ${failures.join('; ')}`);
}

export { expect } from '@playwright/test';
