package dev.quality.halo.support;

import io.restassured.response.Response;
import java.net.ConnectException;
import java.net.SocketException;
import java.net.UnknownHostException;
import java.net.http.HttpTimeoutException;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;

/** Assigns one gate-blocking attribution from the evidence available for a failed test. */
public final class FailureClassifier {
    private FailureClassifier() {}

    public enum FailureKind {
        ENVIRONMENT,
        PRODUCT,
        CONTRACT,
        TEST_TOOL,
        FLAKY_CANDIDATE
    }

    public static FailureKind classify(Throwable error, Optional<Response> response) {
        Objects.requireNonNull(error, "error");
        Objects.requireNonNull(response, "response");

        if (hasCause(error, FailureClassifier::isEnvironmentFailure)) {
            return FailureKind.ENVIRONMENT;
        }
        if (hasCause(error, FailureClassifier::isOpenApiFailure)) {
            return FailureKind.CONTRACT;
        }
        if (hasCause(error, AssertionError.class::isInstance) && response.isPresent()) {
            return FailureKind.PRODUCT;
        }
        return FailureKind.TEST_TOOL;
    }

    private static boolean isEnvironmentFailure(Throwable error) {
        if (error instanceof ConnectException
                || error instanceof SocketException
                || error instanceof UnknownHostException
                || error instanceof HttpTimeoutException) {
            return true;
        }
        String type = error.getClass().getSimpleName().toLowerCase();
        String message = String.valueOf(error.getMessage()).toLowerCase();
        return type.contains("health")
                || type.contains("startup")
                || message.contains("health check")
                || message.contains("failed to start")
                || message.contains("startup failed")
                || message.contains("connection refused");
    }

    private static boolean isOpenApiFailure(Throwable error) {
        String type = error.getClass().getSimpleName().toLowerCase();
        return type.contains("openapi") && (type.contains("breaking") || type.contains("contract"));
    }

    private static boolean hasCause(Throwable error, java.util.function.Predicate<Throwable> predicate) {
        Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        Throwable current = error;
        while (current != null && seen.add(current)) {
            if (predicate.test(current)) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }
}

/** Indicates a breaking difference identified against the reviewed OpenAPI baseline. */
final class OpenApiBreakingChangeException extends RuntimeException {
    OpenApiBreakingChangeException(String message) {
        super(message);
    }
}
