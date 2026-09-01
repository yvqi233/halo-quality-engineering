import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const REQUIRED_FIELDS = ['testId', 'issueUrl', 'owner', 'reason', 'expiresAt', 'restoreAfterGreenRuns'];
const ISO_8601 = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|([+-])(\d{2}):(\d{2}))$/;

/** Parses the intentionally small quarantine.yaml schema without accepting implicit YAML features. */
function parseQuarantine(source) {
  const root = { cases: undefined };
  let current;
  let lineNumber = 0;
  for (const rawLine of source.replace(/^\uFEFF/, '').split(/\r?\n/)) {
    lineNumber += 1;
    if (!rawLine.trim() || rawLine.trimStart().startsWith('#')) continue;
    if (rawLine === 'cases: []') {
      if (root.cases !== undefined) throw new Error(`line ${lineNumber}: duplicate cases declaration`);
      root.cases = [];
      continue;
    }
    if (rawLine === 'cases:') {
      if (root.cases !== undefined) throw new Error(`line ${lineNumber}: duplicate cases declaration`);
      root.cases = [];
      continue;
    }
    const caseMatch = rawLine.match(/^  -(?:\s+(\w+)\s*:\s*(.*))?\s*$/);
    if (caseMatch) {
      if (!Array.isArray(root.cases)) throw new Error(`line ${lineNumber}: cases must be declared before entries`);
      current = {};
      root.cases.push(current);
      if (caseMatch[1]) current[caseMatch[1]] = parseScalar(caseMatch[2], lineNumber);
      continue;
    }
    const fieldMatch = rawLine.match(/^    (\w+)\s*:\s*(.*)\s*$/);
    if (fieldMatch && current) {
      if (Object.hasOwn(current, fieldMatch[1])) throw new Error(`line ${lineNumber}: duplicate field ${fieldMatch[1]}`);
      current[fieldMatch[1]] = parseScalar(fieldMatch[2], lineNumber);
      continue;
    }
    throw new Error(`line ${lineNumber}: unsupported quarantine YAML`);
  }
  if (!Array.isArray(root.cases)) throw new Error('quarantine must declare cases');
  return root.cases;
}

function parseScalar(raw, lineNumber) {
  try {
    return scalar(raw);
  } catch (error) {
    throw new Error(`line ${lineNumber}: ${error.message}`);
  }
}

function scalar(raw) {
  const value = raw.trim();
  if (!value) return '';
  const startsQuote = value.startsWith('"') || value.startsWith("'");
  const endsQuote = value.endsWith('"') || value.endsWith("'");
  if (startsQuote || endsQuote) {
    const quote = value[0];
    const matchingTerminalQuote = value.endsWith(quote)
      && (quote !== '"' || !isEscaped(value, value.length - 1));
    if (!matchingTerminalQuote || (quote === "'" && value.split("'").length % 2 !== 1)) {
      throw new Error('malformed quoted scalar');
    }
    return value.slice(1, -1);
  }
  return value;
}

function isEscaped(value, index) {
  let slashes = 0;
  for (let cursor = index - 1; cursor >= 0 && value[cursor] === '\\'; cursor -= 1) slashes += 1;
  return slashes % 2 === 1;
}

function parseIso8601(value) {
  const match = ISO_8601.exec(value);
  if (!match) return undefined;
  const timestamp = Date.parse(value);
  if (Number.isNaN(timestamp)) return undefined;

  const [, year, month, day, hour, minute, second, zone, sign, zoneHour, zoneMinute] = match;
  const offsetMinutes = zone === 'Z' ? 0 : (sign === '+' ? 1 : -1)
    * (Number(zoneHour) * 60 + Number(zoneMinute));
  const localClock = new Date(timestamp + offsetMinutes * 60_000);
  if (localClock.getUTCFullYear() !== Number(year)
    || localClock.getUTCMonth() + 1 !== Number(month)
    || localClock.getUTCDate() !== Number(day)
    || localClock.getUTCHours() !== Number(hour)
    || localClock.getUTCMinutes() !== Number(minute)
    || localClock.getUTCSeconds() !== Number(second)) {
    return undefined;
  }
  return timestamp;
}

function isPublicIssueUrl(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    const privateIpv4 = /^(10\.|127\.|169\.254\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/;
    return url.protocol === 'https:'
      && !url.username
      && !url.password
      && host !== 'localhost'
      && !host.endsWith('.local')
      && !host.endsWith('.test')
      && !privateIpv4.test(host)
      && !host.includes(':')
      && /(?:^|\/)issues?\//.test(url.pathname);
  } catch {
    return false;
  }
}

export function validateQuarantine(source, now = new Date()) {
  let cases;
  try {
    cases = parseQuarantine(source);
  } catch (error) {
    return [error.message];
  }

  const errors = [];
  cases.forEach((entry, index) => {
    const prefix = `cases[${index}]`;
    for (const field of REQUIRED_FIELDS) {
      if (typeof entry[field] !== 'string' || !entry[field].trim()) {
        errors.push(`${prefix}.${field} is required`);
      }
    }
    if (typeof entry.issueUrl === 'string' && entry.issueUrl.trim() && !isPublicIssueUrl(entry.issueUrl)) {
      errors.push(`${prefix}.issueUrl must be a public HTTPS URL`);
    }
    if (typeof entry.expiresAt === 'string' && entry.expiresAt.trim()) {
      const expiry = parseIso8601(entry.expiresAt);
      if (expiry === undefined) {
        errors.push(`${prefix}.expiresAt must be ISO-8601`);
      } else if (expiry <= now.getTime()) {
        errors.push(`${prefix}.expiresAt is expired`);
      }
    }
    if (typeof entry.restoreAfterGreenRuns === 'string' && entry.restoreAfterGreenRuns.trim()
      && !/^(10|1[1-9]|20)$/.test(entry.restoreAfterGreenRuns)) {
      errors.push(`${prefix}.restoreAfterGreenRuns must be an integer between 10 and 20`);
    }
  });
  return errors;
}

function runCli() {
  const args = process.argv.slice(2);
  const fileIndex = args.indexOf('--file');
  const nowIndex = args.indexOf('--now');
  const path = fileIndex >= 0 ? args[fileIndex + 1] : 'docs/quarantine.yaml';
  const now = nowIndex >= 0 ? new Date(args[nowIndex + 1]) : new Date();
  if (!path || Number.isNaN(now.getTime())) {
    console.error('Usage: node scripts/validate-quarantine.mjs [--file <path>] [--now <ISO-8601>]');
    process.exitCode = 2;
    return;
  }
  let source;
  try {
    source = readFileSync(path, 'utf8');
  } catch (error) {
    console.error(`Unable to read quarantine file: ${error.message}`);
    process.exitCode = 2;
    return;
  }
  const errors = validateQuarantine(source, now);
  if (errors.length) {
    errors.forEach(error => console.error(`Invalid quarantine: ${error}`));
    process.exitCode = 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) runCli();
