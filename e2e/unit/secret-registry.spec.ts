import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { expect, test } from '@playwright/test';
import {
  clearRegisteredSecrets,
  ensureInvocationNamespace,
  readRegisteredSecrets,
  registerSecret,
  registryNamespacePath
} from '../reporters/secret-registry';

test('concurrent invocation namespaces remain isolated and clean independently', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'halo-qe-registry-'));
  const firstEnvironment: NodeJS.ProcessEnv = {};
  const secondEnvironment: NodeJS.ProcessEnv = {};
  const first = ensureInvocationNamespace(firstEnvironment);
  const second = ensureInvocationNamespace(secondEnvironment);

  try {
    expect(first).not.toBe(second);
    expect(ensureInvocationNamespace(firstEnvironment)).toBe(first);
    await Promise.all([
      registerSecret('first-invocation-secret', { namespace: first, root }),
      registerSecret('second-invocation-secret', { namespace: second, root })
    ]);

    expect(await readRegisteredSecrets({ namespace: first, root })).toEqual(['first-invocation-secret']);
    expect(await readRegisteredSecrets({ namespace: second, root })).toEqual(['second-invocation-secret']);

    await clearRegisteredSecrets({ namespace: first, root });
    await expect(readRegisteredSecrets({ namespace: first, root })).resolves.toEqual([]);
    await expect(readRegisteredSecrets({ namespace: second, root })).resolves.toEqual([
      'second-invocation-secret'
    ]);
    expect(registryNamespacePath({ namespace: second, root })).not.toBe(
      registryNamespacePath({ namespace: first, root })
    );
  } finally {
    await clearRegisteredSecrets({ namespace: second, root });
    await rm(root, { recursive: true, force: true });
  }
});
