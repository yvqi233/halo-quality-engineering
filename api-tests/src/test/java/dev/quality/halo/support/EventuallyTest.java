package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import io.restassured.builder.ResponseBuilder;
import io.restassured.response.Response;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class EventuallyTest {
    @Test
    void returnsTheObservationThatSatisfiesThePredicate() {
        AtomicInteger attempts = new AtomicInteger();

        Response result = Eventually.until(
                Duration.ofSeconds(1),
                Duration.ofNanos(1),
                () -> response(attempts.incrementAndGet() == 2 ? 202 : 503),
                observation -> observation.statusCode() == 202);

        assertThat(result.statusCode()).isEqualTo(202);
        assertThat(attempts).hasValue(2);
    }

    @Test
    void deadlineExhaustionThrowsWithTheLastObservation() {
        Response last = response(503);

        assertThatThrownBy(() -> Eventually.until(
                        Duration.ofNanos(1), Duration.ofNanos(1), () -> last, ignored -> false))
                .isInstanceOf(Eventually.ConditionTimeoutException.class)
                .hasMessageContaining("HTTP 503")
                .extracting(error -> ((Eventually.ConditionTimeoutException) error).lastObservation())
                .isSameAs(last);
    }

    private static Response response(int status) {
        return new ResponseBuilder().setStatusCode(status).build();
    }
}
