import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { RoleName } from './role-auth';

export interface CanonicalStatePaths {
  admin: string;
  author: string;
  readonly: string;
  manifest: string;
}

export interface CanonicalRole {
  username: string;
  storageStatePath: string;
}

export interface CanonicalRoles {
  owner: 'setup';
  admin: CanonicalRole;
  author: CanonicalRole;
  readonly: CanonicalRole;
  createdUsers: string[];
}

export interface SetupManifest {
  owner: 'setup';
  admin: string;
  author: string;
  readonly: string;
  createdUsers: string[];
}

export function authDirectory(): string {
  return path.resolve(__dirname, '..', '.auth');
}

export function canonicalStatePaths(directory = authDirectory()): CanonicalStatePaths {
  return {
    admin: path.join(directory, 'admin.json'),
    author: path.join(directory, 'author.json'),
    readonly: path.join(directory, 'readonly.json'),
    manifest: path.join(directory, 'setup-manifest.json')
  };
}

export function stateDestination(
  owner: 'setup' | 'test',
  paths: CanonicalStatePaths,
  role: RoleName
): string | undefined {
  return owner === 'setup' ? paths[role] : undefined;
}

export async function loadCanonicalRoles(directory = authDirectory()): Promise<CanonicalRoles> {
  const paths = canonicalStatePaths(directory);
  await Promise.all([paths.admin, paths.author, paths.readonly].map(file => access(file)));
  const manifest = JSON.parse(await readFile(paths.manifest, 'utf8')) as SetupManifest;
  if (manifest.owner !== 'setup') throw new Error('canonical role manifest is not setup-owned');
  if (!manifest.admin || !manifest.author || !manifest.readonly) {
    throw new Error('canonical role manifest is missing a verified principal');
  }
  return {
    owner: 'setup',
    admin: { username: manifest.admin, storageStatePath: paths.admin },
    author: { username: manifest.author, storageStatePath: paths.author },
    readonly: { username: manifest.readonly, storageStatePath: paths.readonly },
    createdUsers: [...manifest.createdUsers]
  };
}
