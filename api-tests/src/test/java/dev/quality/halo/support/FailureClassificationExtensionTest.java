package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.platform.engine.discovery.DiscoverySelectors.selectClass;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.restassured.builder.ResponseBuilder;
import java.net.ConnectException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.junit.platform.launcher.core.LauncherDiscoveryRequestBuilder;
import org.junit.platform.launcher.core.LauncherFactory;
import org.junit.platform.launcher.listeners.SummaryGeneratingListener;

class FailureClassificationExtensionTest {
    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    void emitsMachineReadableKindsFromTheRealJunitFailurePath(@TempDir Path tempDirectory) throws Exception {
        Path output = tempDirectory.resolve("classification.jsonl");
        String property = "qe.failureClassificationPath";
        String previous = System.getProperty(property);
        try {
            System.setProperty(property, output.toString());
            var request = LauncherDiscoveryRequestBuilder.request()
                    .selectors(
                            selectClass(ProductFailureProbe.class),
                            selectClass(EnvironmentFailureProbe.class),
                            selectClass(ContractFailureProbe.class),
                            selectClass(FixtureFailureProbe.class))
                    .configurationParameter("junit.jupiter.extensions.autodetection.enabled", "true")
                    .build();
            var summary = new SummaryGeneratingListener();
            var launcher = LauncherFactory.create();
            launcher.registerTestExecutionListeners(summary);

            launcher.execute(request);

            assertThat(summary.getSummary().getTestsFailedCount()).isEqualTo(4);
            List<JsonNode> records = Files.readAllLines(output).stream().map(FailureClassificationExtensionTest::json).toList();
            assertThat(records).hasSize(4);
            assertThat(records)
                    .allSatisfy(record -> assertThat(fieldNames(record))
                            .containsExactlyInAnyOrder(
                                    "schemaVersion", "testId", "testClass", "testMethod", "failureKind"));
            assertThat(records).extracting(record -> record.path("failureKind").asText())
                    .containsExactlyInAnyOrder("PRODUCT", "ENVIRONMENT", "CONTRACT", "TEST_TOOL");
        } finally {
            if (previous == null) {
                System.clearProperty(property);
            } else {
                System.setProperty(property, previous);
            }
        }
    }

    private static JsonNode json(String line) {
        try {
            return JSON.readTree(line);
        } catch (Exception error) {
            throw new AssertionError("Invalid classification JSON", error);
        }
    }

    private static Set<String> fieldNames(JsonNode node) {
        Set<String> names = new java.util.HashSet<>();
        node.fieldNames().forEachRemaining(names::add);
        return names;
    }

    @Tag("classification-probe")
    static class ProductFailureProbe {
        @Test
        void productFailure() {
            FailureClassifier.observeResponse(new ResponseBuilder().setStatusCode(200).build());
            throw new AssertionError("expected 403 but was 200");
        }
    }

    @Tag("classification-probe")
    static class EnvironmentFailureProbe {
        @Test
        void environmentFailure() {
            throw new IllegalStateException("request failed", new ConnectException("refused"));
        }
    }

    @Tag("classification-probe")
    static class ContractFailureProbe {
        @Test
        void contractFailure() {
            throw new OpenApiBreakingChangeException("property removed");
        }
    }

    @Tag("classification-probe")
    static class FixtureFailureProbe {
        @Test
        void fixtureFailure() {
            throw new FixtureExecutionException("fixture serialization failed");
        }
    }

    private static final class FixtureExecutionException extends RuntimeException {
        private FixtureExecutionException(String message) {
            super(message);
        }
    }
}
