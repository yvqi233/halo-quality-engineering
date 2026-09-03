import { expect, test } from '../fixtures/test';
import { LoginPage } from '../pages/login-page';

test('E01 admin login reaches console', async ({ page }) => {
  const login = new LoginPage(page);
  await login.open();
  await login.login('qe-admin', 'HaloQE!2026');
  await expect(page).toHaveURL(/\/console(?:\/|$)/);
});

test('E02 wrong password remains unauthenticated', async ({ page }) => {
  const login = new LoginPage(page);
  await login.open();
  await login.login('qe-admin', 'incorrect-synthetic-password');

  await expect(page.getByRole('alert')).toHaveText('Invalid credentials.');
  await expect(page).toHaveURL(/\/login(?:\?|$)/);
});

test('E03 author opens Posts and readonly is redirected from console', async ({
  canonicalAuthorPage,
  canonicalReadonlyPage
}) => {
  await canonicalAuthorPage.goto('/uc');
  await canonicalAuthorPage.getByRole('listitem').filter({ hasText: /^Posts$/ }).click();
  await expect(canonicalAuthorPage).toHaveURL(/\/uc\/posts(?:\/|$)/);

  await canonicalReadonlyPage.goto('/console/posts');
  await expect(canonicalReadonlyPage).toHaveURL(/\/console\/403$/);
});

test('E09 admin logout invalidates the former context', async ({ adminPage }) => {
  await adminPage.goto('/console');
  const logout = adminPage.getByRole('complementary').getByRole('button').last();
  await logout.hover();
  await expect(adminPage.getByText('Logout', { exact: true })).toBeVisible();
  await logout.click();
  await adminPage.getByRole('button', { name: 'Confirm' }).click();
  await expect(adminPage).toHaveURL(/\/logout$/);
  await adminPage.getByRole('button', { name: 'Logout' }).click();
  await adminPage.goto('/console');
  await expect(adminPage).toHaveURL(/\/login(?:\?|$)/);
});

test('E10 @session-expiry idle session redirects to Login', async ({ adminPage }) => {
  await adminPage.goto('/console');
  await expect(adminPage).toHaveURL(/\/console(?:\/|$)/);

  const context = adminPage.context();
  await context.setOffline(true);
  const idleStarted = performance.now();
  await expect.poll(() => performance.now() - idleStarted, { timeout: 10_000 }).toBeGreaterThan(6_000);
  await context.setOffline(false);

  await adminPage.goto('/console');
  await expect(adminPage).toHaveURL(/\/login(?:\?|$)/);
});
