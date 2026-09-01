// Chromium depends on this setup project. Authentication itself is deliberately
// journey-scoped in role-auth.ts so every created principal has a matching teardown.
export { createAuthenticatedRoles } from './role-auth';
export type { AuthenticatedRoles, RoleName, RoleState } from './role-auth';
