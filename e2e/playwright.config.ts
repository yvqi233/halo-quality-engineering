import { defineConfig, devices } from '@playwright/test';
import { ensureInvocationNamespace } from './reporters/secret-registry';

const invocationId = ensureInvocationNamespace();
const artifactRoot = process.env.PW_ARTIFACT_DIR ?? `artifacts/${invocationId}`;

export default defineConfig({
  testDir: '.',
  outputDir: `${artifactRoot}/test-results`,
  timeout: 60_000,
  retries: 0,
  workers: process.env.CI ? 2 : 1,
  use: {
    baseURL: process.env.HALO_BASE_URL ?? 'http://127.0.0.1:8090',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure'
  },
  reporter: [
    ['html', { outputFolder: `${artifactRoot}/html-report`, open: 'never' }],
    ['junit', { outputFile: `${artifactRoot}/junit.xml` }],
    ['./reporters/credential-safe-reporter.ts', {
      artifactRoot,
      invocationId,
      forceSanitizerFailure: process.env.PW_SANITIZER_FORCE_FAILURE === '1'
    }]
  ],
  projects: [
    {
      name: 'setup',
      testMatch: /fixtures[\\/]auth\.setup\.ts/,
      workers: 1,
      teardown: 'teardown'
    },
    {
      name: 'teardown',
      testMatch: /fixtures[\\/]auth\.teardown\.ts/,
      workers: 1
    },
    {
      name: 'chromium',
      testMatch: /specs[\\/].*\.spec\.ts/,
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['setup']
    },
    {
      name: 'firefox',
      testMatch: /specs[\\/].*\.spec\.ts/,
      use: { ...devices['Desktop Firefox'] },
      dependencies: ['setup']
    },
    { name: 'unit', testMatch: /unit[\\/].*\.spec\.ts/, workers: 1 },
    {
      name: 'probe',
      testMatch: /probes[\\/].*\.probe\.ts/,
      workers: 1,
      use: { ...devices['Desktop Chrome'] }
    }
  ]
});
