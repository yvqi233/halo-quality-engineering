package dev.quality.halo.support;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import org.junit.jupiter.api.extension.BeforeEachCallback;
import org.junit.jupiter.api.extension.ExtensionContext;
import org.junit.jupiter.api.extension.TestWatcher;

public final class FailureClassificationExtension implements BeforeEachCallback, TestWatcher {
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final Object WRITE_LOCK = new Object();
    private static final String OUTPUT_PROPERTY = "qe.failureClassificationPath";

    @Override
    public void beforeEach(ExtensionContext context) {
        FailureClassifier.clearResponse();
    }

    @Override
    public void testFailed(ExtensionContext context, Throwable cause) {
        String output = System.getProperty(OUTPUT_PROPERTY);
        if (output == null || output.isBlank()) {
            return;
        }

        ObjectNode record = JSON.createObjectNode();
        record.put("schemaVersion", 1);
        record.put("testId", testId(context));
        record.put("testClass", context.getTestClass().map(Class::getName).orElse("UNKNOWN"));
        record.put("testMethod", context.getTestMethod().map(method -> method.getName()).orElse("UNKNOWN"));
        record.put("failureKind", FailureClassifier.classify(cause, FailureClassifier.currentResponse()).name());
        write(Path.of(output), record);
    }

    private static String testId(ExtensionContext context) {
        String configured = System.getProperty("qe.testId");
        if (configured != null && configured.matches("[A-Z][0-9]{2}")) {
            return configured;
        }
        java.util.regex.Matcher displayId =
                java.util.regex.Pattern.compile("^([A-Z][0-9]{2})\\s").matcher(context.getDisplayName());
        return displayId.find() ? displayId.group(1) : context.getUniqueId();
    }

    private static void write(Path output, ObjectNode record) {
        synchronized (WRITE_LOCK) {
            try {
                Path absolute = output.toAbsolutePath().normalize();
                Files.createDirectories(absolute.getParent());
                Files.writeString(
                        absolute,
                        JSON.writeValueAsString(record) + System.lineSeparator(),
                        StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE,
                        StandardOpenOption.APPEND);
            } catch (IOException error) {
                throw new IllegalStateException("Unable to write JUnit failure classification", error);
            }
        }
    }
}
