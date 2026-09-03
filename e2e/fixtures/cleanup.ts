export interface CleanupFailure {
  operation: string;
  resourceName: string;
  message: string;
}

class CleanupFailureCause extends Error {
  constructor(readonly failure: CleanupFailure) {
    super(`${failure.operation} ${failure.resourceName}: ${failure.message}`);
  }
}

export async function runReverseCleanup<T>(
  items: readonly T[],
  operation: string,
  cleanup: (item: T) => Promise<void>,
  name: (item: T) => string = item => String(item)
): Promise<CleanupFailure[]> {
  const failures: CleanupFailure[] = [];
  for (const item of [...items].reverse()) {
    try {
      await cleanup(item);
    } catch (error) {
      failures.push({ operation, resourceName: name(item), message: errorMessage(error) });
    }
  }
  return failures;
}

export function attachCleanupFailures(primary: unknown, failures: CleanupFailure[]): Error {
  const error = primary instanceof Error ? primary : new Error(String(primary));
  if (failures.length === 0) return error;
  const details = failures.map(failure => new CleanupFailureCause(failure));
  const existing = error.cause === undefined
    ? []
    : error.cause instanceof AggregateError
      ? [...error.cause.errors]
      : [error.cause];
  const causes = [...existing, ...details];
  error.cause = causes.length === 1 ? causes[0] : new AggregateError(causes, 'cleanup failures');
  return error;
}

export function attachedCleanupFailures(error: unknown): CleanupFailure[] {
  if (!(error instanceof Error) || error.cause === undefined) return [];
  return cleanupFailuresFromCause(error.cause);
}

export function formatCleanupFailures(failures: CleanupFailure[]): string[] {
  return failures.map(failure => `${failure.operation} ${failure.resourceName}: ${failure.message}`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function cleanupFailuresFromCause(cause: unknown): CleanupFailure[] {
  if (cause instanceof CleanupFailureCause) return [cause.failure];
  if (cause instanceof AggregateError) {
    return cause.errors.flatMap(item => cleanupFailuresFromCause(item));
  }
  if (cause instanceof Error && cause.cause !== undefined) {
    return cleanupFailuresFromCause(cause.cause);
  }
  return [];
}
