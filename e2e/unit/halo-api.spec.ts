import { expect, test } from '@playwright/test';
import type { APIRequestContext, APIResponse } from '@playwright/test';
import { HaloApi } from '../fixtures/halo-api';

test('scoped UI sweep tracks a saved post before observation failure and deletes it', async () => {
  const calls: string[] = [];
  const request = {
    get: async (url: string) => {
      calls.push(`GET ${url}`);
      return response(200, {
        items: [
          { post: { metadata: { name: 'qe-run-0-e04-ui-post' }, spec: {
            title: 'qe-run-0-e04-ui-title', slug: 'qe-run-0-e04-ui-post', publish: false
          } } },
          { post: { metadata: { name: 'outside-scope' }, spec: {
            title: 'outside-title', slug: 'outside-scope', publish: false
          } } }
        ]
      });
    },
    delete: async (url: string) => {
      calls.push(`DELETE ${url}`);
      return response(200, {});
    }
  } as unknown as APIRequestContext;
  const api = new HaloApi(request, 'qe-run-0-e04');

  api.reserveUiCreation('qe-run-0-e04-ui-title');
  const failures = await api.cleanup();

  expect(failures).toEqual([]);
  expect(calls).toEqual([
    'GET /apis/api.console.halo.run/v1alpha1/posts',
    'DELETE /apis/content.halo.run/v1alpha1/posts/qe-run-0-e04-ui-post'
  ]);
});

function response(status: number, body: object): APIResponse {
  return {
    status: () => status,
    ok: () => status >= 200 && status < 300,
    json: async () => body
  } as APIResponse;
}
