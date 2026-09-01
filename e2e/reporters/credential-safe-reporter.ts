import path from 'node:path';
import type { FullResult, Reporter } from '@playwright/test/reporter';
import { sanitizeArtifactTree } from './artifact-sanitizer';
import { clearRegisteredSecrets, readRegisteredSecrets } from './secret-registry';

interface ReporterOptions {
  artifactRoot?: string;
}

export default class CredentialSafeReporter implements Reporter {
  private readonly artifactRoot: string;

  constructor(options: ReporterOptions = {}) {
    this.artifactRoot = path.resolve(options.artifactRoot ?? 'artifacts');
  }

  async onEnd(result: FullResult): Promise<{ status?: FullResult['status'] }> {
    try {
      const secrets = await readRegisteredSecrets();
      await sanitizeArtifactTree(path.join(this.artifactRoot, 'test-results'), secrets);
      await sanitizeArtifactTree(path.join(this.artifactRoot, 'html-report'), secrets);
      await sanitizeArtifactTree(path.join(this.artifactRoot, 'junit.xml'), secrets);
      return { status: result.status };
    } catch (error) {
      process.stderr.write(`Credential-safe artifact sanitization failed: ${errorMessage(error)}\n`);
      return { status: 'failed' };
    } finally {
      await clearRegisteredSecrets().catch(error => {
        process.stderr.write(`Credential registry cleanup failed: ${errorMessage(error)}\n`);
      });
    }
  }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
