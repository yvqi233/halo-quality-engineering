import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const HTTP_METHODS = new Set([
  'get',
  'put',
  'post',
  'delete',
  'options',
  'head',
  'patch',
  'trace'
]);

const objectOrEmpty = (value) => (
  value && typeof value === 'object' && !Array.isArray(value) ? value : {}
);

const escapePointerSegment = (value) => String(value)
  .replaceAll('~', '~0')
  .replaceAll('/', '~1');

const pointerSegment = (value) => escapePointerSegment(value);

const sortedKeys = (value) => Object.keys(objectOrEmpty(value)).sort();

const typeValue = (value) => typeof value === 'string' ? value : undefined;

/**
 * Finds backward-incompatible changes from a reviewed OpenAPI baseline.
 *
 * @param {object} baseline
 * @param {object} candidate
 * @returns {Array<{kind: string, pointer: string, before?: string, after?: string}>}
 */
export function findBreakingChanges(baseline, candidate) {
  const changes = [];
  const baselinePaths = objectOrEmpty(baseline?.paths);
  const candidatePaths = objectOrEmpty(candidate?.paths);

  for (const pathName of sortedKeys(baselinePaths)) {
    const pathPointer = `#/paths/${pointerSegment(pathName)}`;
    const baselinePath = objectOrEmpty(baselinePaths[pathName]);
    const candidatePath = candidatePaths[pathName];

    if (!candidatePath || typeof candidatePath !== 'object') {
      changes.push({ kind: 'PATH_REMOVED', pointer: pathPointer });
      continue;
    }

    const candidatePathItem = objectOrEmpty(candidatePath);
    for (const method of sortedKeys(baselinePath)) {
      if (HTTP_METHODS.has(method) && !(method in candidatePathItem)) {
        changes.push({ kind: 'METHOD_REMOVED', pointer: `${pathPointer}/${method}` });
      }
    }
  }

  const baselineSchemas = objectOrEmpty(baseline?.components?.schemas);
  const candidateSchemas = objectOrEmpty(candidate?.components?.schemas);
  for (const schemaName of sortedKeys(baselineSchemas)) {
    const schemaPointer = `#/components/schemas/${pointerSegment(schemaName)}`;
    const baselineSchema = objectOrEmpty(baselineSchemas[schemaName]);
    const candidateSchema = candidateSchemas[schemaName];

    if (!candidateSchema || typeof candidateSchema !== 'object') {
      changes.push({ kind: 'SCHEMA_REMOVED', pointer: schemaPointer });
      continue;
    }

    const candidateSchemaObject = objectOrEmpty(candidateSchema);
    const baselineProperties = objectOrEmpty(baselineSchema.properties);
    const candidateProperties = objectOrEmpty(candidateSchemaObject.properties);
    for (const propertyName of sortedKeys(baselineProperties)) {
      const propertyPointer = `${schemaPointer}/properties/${pointerSegment(propertyName)}`;
      const baselineProperty = objectOrEmpty(baselineProperties[propertyName]);
      const candidateProperty = candidateProperties[propertyName];

      if (!candidateProperty || typeof candidateProperty !== 'object') {
        changes.push({ kind: 'PROPERTY_REMOVED', pointer: propertyPointer });
        continue;
      }

      const before = typeValue(baselineProperty.type);
      const after = typeValue(candidateProperty.type);
      if (before !== after) {
        const change = { kind: 'TYPE_CHANGED', pointer: `${propertyPointer}/type` };
        if (before !== undefined) change.before = before;
        if (after !== undefined) change.after = after;
        changes.push(change);
      }
    }

    const baselineRequired = new Set(
      Array.isArray(baselineSchema.required) ? baselineSchema.required : []
    );
    const candidateRequired = new Set(
      Array.isArray(candidateSchemaObject.required) ? candidateSchemaObject.required : []
    );
    for (const propertyName of [...candidateRequired].sort()) {
      if (!baselineRequired.has(propertyName)) {
        changes.push({
          kind: 'PROPERTY_REQUIRED',
          pointer: `${schemaPointer}/required/${pointerSegment(propertyName)}`
        });
      }
    }
  }

  return changes.sort((left, right) => {
    if (left.pointer !== right.pointer) return left.pointer < right.pointer ? -1 : 1;
    if (left.kind !== right.kind) return left.kind < right.kind ? -1 : 1;
    return 0;
  });
}

function runCli() {
  const [baselinePath, candidatePath] = process.argv.slice(2);
  if (!baselinePath || !candidatePath) {
    console.error('Usage: node contracts/openapi-check/check.mjs <baseline.json> <candidate.json>');
    process.exitCode = 1;
    return;
  }

  const baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
  const candidate = JSON.parse(readFileSync(candidatePath, 'utf8'));
  const changes = findBreakingChanges(baseline, candidate);
  console.log(JSON.stringify(changes, null, 2));
  if (changes.length > 0) process.exitCode = 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  runCli();
}
