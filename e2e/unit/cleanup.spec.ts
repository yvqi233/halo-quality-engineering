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
  expect(causeMessages(result)).toEqual([
    'delete readonly: HTTP 403',
    'close author-context: close failed'
  ]);
});

test('preserves an existing close failure when later cleanup also fails', () => {
  const primary = new Error('login failed', { cause: new Error('close failed login context author: rejected') });
  const result = attachCleanupFailures(primary, [
    { operation: 'delete user', resourceName: 'readonly', message: 'HTTP 500' },
    { operation: 'close context', resourceName: 'admin', message: 'rejected' }
  ]);

  expect(causeMessages(result)).toEqual([
    'close failed login context author: rejected',
    'delete user readonly: HTTP 500',
    'close context admin: rejected'
  ]);
});

function causeMessages(error: Error): string[] {
  const cause = error.cause;
  if (cause instanceof AggregateError) {
    return cause.errors.map(item => item instanceof Error ? item.message : String(item));
  }
  return cause instanceof Error ? [cause.message] : [];
}
