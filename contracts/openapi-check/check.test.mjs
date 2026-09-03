import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { findBreakingChanges } from './check.mjs';

const fixturesDirectory = new URL('./fixtures/', import.meta.url);
const read = (name) => JSON.parse(readFileSync(new URL(name, fixturesDirectory), 'utf8'));
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const checkPath = join(repositoryRoot, 'contracts/openapi-check/check.mjs');
const capturePath = join(repositoryRoot, 'scripts/capture-openapi.ps1');
const powerShellHost = process.env.HALO_QE_POWERSHELL_HOST
  ?? (process.platform === 'win32' ? 'powershell.exe' : 'pwsh');
const powerShellAvailable = (() => {
  const probe = spawnSync(powerShellHost, ['-NoProfile', '-Command', '$PSVersionTable.PSVersion'], {
    windowsHide: true
  });
  return probe.status === 0;
})();

function run(command, argumentsList) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(command, argumentsList, { cwd: repositoryRoot, windowsHide: true });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (status) => resolveRun({ status, stdout, stderr }));
  });
}

async function startJsonServer(document) {
  let requests = 0;
  const server = createServer((_request, response) => {
    requests += 1;
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify(document));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  return {
    endpoint: `http://127.0.0.1:${address.port}/openapi.json`,
    requests: () => requests,
    async close() {
      server.close();
      await once(server, 'close');
    }
  };
}

const baseDocument = () => ({
  paths: {
    '/posts': { get: {}, post: {} },
    '/tags': { get: {} }
  },
  components: {
    schemas: {
      Post: {
        properties: {
          spec: { type: 'string' },
          metadata: { type: 'object' }
        },
        required: ['spec']
      },
      Tag: { properties: {} }
    }
  }
});

test('removed property is breaking', () => {
  const changes = findBreakingChanges(read('base.json'), read('remove-field.json'));
  assert.deepEqual(changes, [{
    kind: 'PROPERTY_REMOVED', pointer: '#/components/schemas/Post/properties/spec'
  }]);
});

test('new optional property is compatible', () => {
  assert.deepEqual(findBreakingChanges(read('base.json'), read('add-optional.json')), []);
});

test('reports every declared breaking-change kind deterministically', () => {
  const baseline = baseDocument();
  const candidate = baseDocument();
  delete candidate.paths['/tags'];
  delete candidate.paths['/posts'].post;
  delete candidate.components.schemas.Tag;
  delete candidate.components.schemas.Post.properties.metadata;
  candidate.components.schemas.Post.properties.introduced = { type: 'string' };
  candidate.components.schemas.Post.required = ['spec', 'introduced'];
  candidate.components.schemas.Post.properties.spec.type = 'integer';

  assert.deepEqual(findBreakingChanges(baseline, candidate), [
    { kind: 'PROPERTY_REMOVED', pointer: '#/components/schemas/Post/properties/metadata' },
    { kind: 'TYPE_CHANGED', pointer: '#/components/schemas/Post/properties/spec/type', before: 'string', after: 'integer' },
    { kind: 'PROPERTY_REQUIRED', pointer: '#/components/schemas/Post/required/introduced' },
    { kind: 'SCHEMA_REMOVED', pointer: '#/components/schemas/Tag' },
    { kind: 'METHOD_REMOVED', pointer: '#/paths/~1posts/post' },
    { kind: 'PATH_REMOVED', pointer: '#/paths/~1tags' }
  ]);
});

test('compares OpenAPI 3.1 array-valued property types semantically', () => {
  const baseline = baseDocument();
  const candidate = baseDocument();
  baseline.components.schemas.Post.properties.spec.type = ['null', 'string'];
  candidate.components.schemas.Post.properties.spec.type = ['string', 'boolean'];

  assert.deepEqual(findBreakingChanges(baseline, candidate), [{
    kind: 'TYPE_CHANGED',
    pointer: '#/components/schemas/Post/properties/spec/type',
    before: '["null","string"]',
    after: '["boolean","string"]'
  }]);

  candidate.components.schemas.Post.properties.spec.type = ['string', 'null'];
  assert.deepEqual(findBreakingChanges(baseline, candidate), []);

  baseline.components.schemas.Post.properties.spec.type = 'string';
  candidate.components.schemas.Post.properties.spec.type = ['string'];
  assert.deepEqual(findBreakingChanges(baseline, candidate), []);

  baseline.components.schemas.Post.properties.reference = { $ref: '#/components/schemas/Metadata' };
  candidate.components.schemas.Post.properties.reference = { $ref: '#/components/schemas/Metadata' };
  assert.deepEqual(findBreakingChanges(baseline, candidate), []);
});

test('CLI prints JSON and uses contract gate exit codes', async () => {
  const removal = await run(process.execPath, [
    checkPath,
    join(repositoryRoot, 'contracts/openapi-check/fixtures/base.json'),
    join(repositoryRoot, 'contracts/openapi-check/fixtures/remove-field.json')
  ]);
  assert.equal(removal.status, 2);
  assert.equal(removal.stderr, '');
  assert.deepEqual(JSON.parse(removal.stdout), [{
    kind: 'PROPERTY_REMOVED', pointer: '#/components/schemas/Post/properties/spec'
  }]);

  const identity = await run(process.execPath, [
    checkPath,
    join(repositoryRoot, 'contracts/openapi-check/fixtures/base.json'),
    join(repositoryRoot, 'contracts/openapi-check/fixtures/base.json')
  ]);
  assert.equal(identity.status, 0);
  assert.equal(identity.stderr, '');
  assert.deepEqual(JSON.parse(identity.stdout), []);
});

test('capture preserves arrays recursively with stable keys', {
  skip: powerShellAvailable ? false : `PowerShell host ${powerShellHost} is required to verify capture-openapi.ps1.`
}, async () => {
  const document = {
    z: {
      tags: ['contract'],
      parameters: [{ name: 'page', in: 'query' }],
      enum: ['draft', 'published'],
      nested: [[], ['single'], [{ values: ['nested'] }]]
    },
    a: { required: [], singleton: ['only'] }
  };
  const server = await startJsonServer(document);
  const directory = mkdtempSync(join(tmpdir(), 'halo-openapi-capture-'));
  const outputPath = join(directory, 'baseline.json');
  try {
    const capture = await run(powerShellHost, [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', capturePath,
      '-AcceptReviewedBaseline', '-BaselinePath', outputPath, '-Endpoint', server.endpoint
    ]);
    assert.equal(capture.status, 0, capture.stderr);
    assert.equal(server.requests(), 1);
    const captured = readFileSync(outputPath, 'utf8');
    assert.deepEqual(JSON.parse(captured), document);
    assert.ok(captured.indexOf('"a"') < captured.indexOf('"z"'));
    assert.ok(captured.indexOf('"enum"') < captured.indexOf('"nested"'));
  } finally {
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  }
});

test('capture refuses overwrite before contacting its endpoint', {
  skip: powerShellAvailable ? false : `PowerShell host ${powerShellHost} is required to verify capture-openapi.ps1.`
}, async () => {
  const server = await startJsonServer({ ignored: true });
  const directory = mkdtempSync(join(tmpdir(), 'halo-openapi-refusal-'));
  const outputPath = join(directory, 'baseline.json');
  writeFileSync(outputPath, '{"reviewed":true}', 'utf8');
  try {
    const capture = await run(powerShellHost, [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', capturePath,
      '-BaselinePath', outputPath, '-Endpoint', server.endpoint
    ]);
    assert.notEqual(capture.status, 0);
    assert.match(`${capture.stdout}${capture.stderr}`, /Baseline exists/);
    assert.equal(server.requests(), 0);
    assert.equal(readFileSync(outputPath, 'utf8'), '{"reviewed":true}');
  } finally {
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
