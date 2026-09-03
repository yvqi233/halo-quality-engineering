package dev.quality.halo.posts;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import io.restassured.builder.ResponseBuilder;
import io.restassured.response.Response;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.Test;

class ConcurrentUpdateAwaiterTest {
    @Test
    void readinessTimeoutReleasesWorkersAndCancelsEveryFuture() {
        CountDownLatch ready = new CountDownLatch(1);
        CountDownLatch start = new CountDownLatch(1);
        Future<Response> first = new CompletableFuture<>();
        Future<Response> second = new CompletableFuture<>();

        assertThatThrownBy(() -> ConcurrentUpdateAwaiter.await(
                        ready, start, List.of(first, second), Duration.ofNanos(1)))
                .isInstanceOf(TimeoutException.class)
                .hasMessageContaining("ready");
        assertThat(start.getCount()).isZero();
        assertThat(first.isCancelled()).isTrue();
        assertThat(second.isCancelled()).isTrue();
    }

    @Test
    void responseTimeoutCancelsEveryFuture() {
        CountDownLatch start = new CountDownLatch(1);
        Future<Response> first = new TimedOutFuture();
        Future<Response> second = new CompletableFuture<>();

        assertThatThrownBy(() -> ConcurrentUpdateAwaiter.await(
                        new CountDownLatch(0), start, List.of(first, second), Duration.ofSeconds(1)))
                .isInstanceOf(TimeoutException.class)
                .hasMessageContaining("response");
        assertThat(start.getCount()).isZero();
        assertThat(first.isCancelled()).isTrue();
        assertThat(second.isCancelled()).isTrue();
    }

    @Test
    void returnsEveryCompletedResponse() throws Exception {
        Response first = response(200);
        Response second = response(409);

        List<Response> responses = ConcurrentUpdateAwaiter.await(
                new CountDownLatch(0),
                new CountDownLatch(1),
                List.of(CompletableFuture.completedFuture(first), CompletableFuture.completedFuture(second)),
                Duration.ofSeconds(1));

        assertThat(responses).containsExactly(first, second);
    }

    private static Response response(int status) {
        return new ResponseBuilder().setStatusCode(status).build();
    }

    private static final class TimedOutFuture implements Future<Response> {
        private boolean cancelled;

        @Override
        public boolean cancel(boolean mayInterruptIfRunning) {
            cancelled = true;
            return true;
        }

        @Override
        public boolean isCancelled() {
            return cancelled;
        }

        @Override
        public boolean isDone() {
            return false;
        }

        @Override
        public Response get() {
            throw new AssertionError("Unbounded Future.get() must not be used");
        }

        @Override
        public Response get(long timeout, TimeUnit unit) throws TimeoutException {
            throw new TimeoutException("fixture timeout");
        }
    }
}
