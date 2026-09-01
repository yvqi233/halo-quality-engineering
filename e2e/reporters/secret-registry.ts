import { randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const INVOCATION_NAMESPACE_ENV = 'HALO_QE_INVOCATION_ID';
const defaultRegistryRoot = path.resolve(__dirname, '..', '.auth', 'redaction-values');
const SAFE_NAMESPACE = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/;

interface RegistryLocation {
  namespace?: string;
  root?: string;
}

export function ensureInvocationNamespace(environment: NodeJS.ProcessEnv = process.env): string {
  const existing = environment[INVOCATION_NAMESPACE_ENV];
  if (existing) return validateNamespace(existing);
  const namespace = randomUUID();
  environment[INVOCATION_NAMESPACE_ENV] = namespace;
  return namespace;
}

export function registryNamespacePath(location: RegistryLocation = {}): string {
  const namespace = validateNamespace(location.namespace ?? ensureInvocationNamespace());
  return path.join(path.resolve(location.root ?? defaultRegistryRoot), namespace);
}

export async function registerSecret(value: string, location: RegistryLocation = {}): Promise<void> {
  if (!value) return;
  const directory = registryNamespacePath(location);
  await mkdir(directory, { recursive: true });
  const filename = `${process.pid}-${randomUUID()}.secret`;
  await writeFile(path.join(directory, filename), value, { encoding: 'utf8', flag: 'wx' });
}

export async function readRegisteredSecrets(location: RegistryLocation = {}): Promise<string[]> {
  const directory = registryNamespacePath(location);
  let files: string[];
  try {
    files = await readdir(directory);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  }
  const values = await Promise.all(files.map(file => readFile(path.join(directory, file), 'utf8')));
  return [...new Set(values.filter(Boolean))];
}

export async function clearRegisteredSecrets(location: RegistryLocation = {}): Promise<void> {
  await rm(registryNamespacePath(location), { recursive: true, force: true });
}

function validateNamespace(namespace: string): string {
  if (!SAFE_NAMESPACE.test(namespace)) throw new Error('invalid credential registry invocation namespace');
  return namespace;
}
