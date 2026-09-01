import { expect, test } from '../fixtures/test';
import { draftPayload } from '../fixtures/halo-api';
import { PostsPage } from '../pages/posts-page';

test('E04 author creates a draft through the editor', async ({ authorPage, haloApi }) => {
  const posts = new PostsPage(authorPage, 'user-center');
  const title = `${haloApi.unique('e04', 'ui')}-title`;
  await posts.open();
  await posts.createDraft(title);

  let observed;
  await expect.poll(async () => {
    observed = await haloApi.trackCreatedByTitle(title);
    if (!observed) return undefined;
    const state = await haloApi.consolePost(observed);
    return state.post?.status?.phase;
  }).toBe('DRAFT');
});

test('E05 admin publishes an API draft through Posts', async ({ adminPage, haloApi }) => {
  const ref = await haloApi.createDraft('qe-admin', 'e05');
  await expect.poll(async () => (await haloApi.consolePost(ref)).post?.status?.phase).toBe('DRAFT');

  const posts = new PostsPage(adminPage);
  await posts.open();
  await posts.publish(ref.title);

  let permalink: string | undefined;
  await expect.poll(async () => {
    const state = await haloApi.consolePost(ref);
    permalink = state.post?.status?.permalink;
    return state.post?.status?.phase;
  }).toBe('PUBLISHED');
  await expect.poll(async () => (await haloApi.publicPost(ref)).status).toBe(200);
  expect(permalink).toBeTruthy();
});

test('E06 API-published title is visible at exact anonymous permalink', async ({ browser, haloApi }) => {
  const ref = await haloApi.createDraft('qe-admin', 'e06');
  await haloApi.publish(ref);

  let permalink: string | undefined;
  await expect.poll(async () => {
    const state = await haloApi.consolePost(ref);
    permalink = state.post?.status?.permalink;
    return state.post?.status?.phase;
  }).toBe('PUBLISHED');
  expect(permalink).toBeTruthy();

  const anonymous = await browser.newContext();
  const page = await anonymous.newPage();
  await page.goto(permalink!);
  await expect(page.getByRole('heading', { name: ref.title, exact: true, level: 1 })).toBeVisible();
  await anonymous.close();
});

test('E07 admin unpublishes and anonymous permalink ceases exposure', async ({ adminPage, browser, haloApi }) => {
  const ref = await haloApi.createDraft('qe-admin', 'e07');
  await haloApi.publish(ref);

  let permalink: string | undefined;
  await expect.poll(async () => {
    const state = await haloApi.consolePost(ref);
    permalink = state.post?.status?.permalink;
    return state.post?.status?.phase;
  }).toBe('PUBLISHED');
  expect(permalink).toBeTruthy();

  const posts = new PostsPage(adminPage);
  await posts.open();
  await posts.unpublish(ref.title);
  await expect.poll(async () => (await haloApi.publicPost(ref)).status).toBe(404);

  const anonymous = await browser.newContext();
  const page = await anonymous.newPage();
  const response = await page.goto(permalink!);
  expect(response?.status()).toBe(404);
  await expect(page.getByText(ref.title, { exact: true })).toHaveCount(0);
  await anonymous.close();
});

test('E08 readonly direct create is denied once and resource remains absent', async ({ readonlyPage, roles, haloApi }) => {
  const name = haloApi.unique('e08', 'denied');
  const ref = { name, title: `${name}-title`, slug: name };
  const response = await readonlyPage.request.post('/apis/api.console.halo.run/v1alpha1/posts', {
    data: draftPayload(ref, roles.readonly.username)
  });

  expect([401, 403]).toContain(response.status());
  expect((await haloApi.consolePost(name)).status).toBe(404);
});
