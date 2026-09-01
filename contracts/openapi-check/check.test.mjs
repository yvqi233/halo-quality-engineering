import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { findBreakingChanges } from './check.mjs';

const fixturesDirectory = new URL('./fixtures/', import.meta.url);
const read = (name) => JSON.parse(readFileSync(new URL(name, fixturesDirectory), 'utf8'));

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
