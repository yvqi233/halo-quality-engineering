import { expect, test } from '../fixtures/test';
import { registerSecret } from '../reporters/secret-registry';

test('forced sanitizer failure probe blocks artifact publishing', async ({ adminPage }, testInfo) => {
  await adminPage.goto('/console');
  await expect(adminPage).toHaveURL(/\/console(?:\/|$)/);

  const secret = 'forced-probe-sensitive-value-71c24d';
  await registerSecret(secret);
  await testInfo.attach('forced-sanitizer-sensitive.txt', {
    body: Buffer.from(`diagnostic-before-forced-failure\npassword=${secret}`),
    contentType: 'text/plain'
  });
});
