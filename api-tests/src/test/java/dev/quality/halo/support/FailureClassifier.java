package dev.quality.halo.support;

import com.fasterxml.jackson.core.JsonProcessingException;
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
import java.util.Locale;

/** Assigns one gate-blocking attribution from the evidence available for a failed test. */
public final class FailureClassifier {
    private static final ThreadLocal<Response> LAST_RESPONSE = new ThreadLocal<>();

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

        if (hasRelated(error, FailureClassifier::isOpenApiFailure)) {
            return FailureKind.CONTRACT;
        }
        if (hasRelated(error, FailureClassifier::isTestToolFailure)) {
            return FailureKind.TEST_TOOL;
        }
        if (hasRelated(error, FailureClassifier::isTypedEnvironmentFailure)) {
            return FailureKind.ENVIRONMENT;
        }
        if (hasRelated(error, AssertionError.class::isInstance) && response.isPresent()) {
            return FailureKind.PRODUCT;
        }
        if (hasRelated(error, FailureClassifier::hasEnvironmentMessage)) {
            return FailureKind.ENVIRONMENT;
        }
        return FailureKind.TEST_TOOL;
    }

    public static void observeResponse(Response response) {
        LAST_RESPONSE.set(Objects.requireNonNull(response, "response"));
    }

    static Optional<Response> currentResponse() {
        return Optional.ofNullable(LAST_RESPONSE.get());
    }

    static void clearResponse() {
        LAST_RESPONSE.remove();
    }

    private static boolean isTypedEnvironmentFailure(Throwable error) {
        return error instanceof ConnectException
                || error instanceof SocketException
                || error instanceof UnknownHostException
                || error instanceof HttpTimeoutException;
    }

    private static boolean hasEnvironmentMessage(Throwable error) {
        String message = String.valueOf(error.getMessage()).toLowerCase(Locale.ROOT);
        return message.contains("health check")
                || message.contains("failed to start")
                || message.contains("startup failed")
                || message.contains("connection refused");
    }

    private static boolean isOpenApiFailure(Throwable error) {
        String type = error.getClass().getSimpleName().toLowerCase(Locale.ROOT);
        return type.contains("openapi") && (type.contains("breaking") || type.contains("contract"));
    }

    private static boolean isTestToolFailure(Throwable error) {
        if (error instanceof JsonProcessingException) {
            return true;
        }
        String type = error.getClass().getSimpleName().toLowerCase(Locale.ROOT);
        return type.contains("fixture") || type.contains("cleanup");
    }

    private static boolean hasRelated(Throwable error, java.util.function.Predicate<Throwable> predicate) {
        Set<Throwable> seen = Collections.newSetFromMap(new IdentityHashMap<>());
        java.util.ArrayDeque<Throwable> pending = new java.util.ArrayDeque<>();
        pending.add(error);
        while (!pending.isEmpty()) {
            Throwable current = pending.removeFirst();
            if (!seen.add(current)) {
                continue;
            }
            if (predicate.test(current)) {
                return true;
            }
            if (current.getCause() != null) {
                pending.addLast(current.getCause());
            }
            for (Throwable suppressed : current.getSuppressed()) {
                pending.addLast(suppressed);
            }
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
