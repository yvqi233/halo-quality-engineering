package dev.quality.halo.support;

import static dev.quality.halo.support.FailureClassifier.FailureKind.CONTRACT;
import static dev.quality.halo.support.FailureClassifier.FailureKind.ENVIRONMENT;
import static dev.quality.halo.support.FailureClassifier.FailureKind.PRODUCT;
import static dev.quality.halo.support.FailureClassifier.FailureKind.TEST_TOOL;
import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.core.JsonProcessingException;
import io.restassured.builder.ResponseBuilder;
import io.restassured.response.Response;
import java.net.ConnectException;
import java.util.Optional;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;

class FailureClassifierTest {
    @ParameterizedTest
    @MethodSource("cases")
    void classifiesByEvidence(Throwable error, Integer status, FailureClassifier.FailureKind expected) {
        Optional<Response> response = status == null ? Optional.empty() : Optional.of(response(status));

        assertThat(FailureClassifier.classify(error, response)).isEqualTo(expected);
    }

    static Stream<Arguments> cases() {
        return Stream.of(
                Arguments.arguments(new ConnectException("refused"), null, ENVIRONMENT),
                Arguments.arguments(new IllegalStateException("health check failed"), null, ENVIRONMENT),
                Arguments.arguments(new AssertionError("expected 403 but was 200"), 200, PRODUCT),
                Arguments.arguments(new OpenApiBreakingChangeException("type changed"), null, CONTRACT),
                Arguments.arguments(new JsonProcessingException("bad fixture") {}, null, TEST_TOOL),
                Arguments.arguments(new FixtureCleanupException("cleanup failed"), null, TEST_TOOL));
    }

    @Test
    void neverAssignsFlakyCandidateFromASingleFailure() {
        assertThat(FailureClassifier.classify(new AssertionError("expected 200 but was 500"), Optional.empty()))
                .isEqualTo(TEST_TOOL)
                .isNotEqualTo(FailureClassifier.FailureKind.FLAKY_CANDIDATE);
    }

    @Test
    void givesReceivedProductResponseAssertionPrecedenceOverIncidentalEnvironmentWords() {
        assertThat(FailureClassifier.classify(
                        new AssertionError("health check expected 403 but was 200"), Optional.of(response(200))))
                .isEqualTo(PRODUCT);
    }

    @Test
    void givesFixtureSerializationAndCleanupEvidencePrecedenceOverIncidentalEnvironmentWords() {
        Throwable serialization = new IllegalStateException(
                "wrapper health check failed", new JsonProcessingException("startup fixture") {});
        Throwable cleanup = new IllegalStateException(
                "startup failed", new FixtureCleanupException("fixture cleanup failed"));

        assertThat(FailureClassifier.classify(serialization, Optional.empty())).isEqualTo(TEST_TOOL);
        assertThat(FailureClassifier.classify(cleanup, Optional.empty())).isEqualTo(TEST_TOOL);
    }

    @Test
    void classifiesTypedEnvironmentEvidenceInANestedCause() {
        assertThat(FailureClassifier.classify(
                        new IllegalStateException("wrapper", new ConnectException("refused")), Optional.empty()))
                .isEqualTo(ENVIRONMENT);
    }

    private static Response response(int status) {
        return new ResponseBuilder().setStatusCode(status).build();
    }

    private static final class FixtureCleanupException extends RuntimeException {
        private FixtureCleanupException(String message) {
            super(message);
        }
    }
}
