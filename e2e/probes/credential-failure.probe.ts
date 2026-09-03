import { expect, test } from '../fixtures/test';
import { ADMIN_PASSWORD } from '../fixtures/role-auth';
import { registerSecret } from '../reporters/secret-registry';

test('credential failure probe retains diagnostics without credentials', async ({ adminPage, roles }, testInfo) => {
  await adminPage.goto('/console');
  await expect(adminPage).toHaveURL(/\/console(?:\/|$)/);

  const generatedPassword = `fixture-${roles.author.username}-password`;
  const controlledSession = 'probe-session-value-4f0797';
  const controlledToken = 'probe-token-value-42a971';
  await Promise.all([
    registerSecret(generatedPassword),
    registerSecret(controlledSession),
    registerSecret(controlledToken)
  ]);

  await testInfo.attach('credential-probe-diagnostics.txt', {
    body: Buffer.from([
      'diagnostic-marker=halo-qe-probe-retained',
      `setupPassword=${ADMIN_PASSWORD}`,
      `generatedPassword=${generatedPassword}`,
      `Authorization: Bearer ${controlledToken}`,
      `Cookie: SESSION=${controlledSession}`,
      `Set-Cookie: SESSION=${controlledSession}`,
      `token=${controlledToken}`,
      `storageState=${controlledSession}`,
      `session=${controlledSession}`
    ].join('\n')),
    contentType: 'text/plain'
  });

  expect('intentional credential probe failure').toBe('successful probe');
});
