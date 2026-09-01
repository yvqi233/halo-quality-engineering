import { expect, test } from '@playwright/test';
import { attachCleanupFailures, runReverseCleanup } from '../fixtures/cleanup';

test('attempts every cleanup in reverse order and aggregates multiple failures', async () => {
  const order: string[] = [];
  const failures = await runReverseCleanup(['first', 'second', 'third'], 'delete', async item => {
    order.push(item);
    if (item !== 'second') throw new Error(`${item} failed`);
  });

  expect(order).toEqual(['third', 'second', 'first']);
  expect(failures.map(failure => failure.resourceName)).toEqual(['third', 'first']);
});

test('preserves the primary failure while attaching cleanup details', () => {
  const primary = new Error('journey assertion failed');
  const result = attachCleanupFailures(primary, [
    { operation: 'delete', resourceName: 'readonly', message: 'HTTP 403' },
    { operation: 'close', resourceName: 'author-context', message: 'close failed' }
  ]);

  expect(result).toBe(primary);
  expect(result.message).toBe('journey assertion failed');
  expect(result.cause).toEqual(expect.objectContaining({ message: expect.stringContaining('readonly') }));
});
