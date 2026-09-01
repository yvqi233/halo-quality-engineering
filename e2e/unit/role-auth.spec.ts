import { expect, test } from '@playwright/test';
import type { APIResponse, Browser, BrowserContext, Page } from '@playwright/test';
import { createAuthenticatedRoles } from '../fixtures/role-auth';

test('provisioning failure preserves its error while reverse cleanup and closure continue', async () => {
  const events: string[] = [];
  let contextNumber = 0;
  const browser = {
    newContext: async () => {
      contextNumber += 1;
      const number = contextNumber;
      const page = fakePage(number === 2 ? new Error('author login failed') : undefined, events);
      const context = {
        newPage: async () => page,
        storageState: async () => ({ cookies: [], origins: [] }),
        close: async () => {
          events.push(`close context ${number}`);
          if (number === 1) throw new Error('admin context close failed');
        },
        request: {
          get: async () => response(200, { name: 'qe-admin' }),
          post: async (_url: string, options: { data?: { name?: string } }) => {
            events.push(`create ${options.data?.name}`);
            return response(201, {});
          },
          delete: async (url: string) => {
            const username = decodeURIComponent(url.split('/').at(-1) ?? '');
            events.push(`delete ${username}`);
            return response(username.endsWith('-readonly') ? 500 : 204, {});
          }
        }
      };
      return context as unknown as BrowserContext;
    }
  } as Browser;

  let thrown: Error | undefined;
  try {
    await createAuthenticatedRoles(browser, 'http://halo.test', 'qe-run-0-setup');
  } catch (error) {
    thrown = error as Error;
  }

  expect(thrown?.message).toBe('author login failed');
  expect((thrown?.cause as Error).message).toContain('qe-run-0-setup-readonly');
  expect((thrown?.cause as Error).message).toContain('admin context close failed');
  expect(events.filter(event => event.startsWith('delete '))).toEqual([
    'delete qe-run-0-setup-readonly',
    'delete qe-run-0-setup-author'
  ]);
  expect(events).toContain('close context 1');
});

function fakePage(loginFailure: Error | undefined, events: string[]): Page {
  const locator = { fill: async () => {}, click: async () => {} };
  return {
    goto: async () => {},
    getByLabel: () => locator,
    getByRole: () => locator,
    waitForURL: async () => {
      if (loginFailure) throw loginFailure;
    },
    close: async () => events.push('close page')
  } as unknown as Page;
}

function response(status: number, body: object): APIResponse {
  return {
    status: () => status,
    ok: () => status >= 200 && status < 300,
    json: async () => body
  } as APIResponse;
}
