export interface CleanupFailure {
  operation: string;
  resourceName: string;
  message: string;
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
  const details = failures.map(failure => new Error(
    `${failure.operation} ${failure.resourceName}: ${failure.message}`
  ));
  const existing = error.cause === undefined
    ? []
    : error.cause instanceof AggregateError
      ? [...error.cause.errors]
      : [error.cause];
  const causes = [...existing, ...details];
  error.cause = causes.length === 1 ? causes[0] : new AggregateError(causes, 'cleanup failures');
  return error;
}

export function formatCleanupFailures(failures: CleanupFailure[]): string[] {
  return failures.map(failure => `${failure.operation} ${failure.resourceName}: ${failure.message}`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
