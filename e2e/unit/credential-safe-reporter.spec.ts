import { mkdtemp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { expect, test } from '@playwright/test';
import type { FullResult } from '@playwright/test/reporter';
import CredentialSafeReporter, {
  SANITIZATION_FAILURE_MARKER
} from '../reporters/credential-safe-reporter';
import { registerSecret, registryNamespacePath } from '../reporters/secret-registry';

test('injected sanitizer failure evicts publishable artifacts and leaves only a safe marker', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'halo-qe-fail-closed-'));
  const artifactRoot = path.join(directory, 'artifacts');
  const registryRoot = path.join(directory, 'registry');
  const privateRoot = path.join(directory, 'private');
  const invocationId = 'injected-failure-invocation';
  const secret = 'forced-sanitizer-sensitive-value';

  try {
    await mkdir(path.join(artifactRoot, 'test-results'), { recursive: true });
    await writeFile(path.join(artifactRoot, 'test-results', 'trace.txt'), `password=${secret}`);
    await registerSecret(secret, { namespace: invocationId, root: registryRoot });

    const reporter = new CredentialSafeReporter({
      artifactRoot,
      invocationId,
      registryRoot,
      privateRoot,
      forceSanitizerFailure: true
    });
    const result = await reporter.onEnd({ status: 'passed' } as FullResult);

    expect(result.status).toBe('failed');
    expect(await readdir(artifactRoot)).toEqual([SANITIZATION_FAILURE_MARKER]);
    const marker = await readFile(path.join(artifactRoot, SANITIZATION_FAILURE_MARKER), 'utf8');
    expect(marker).toBe('Credential-safe artifact publishing was blocked.\n');
    expect(marker).not.toContain(secret);
    await expect(readFile(path.join(artifactRoot, 'test-results', 'trace.txt'))).rejects.toThrow();
    await expect(readdir(registryNamespacePath({ namespace: invocationId, root: registryRoot })))
      .rejects.toThrow();
    await expect(readdir(path.join(privateRoot, invocationId))).rejects.toThrow();
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
