import { randomUUID } from 'node:crypto';
import { test as base, type Page, type TestInfo } from '@playwright/test';
import { createAuthenticatedRoles, type AuthenticatedRoles } from './role-auth';
import { HaloApi } from './halo-api';

interface Fixtures {
  roles: AuthenticatedRoles;
  haloApi: HaloApi;
  adminPage: Page;
  authorPage: Page;
  readonlyPage: Page;
}

const runId = (process.env.QE_RUN_ID ?? `${Date.now()}-${randomUUID().slice(0, 8)}`)
  .toLowerCase()
  .replace(/[^a-z0-9-]/g, '-');

export const test = base.extend<Fixtures>({
  roles: [
    async ({ browser, baseURL }, use, testInfo) => {
      if (!baseURL) throw new Error('HALO baseURL is required');
      const scenarioId = testInfo.title.match(/E\d{2}/)?.[0]?.toLowerCase() ?? 'scenario';
      const prefix = `qe-${runId}-${testInfo.workerIndex}-${scenarioId}`;
      const roles = await createAuthenticatedRoles(browser, baseURL, prefix);
      await use(roles);
      const failures = await roles.cleanup();
      reportCleanup(failures, testInfo);
    },
    { auto: true }
  ],

  haloApi: async ({ roles }, use, testInfo) => {
    const scenarioId = testInfo.title.match(/E\d{2}/)?.[0]?.toLowerCase() ?? 'scenario';
    const prefix = `qe-${runId}-${testInfo.workerIndex}-${scenarioId}`;
    const api = new HaloApi(roles.adminContext.request, prefix);
    await use(api);
    const failures = await api.cleanup();
    reportCleanup(
      failures.map(failure => `delete post ${failure.resourceName} failed: ${failure.message}`),
      testInfo
    );
  },

  adminPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.admin.storageStatePath });
    const page = await context.newPage();
    await use(page);
    await context.close();
  },

  authorPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.author.storageStatePath });
    const page = await context.newPage();
    await use(page);
    await context.close();
  },

  readonlyPage: async ({ browser, roles }, use) => {
    const context = await browser.newContext({ storageState: roles.readonly.storageStatePath });
    const page = await context.newPage();
    await use(page);
    await context.close();
  }
});

function reportCleanup(failures: string[], testInfo: TestInfo): void {
  if (failures.length === 0) return;
  testInfo.annotations.push({ type: 'cleanup', description: failures.join('; ') });
  if (testInfo.status === testInfo.expectedStatus) {
    throw new Error(`cleanup failed: ${failures.join('; ')}`);
  }
}

export { expect } from '@playwright/test';
