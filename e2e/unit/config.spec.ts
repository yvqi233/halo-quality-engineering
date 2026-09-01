import { expect, test } from '@playwright/test';
import config from '../playwright.config';

test('chromium consumes setup and setup owns reliable teardown', () => {
  const projects = config.projects ?? [];
  const setup = projects.find(project => project.name === 'setup');
  const chromium = projects.find(project => project.name === 'chromium');
  const reporters = config.reporter as [string, Record<string, unknown>][];
  const credentialSafe = reporters.find(([name]) => name.includes('credential-safe-reporter'));

  expect(setup?.teardown).toBe('teardown');
  expect(chromium?.dependencies).toEqual(['setup']);
  expect(config.retries).toBe(0);
  expect(credentialSafe?.[1].invocationId).toBe(process.env.HALO_QE_INVOCATION_ID);
  if (process.env.PW_ARTIFACT_DIR) expect(config.outputDir).toContain(process.env.PW_ARTIFACT_DIR);
  else expect(config.outputDir).toContain(process.env.HALO_QE_INVOCATION_ID!);
});
