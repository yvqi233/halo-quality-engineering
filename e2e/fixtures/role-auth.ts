import { mkdir } from 'node:fs/promises';
import path from 'node:path';
import type { Browser, BrowserContext } from '@playwright/test';
import { LoginPage } from '../pages/login-page';
import { registerSecret } from '../reporters/secret-registry';
import {
  attachCleanupFailures,
  type CleanupFailure,
  runReverseCleanup
} from './cleanup';
import { authDirectory, type CanonicalStatePaths, stateDestination } from './role-state';

export const ADMIN_USERNAME = 'qe-admin';
export const ADMIN_PASSWORD = 'HaloQE!2026';
const IDENTITY_PATH = '/apis/uc.api.halo.run/v1alpha1/users/-';

export type RoleName = 'admin' | 'author' | 'readonly';

export interface RoleState {
  username: string;
  storageState: string | Awaited<ReturnType<BrowserContext['storageState']>>;
}

export interface AuthenticatedRoles {
  admin: RoleState;
  author: RoleState;
  readonly: RoleState;
  adminContext: BrowserContext;
  createdUsers: string[];
  cleanup(): Promise<CleanupFailure[]>;
  closeContexts(): Promise<CleanupFailure[]>;
}

interface CreatedUser {
  username: string;
  password: string;
}

interface ProvisionOptions {
  owner?: 'setup' | 'test';
  canonicalPaths?: CanonicalStatePaths;
}

export async function createAuthenticatedRoles(
  browser: Browser,
  baseURL: string,
  scope: string,
  options: ProvisionOptions = {}
): Promise<AuthenticatedRoles> {
  const owner = options.owner ?? 'test';
  const paths = options.canonicalPaths;
  if (owner === 'setup' && !paths) throw new Error('setup role provisioning requires canonical paths');

  await mkdir(authDirectory(), { recursive: true });
  const contexts: BrowserContext[] = [];
  const createdUsers: CreatedUser[] = [];
  const provisioningAdminContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
  contexts.push(provisioningAdminContext);

  try {
    const admin = await saveVerifiedState(
      provisioningAdminContext,
      ADMIN_USERNAME,
      paths ? stateDestination(owner, paths, 'admin') : undefined
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
    const author = await saveVerifiedState(
      authorContext,
      authorUser.username,
      paths ? stateDestination(owner, paths, 'author') : undefined
    );

    const readonlyContext = await loginContext(browser, baseURL, readonlyUser.username, readonlyUser.password);
    contexts.push(readonlyContext);
    const readonly = await saveVerifiedState(
      readonlyContext,
      readonlyUser.username,
      paths ? stateDestination(owner, paths, 'readonly') : undefined
    );

    const adminContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
    contexts.push(adminContext);
    let closed = false;

    const closeContexts = async (): Promise<CleanupFailure[]> => {
      if (closed) return [];
      closed = true;
      return closeAllContexts(contexts);
    };

    return {
      admin,
      author,
      readonly,
      adminContext,
      createdUsers: createdUsers.map(user => user.username),
      closeContexts,
      cleanup: async () => {
        const failures = await cleanupUsers(browser, baseURL, createdUsers, adminContext, contexts);
        closed = true;
        return failures;
      }
    };
  } catch (error) {
    const failures = await cleanupUsers(
      browser,
      baseURL,
      createdUsers,
      provisioningAdminContext,
      contexts
    );
    throw attachCleanupFailures(error, failures);
  }
}

export async function cleanupNamedUsers(
  browser: Browser,
  baseURL: string,
  usernames: readonly string[]
): Promise<CleanupFailure[]> {
  const contexts: BrowserContext[] = [];
  const failures: CleanupFailure[] = [];
  let context: BrowserContext;
  try {
    context = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
    contexts.push(context);
  } catch (error) {
    failures.push({ operation: 'authenticate', resourceName: ADMIN_USERNAME, message: errorMessage(error) });
    context = await browser.newContext({ baseURL });
    contexts.push(context);
  }

  try {
    failures.push(...await deleteUsers(context, usernames));
  } finally {
    failures.push(...await closeAllContexts(contexts));
  }
  return failures;
}

async function cleanupUsers(
  browser: Browser,
  baseURL: string,
  users: readonly CreatedUser[],
  initialContext: BrowserContext,
  contexts: BrowserContext[]
): Promise<CleanupFailure[]> {
  const failures: CleanupFailure[] = [];
  let cleanupContext = initialContext;
  let refreshRequired = false;
  let initialAuthenticationError: unknown;
  try {
    const identity = await verifiedIdentity(cleanupContext);
    refreshRequired = identity !== ADMIN_USERNAME;
  } catch (error) {
    refreshRequired = true;
    initialAuthenticationError = error;
  }

  if (refreshRequired) {
    try {
      cleanupContext = await loginContext(browser, baseURL, ADMIN_USERNAME, ADMIN_PASSWORD);
      contexts.push(cleanupContext);
    } catch (refreshError) {
      const initial = initialAuthenticationError
        ? `initial session: ${errorMessage(initialAuthenticationError)}; `
        : '';
      failures.push({
        operation: 'authenticate',
        resourceName: ADMIN_USERNAME,
        message: `${initial}refresh: ${errorMessage(refreshError)}`
      });
    }
  }

  try {
    failures.push(...await deleteUsers(cleanupContext, users.map(user => user.username)));
  } finally {
    failures.push(...await closeAllContexts(contexts));
  }
  return failures;
}

async function deleteUsers(context: BrowserContext, usernames: readonly string[]): Promise<CleanupFailure[]> {
  return runReverseCleanup(usernames, 'delete user', async username => {
    const response = await context.request.delete(`/api/v1alpha1/users/${encodeURIComponent(username)}`);
    if (!response.ok() && response.status() !== 404) throw new Error(`HTTP ${response.status()}`);
  });
}

async function closeAllContexts(contexts: BrowserContext[]): Promise<CleanupFailure[]> {
  const pending = contexts.splice(0, contexts.length);
  return runReverseCleanup(
    pending,
    'close context',
    context => context.close(),
    () => 'browser-context'
  );
}

async function loginContext(
  browser: Browser,
  baseURL: string,
  username: string,
  password: string
): Promise<BrowserContext> {
  await registerSecret(password);
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
    const failures = await runReverseCleanup(
      [context],
      'close failed login context',
      failedContext => failedContext.close(),
      () => username
    );
    throw attachCleanupFailures(error, failures);
  }
}

async function saveVerifiedState(
  context: BrowserContext,
  expectedUsername: string,
  destination?: string
): Promise<RoleState> {
  const principal = await verifiedIdentity(context);
  if (principal !== expectedUsername) throw new Error('identity verification returned an unexpected principal');
  if (destination) {
    await context.storageState({ path: destination });
    return { username: expectedUsername, storageState: destination };
  }
  return { username: expectedUsername, storageState: await context.storageState() };
}

async function verifiedIdentity(context: BrowserContext): Promise<string | undefined> {
  const response = await context.request.get(IDENTITY_PATH, {
    headers: { 'X-Requested-With': 'XMLHttpRequest' }
  });
  if (!response.ok()) throw new Error(`identity verification returned HTTP ${response.status()}`);
  return ((await response.json()) as { name?: string }).name;
}

async function createUser(context: BrowserContext, username: string, roles: string[]): Promise<CreatedUser> {
  const password = `fixture-${username}-password`;
  await registerSecret(password);
  const response = await context.request.post('/apis/api.console.halo.run/v1alpha1/users', {
    data: {
      name: username,
      displayName: username,
      email: `${username}@example.test`,
      password,
      roles: [...roles].sort()
    }
  });
  if (!response.ok()) throw new Error(`create user ${username} returned HTTP ${response.status()}`);
  return { username, password };
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
