import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import AdmZip from 'adm-zip';
import { expect, test } from '@playwright/test';
import { sanitizeArtifactTree, validateArtifactTree } from '../reporters/artifact-sanitizer';

test('sanitizes trace archives and embedded HTML report archives', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'halo-qe-sanitize-'));
  const password = 'probe-generated-password';
  const session = 'probe-session-value';
  const token = 'probe-token-value';

  try {
    const trace = new AdmZip();
    trace.addFile(
      'trace.trace',
      Buffer.from(
        `${JSON.stringify({
          type: 'before',
          apiName: 'locator.fill',
          params: { selector: 'internal:label=Password', value: password }
        })}\n`
      )
    );
    trace.addFile(
      'trace.network',
      Buffer.from(
        `${JSON.stringify({
          request: {
            headers: [
              { name: 'Cookie', value: `SESSION=${session}` },
              { name: 'Authorization', value: 'Bearer probe-token-value' }
            ],
            postData: `password=${password}&token=${token}`
          },
          response: { headers: [{ name: 'Set-Cookie', value: `SESSION=${session}` }] }
        })}\n`
      )
    );
    trace.getEntries().forEach(entry => { entry.header.method = 8; });
    trace.writeZip(path.join(directory, 'trace.zip'));

    const reportArchive = new AdmZip();
    reportArchive.addFile('report.json', Buffer.from(JSON.stringify({ storageState: session, password })));
    const embedded = reportArchive.toBuffer().toString('base64');
    await writeFile(
      path.join(directory, 'index.html'),
      `<script id="playwrightReportBase64">data:application/zip;base64,${embedded}</script>`
    );

    await sanitizeArtifactTree(directory, [password, session, token]);
    await validateArtifactTree(directory, [password, session, token]);

    const traceText = new AdmZip(path.join(directory, 'trace.zip'))
      .getEntries()
      .map(entry => entry.getData().toString('utf8'))
      .join('\n');
    const html = await readFile(path.join(directory, 'index.html'), 'utf8');
    const embeddedMatch = html.match(/data:application\/zip;base64,([A-Za-z0-9+/=]+)/);
    expect(embeddedMatch).toBeTruthy();
    const reportText = new AdmZip(Buffer.from(embeddedMatch![1], 'base64'))
      .getEntries()
      .map(entry => entry.getData().toString('utf8'))
      .join('\n');
    const combined = `${traceText}\n${reportText}`;

    expect(combined).toContain('[REDACTED]');
    for (const secret of [password, session, token]) expect(combined).not.toContain(secret);
    expect(combined).not.toMatch(/Authorization|Set-Cookie|Cookie|storageState/i);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
