import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  outputDir: 'artifacts/test-results',
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
    ['html', { outputFolder: 'artifacts/html-report', open: 'never' }],
    ['junit', { outputFile: 'artifacts/junit.xml' }]
  ],
  projects: [
    { name: 'setup', testMatch: /fixtures[\\/]auth\.setup\.ts/ },
    {
      name: 'chromium',
      testMatch: /specs[\\/].*\.spec\.ts/,
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['setup']
    }
  ]
});
