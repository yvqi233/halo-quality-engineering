import { randomUUID } from 'node:crypto';
import { mkdir, rename, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { FullResult, Reporter } from '@playwright/test/reporter';
import { sanitizeArtifactTree, validateArtifactTree } from './artifact-sanitizer';
import { clearRegisteredSecrets, readRegisteredSecrets } from './secret-registry';

export const SANITIZATION_FAILURE_MARKER = 'SANITIZATION_FAILED.txt';
const FAILURE_MARKER_CONTENT = 'Credential-safe artifact publishing was blocked.\n';

export interface ReporterOptions {
  artifactRoot?: string;
  invocationId?: string;
  registryRoot?: string;
  privateRoot?: string;
  forceSanitizerFailure?: boolean;
}

export default class CredentialSafeReporter implements Reporter {
  private readonly artifactRoot: string;
  private readonly invocationId: string;
  private readonly registryRoot?: string;
  private readonly privateRoot: string;
  private readonly forceSanitizerFailure: boolean;

  constructor(options: ReporterOptions = {}) {
    this.artifactRoot = path.resolve(options.artifactRoot ?? 'artifacts');
    this.invocationId = options.invocationId ?? process.env.HALO_QE_INVOCATION_ID ?? '';
    if (!this.invocationId) throw new Error('credential-safe reporter requires an invocation namespace');
    this.registryRoot = options.registryRoot;
    this.privateRoot = path.resolve(
      options.privateRoot ?? path.join(__dirname, '..', '.auth', 'artifact-quarantine')
    );
    this.forceSanitizerFailure = options.forceSanitizerFailure ?? false;
  }

  async onEnd(result: FullResult): Promise<{ status?: FullResult['status'] }> {
    const registry = { namespace: this.invocationId, root: this.registryRoot };
    const stagingRoot = path.join(this.privateRoot, this.invocationId);
    try {
      const secrets = await readRegisteredSecrets(registry);
      await stageArtifactRoot(this.artifactRoot, stagingRoot);
      if (this.forceSanitizerFailure) throw new Error('injected artifact sanitizer failure');
      await sanitizeArtifactTree(stagingRoot, secrets);
      await validateArtifactTree(stagingRoot, secrets);
      await restoreArtifactRoot(stagingRoot, this.artifactRoot);
      await clearRegisteredSecrets(registry);
      return { status: result.status };
    } catch {
      process.stderr.write('Credential-safe artifact publishing blocked.\n');
      const safe = await installFailureMarker(
        this.artifactRoot,
        stagingRoot,
        this.privateRoot,
        this.invocationId
      ).catch(() => false);
      if (safe) {
        await clearRegisteredSecrets(registry).catch(() => {
          process.stderr.write('Credential registry cleanup failed after artifact blocking.\n');
        });
      } else {
        process.stderr.write('Unable to establish a credential-safe artifact terminal state.\n');
      }
      return { status: 'failed' };
    }
  }
}

async function stageArtifactRoot(artifactRoot: string, stagingRoot: string): Promise<void> {
  await mkdir(path.dirname(stagingRoot), { recursive: true });
  try {
    await rename(artifactRoot, stagingRoot);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    await mkdir(stagingRoot, { recursive: true });
  }
}

async function restoreArtifactRoot(stagingRoot: string, artifactRoot: string): Promise<void> {
  await mkdir(path.dirname(artifactRoot), { recursive: true });
  await rename(stagingRoot, artifactRoot);
}

async function installFailureMarker(
  artifactRoot: string,
  stagingRoot: string,
  privateRoot: string,
  invocationId: string
): Promise<boolean> {
  await evictPublishableRoot(artifactRoot, privateRoot, invocationId);
  await rm(stagingRoot, { recursive: true, force: true }).catch(() => {});
  await mkdir(artifactRoot, { recursive: true });
  await writeFile(
    path.join(artifactRoot, SANITIZATION_FAILURE_MARKER),
    FAILURE_MARKER_CONTENT,
    { encoding: 'utf8', flag: 'wx' }
  );
  return true;
}

async function evictPublishableRoot(
  artifactRoot: string,
  privateRoot: string,
  invocationId: string
): Promise<void> {
  try {
    await rm(artifactRoot, { recursive: true, force: true });
  } catch {
    await mkdir(privateRoot, { recursive: true });
    await rename(artifactRoot, path.join(privateRoot, `${invocationId}-blocked-${randomUUID()}`));
  }
}
