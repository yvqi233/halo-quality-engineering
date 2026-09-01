import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import type { Browser, BrowserContext, Page } from '@playwright/test';
import { LoginPage } from '../pages/login-page';

const ADMIN_USERNAME = 'qe-admin';
const ADMIN_PASSWORD = 'HaloQE!2026';
const IDENTITY_PATH = '/apis/uc.api.halo.run/v1alpha1/users/-';

export type RoleName = 'admin' | 'author' | 'readonly';

export interface RoleState {
  username: string;
  storageStatePath: string;
}

export interface AuthenticatedRoles {
  admin: RoleState;
  author: RoleState;
  readonly: RoleState;
  adminContext: BrowserContext;
  cleanup(): Promise<string[]>;
}

interface CreatedUser {
  username: string;
  password: string;
}

export async function createAuthenticatedRoles(
  browser: Browser,
  baseURL: string,
  scope: string
): Promise<AuthenticatedRoles> {
  const authDirectory = path.resolve(__dirname, '..', '.auth');
  await mkdir(authDirectory, { recursive: true });

  const contexts: BrowserContext[] = [];
  const createdUsers: CreatedUser[] = [];
  const provisioningAdminContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
  contexts.push(provisioningAdminContext);

  try {
    const admin = await saveVerifiedState(
      provisioningAdminContext,
      ADMIN_USERNAME,
      path.join(authDirectory, 'admin.json')
    );
    const authorUser = await createUser(provisioningAdminContext, `${scope}-author`, [
      'role-template-post-author',
      'role-template-post-contributor'
    ]);
    createdUsers.push(authorUser);
    const readonlyUser = await createUser(provisioningAdminContext, `${scope}-readonly`, []);
    createdUsers.push(readonlyUser);

    const authorContext = await loginContext(browser, baseURL, authorUser.username, authorUser.password);
    contexts.push(authorContext);
    const author = await saveVerifiedState(authorContext, authorUser.username, path.join(authDirectory, 'author.json'));

    const readonlyContext = await loginContext(browser, baseURL, readonlyUser.username, readonlyUser.password);
    contexts.push(readonlyContext);
    const readonly = await saveVerifiedState(
      readonlyContext,
      readonlyUser.username,
      path.join(authDirectory, 'readonly.json')
    );
    const adminContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
    contexts.push(adminContext);

    return {
      admin,
      author,
      readonly,
      adminContext,
      cleanup: async () => {
        const failures: string[] = [];
        let cleanupContext = adminContext;
        try {
          const identityResponse = await cleanupContext.request.get(IDENTITY_PATH, {
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
          });
          const identity = identityResponse.ok() ? ((await identityResponse.json()) as { name?: string }) : {};
          if (identity.name !== ADMIN_USERNAME) {
            cleanupContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
            contexts.push(cleanupContext);
          }
        } catch {
          cleanupContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
          contexts.push(cleanupContext);
        }
        for (const user of [...createdUsers].reverse()) {
          try {
            const response = await cleanupContext.request.delete(`/api/v1alpha1/users/${encodeURIComponent(user.username)}`);
            if (!response.ok() && response.status() !== 404) {
              failures.push(`delete user ${user.username} returned HTTP ${response.status()}`);
            }
          } catch (error) {
            failures.push(`delete user ${user.username} failed: ${errorMessage(error)}`);
          }
        }
        for (const context of [...contexts].reverse()) {
          await context.close().catch(error => failures.push(`close role context failed: ${errorMessage(error)}`));
        }
        return failures;
      }
    };
  } catch (error) {
    for (const user of [...createdUsers].reverse()) {
      await provisioningAdminContext.request
        .delete(`/api/v1alpha1/users/${encodeURIComponent(user.username)}`)
        .catch(() => {});
    }
    for (const context of [...contexts].reverse()) {
      await context.close().catch(() => {});
    }
    throw error;
  }
}

async function loginContext(
  browser: Browser,
  baseURL: string,
  username: string,
  password: string
): Promise<BrowserContext> {
  const context = await browser.newContext({ baseURL });
  try {
    const page = await context.newPage();
    const login = new LoginPage(page);
    await login.open();
    await login.login(username, password);
    await page.waitForURL(/\/(?:console(?:\/|$)|uc\/profile(?:\/|$))/);
    await page.close();
    return context;
  } catch (error) {
    await context.close().catch(() => {});
    throw error;
  }
}

async function saveVerifiedState(
  context: BrowserContext,
  expectedUsername: string,
  storageStatePath: string
): Promise<RoleState> {
  const response = await context.request.get(IDENTITY_PATH, {
    headers: { 'X-Requested-With': 'XMLHttpRequest' }
  });
  if (!response.ok()) {
    throw new Error(`identity verification returned HTTP ${response.status()}`);
  }
  const identity = (await response.json()) as { name?: string };
  if (identity.name !== expectedUsername) {
    throw new Error(`identity verification returned an unexpected principal`);
  }
  await context.storageState({ path: storageStatePath });
  return { username: expectedUsername, storageStatePath };
}

async function createUser(context: BrowserContext, username: string, roles: string[]): Promise<CreatedUser> {
  const password = `fixture-${username}-password`;
  const response = await context.request.post('/apis/api.console.halo.run/v1alpha1/users', {
    data: {
      name: username,
      displayName: username,
      email: `${username}@example.test`,
      password,
      roles: [...roles].sort()
    }
  });
  if (!response.ok()) {
    throw new Error(`create user ${username} returned HTTP ${response.status()}`);
  }
  return { username, password };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
