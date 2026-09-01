import { randomUUID } from 'node:crypto';
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';

const registryDirectory = path.resolve(__dirname, '..', '.auth', 'redaction-values');

export async function registerSecret(value: string): Promise<void> {
  if (!value) return;
  await mkdir(registryDirectory, { recursive: true });
  const filename = `${process.pid}-${randomUUID()}.secret`;
  await writeFile(path.join(registryDirectory, filename), value, { encoding: 'utf8', flag: 'wx' });
}

export async function readRegisteredSecrets(): Promise<string[]> {
  let files: string[];
  try {
    files = await readdir(registryDirectory);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return [];
    throw error;
  }
  const values = await Promise.all(files.map(file => readFile(path.join(registryDirectory, file), 'utf8')));
  return [...new Set(values.filter(Boolean))];
}

export async function clearRegisteredSecrets(): Promise<void> {
  await rm(registryDirectory, { recursive: true, force: true });
}
