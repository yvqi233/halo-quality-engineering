package dev.quality.halo.posts;

import io.restassured.response.Response;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

final class ConcurrentUpdateAwaiter {
    private ConcurrentUpdateAwaiter() {}

    static List<Response> await(
            CountDownLatch ready, CountDownLatch start, List<Future<Response>> futures, Duration timeout)
            throws InterruptedException, ExecutionException, TimeoutException {
        Objects.requireNonNull(ready, "ready");
        Objects.requireNonNull(start, "start");
        Objects.requireNonNull(futures, "futures");
        Objects.requireNonNull(timeout, "timeout");
        if (timeout.isZero() || timeout.isNegative()) {
            throw new IllegalArgumentException("timeout must be positive");
        }

        long started = System.nanoTime();
        long timeoutNanos = timeout.toNanos();
        try {
            if (!ready.await(timeoutNanos, TimeUnit.NANOSECONDS)) {
                throw new TimeoutException("Concurrent update workers were not ready before the deadline");
            }
            start.countDown();

            List<Response> responses = new ArrayList<>(futures.size());
            for (Future<Response> future : futures) {
                long remaining = timeoutNanos - (System.nanoTime() - started);
                if (remaining <= 0) {
                    throw new TimeoutException("Concurrent update response exceeded the shared deadline");
                }
                try {
                    responses.add(future.get(remaining, TimeUnit.NANOSECONDS));
                } catch (TimeoutException error) {
                    TimeoutException bounded =
                            new TimeoutException("Concurrent update response exceeded the shared deadline");
                    bounded.initCause(error);
                    throw bounded;
                }
            }
            return List.copyOf(responses);
        } catch (InterruptedException | ExecutionException | TimeoutException error) {
            futures.forEach(future -> future.cancel(true));
            throw error;
        } finally {
            start.countDown();
        }
    }
}
