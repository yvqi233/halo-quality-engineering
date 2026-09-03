package dev.quality.halo.support;

import io.restassured.response.Response;
import java.time.Duration;
import java.util.Objects;
import java.util.concurrent.locks.LockSupport;
import java.util.function.Predicate;
import java.util.function.Supplier;

public final class Eventually {
    private static final long MAX_DELAY_NANOS = Duration.ofSeconds(1).toNanos();

    private Eventually() {}

    public static Response until(
            Duration deadline,
            Duration initialDelay,
            Supplier<Response> observation,
            Predicate<Response> satisfied) {
        Objects.requireNonNull(deadline, "deadline");
        Objects.requireNonNull(initialDelay, "initialDelay");
        Objects.requireNonNull(observation, "observation");
        Objects.requireNonNull(satisfied, "satisfied");
        if (deadline.isZero() || deadline.isNegative() || initialDelay.isZero() || initialDelay.isNegative()) {
            throw new IllegalArgumentException("Deadline and initial delay must be positive");
        }

        long started = System.nanoTime();
        long deadlineNanos = deadline.toNanos();
        long delayNanos = Math.min(initialDelay.toNanos(), MAX_DELAY_NANOS);
        Response last;
        do {
            last = observation.get();
            if (satisfied.test(last)) {
                return last;
            }
            long elapsed = System.nanoTime() - started;
            if (elapsed >= deadlineNanos) {
                throw new ConditionTimeoutException(last);
            }
            LockSupport.parkNanos(Math.min(delayNanos, deadlineNanos - elapsed));
            delayNanos = Math.min(delayNanos * 2, MAX_DELAY_NANOS);
        } while (true);
    }

    public static final class ConditionTimeoutException extends AssertionError {
        private final Response lastObservation;

        private ConditionTimeoutException(Response lastObservation) {
            super("Condition was not satisfied before the deadline; last observation was HTTP "
                    + lastObservation.statusCode());
            this.lastObservation = lastObservation;
        }

        public Response lastObservation() {
            return lastObservation;
        }
    }
}
