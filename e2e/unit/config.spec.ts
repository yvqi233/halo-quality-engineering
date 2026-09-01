import { expect, test } from '@playwright/test';
import config from '../playwright.config';

test('chromium consumes setup and setup owns reliable teardown', () => {
  const projects = config.projects ?? [];
  const setup = projects.find(project => project.name === 'setup');
  const chromium = projects.find(project => project.name === 'chromium');

  expect(setup?.teardown).toBe('teardown');
  expect(chromium?.dependencies).toEqual(['setup']);
  expect(config.retries).toBe(0);
});
