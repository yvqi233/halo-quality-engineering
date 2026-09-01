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
  const details = failures
    .map(failure => `${failure.operation} ${failure.resourceName}: ${failure.message}`)
    .join('; ');
  error.cause = new Error(`cleanup failures: ${details}`);
  return error;
}

export function formatCleanupFailures(failures: CleanupFailure[]): string[] {
  return failures.map(failure => `${failure.operation} ${failure.resourceName}: ${failure.message}`);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
