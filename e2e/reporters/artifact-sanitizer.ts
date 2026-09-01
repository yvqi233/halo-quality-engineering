import { readdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import AdmZip from 'adm-zip';

const REDACTED = '[REDACTED]';
const SENSITIVE_KEY = /^(?:authorization|cookie|set-cookie|password|passwd|token|storageState|storage_state|session|secret)$/i;
const EMBEDDED_ZIP = /data:application\/zip;base64,([A-Za-z0-9+/=]+)/g;

export async function sanitizeArtifactTree(root: string, secrets: readonly string[]): Promise<void> {
  if (!(await exists(root))) return;
  if ((await stat(root)).isFile()) {
    await sanitizeFile(root, secrets);
    return;
  }
  for (const file of await walk(root)) {
    try {
      await sanitizeFile(file, secrets);
    } catch (error) {
      throw new Error(`failed to sanitize ${file}: ${errorMessage(error)}`, { cause: error });
    }
  }
}

async function sanitizeFile(file: string, secrets: readonly string[]): Promise<void> {
  if (file.toLowerCase().endsWith('.zip')) {
    const sanitized = sanitizeZip(await readFile(file), secrets);
    await atomicWrite(file, sanitized);
    return;
  }
  const data = await readFile(file);
  if (!isProbablyText(data)) return;
  const text = data.toString('utf8');
  const sanitized = sanitizeEmbeddedArchives(sanitizeTextDocument(text, secrets), secrets);
  if (sanitized !== text) await atomicWrite(file, Buffer.from(sanitized));
}

function sanitizeZip(data: Buffer, secrets: readonly string[]): Buffer {
  const source = new AdmZip(data);
  const target = new AdmZip();
  for (const entry of source.getEntries()) {
    let content = entry.isDirectory ? Buffer.alloc(0) : entry.getData();
    if (entry.entryName.toLowerCase().endsWith('.zip') && isZipArchive(content)) {
      content = sanitizeZip(content, secrets);
    } else if (isProbablyText(content)) {
      const text = content.toString('utf8');
      content = Buffer.from(sanitizeEmbeddedArchives(sanitizeTextDocument(text, secrets), secrets));
    }
    target.addFile(entry.entryName, content, entry.comment, entry.header.attr);
  }
  return target.toBuffer();
}

function sanitizeTextDocument(text: string, secrets: readonly string[]): string {
  const lines = text.split(/(?<=\n)/);
  return lines.map(line => sanitizeLine(line, secrets)).join('');
}

function sanitizeLine(line: string, secrets: readonly string[]): string {
  const ending = line.endsWith('\r\n') ? '\r\n' : line.endsWith('\n') ? '\n' : '';
  const body = ending ? line.slice(0, -ending.length) : line;
  try {
    return `${JSON.stringify(sanitizeValue(JSON.parse(body), secrets))}${ending}`;
  } catch {
    return `${sanitizeString(body, secrets)}${ending}`;
  }
}

function sanitizeValue(value: unknown, secrets: readonly string[], parentSensitive = false): unknown {
  if (typeof value === 'string') return parentSensitive ? REDACTED : sanitizeString(value, secrets);
  if (Array.isArray(value)) return value.map(item => sanitizeValue(item, secrets, parentSensitive));
  if (!value || typeof value !== 'object') return value;

  const source = value as Record<string, unknown>;
  if (typeof source.name === 'string' && SENSITIVE_KEY.test(source.name)) {
    return { name: REDACTED, value: REDACTED };
  }
  const passwordFill = JSON.stringify(source).toLowerCase().includes('password')
    && (source.apiName === 'locator.fill' || source.method === 'fill' || 'selector' in source);
  const target: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(source)) {
    if (SENSITIVE_KEY.test(key)) continue;
    const sensitive = passwordFill && /^(?:value|text|inputValue)$/i.test(key);
    target[key] = sanitizeValue(child, secrets, sensitive);
  }
  return target;
}

function sanitizeString(value: string, secrets: readonly string[]): string {
  let sanitized = value;
  for (const secret of [...secrets].filter(Boolean).sort((left, right) => right.length - left.length)) {
    sanitized = sanitized.split(secret).join(REDACTED);
  }
  sanitized = sanitized
    .replace(
      /(^|\r?\n)([ \t]*)(?:Authorization|Cookie|Set-Cookie)\s*[:=][^\r\n]*/gi,
      `$1$2${REDACTED}`
    )
    .replace(
      /(^|\r?\n)([ \t]*)(?:password|passwd|token|storageState|storage_state|session)\s*[:=][^\r\n]*/gi,
      `$1$2${REDACTED}`
    );
  return sanitized;
}

function sanitizeEmbeddedArchives(text: string, secrets: readonly string[]): string {
  return text.replace(EMBEDDED_ZIP, (match, encoded: string) => {
    const archive = Buffer.from(encoded, 'base64');
    if (!isZipArchive(archive)) return match;
    const sanitized = sanitizeZip(archive, secrets).toString('base64');
    return `data:application/zip;base64,${sanitized}`;
  });
}

function isZipArchive(data: Buffer): boolean {
  if (data.length < 4) return false;
  return [0x04034b50, 0x06054b50, 0x08074b50].includes(data.readUInt32LE(0));
}

async function walk(root: string): Promise<string[]> {
  const files: string[] = [];
  for (const entry of await readdir(root, { withFileTypes: true })) {
    const resolved = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...await walk(resolved));
    else if (entry.isFile()) files.push(resolved);
  }
  return files;
}

async function atomicWrite(file: string, data: Buffer): Promise<void> {
  const temporary = `${file}.sanitizing-${process.pid}`;
  await writeFile(temporary, data);
  await rename(temporary, file);
}

async function exists(file: string): Promise<boolean> {
  try {
    await stat(file);
    return true;
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return false;
    throw error;
  }
}

function isProbablyText(data: Buffer): boolean {
  if (data.length === 0) return true;
  const sample = data.subarray(0, Math.min(data.length, 8192));
  let control = 0;
  for (const byte of sample) {
    if (byte === 0) return false;
    if (byte < 9 || (byte > 13 && byte < 32)) control += 1;
  }
  return control / sample.length < 0.02;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
