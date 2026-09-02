package dev.quality.halo.support;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public record StabilityRecord(
        int sequence,
        String startedAt,
        String commit,
        String haloImage,
        String result,
        double durationSeconds,
        String failureKind) {
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();
    private static final Set<String> FIELDS = Set.of(
            "sequence", "startedAt", "commit", "haloImage", "result", "durationSeconds", "failureKind");
    private static final Set<String> FAILURE_KINDS =
            Set.of("NONE", "ENVIRONMENT", "PRODUCT", "CONTRACT", "TEST_TOOL", "FLAKY_CANDIDATE");

    public static List<StabilityRecord> read(Path path) throws IOException {
        List<StabilityRecord> records = new ArrayList<>();
        int lineNumber = 0;
        for (String line : Files.readAllLines(path, StandardCharsets.UTF_8)) {
            lineNumber++;
            if (line.isBlank()) {
                throw invalid(lineNumber, "blank records are not allowed");
            }
            try {
                JsonNode node = OBJECT_MAPPER.readTree(line);
                if (!node.isObject()) {
                    throw invalid(lineNumber, "record must be a JSON object");
                }
                Set<String> actualFields = new HashSet<>();
                node.fieldNames().forEachRemaining(actualFields::add);
                if (!actualFields.equals(FIELDS)) {
                    throw invalid(lineNumber, "record must contain exactly " + FIELDS);
                }
                StabilityRecord record = OBJECT_MAPPER.treeToValue(node, StabilityRecord.class);
                validate(record, lineNumber);
                records.add(record);
            } catch (IllegalArgumentException error) {
                throw error;
            } catch (Exception error) {
                throw invalid(lineNumber, "invalid JSON", error);
            }
        }
        return List.copyOf(records);
    }

    public static boolean hasConsecutiveGreen(List<StabilityRecord> records, int requiredRuns) {
        if (requiredRuns < 1) {
            throw new IllegalArgumentException("requiredRuns must be positive");
        }
        if (records.size() != requiredRuns) {
            return false;
        }
        for (int index = 0; index < records.size(); index++) {
            StabilityRecord record = records.get(index);
            if (!record.result.equals("PASS")
                    || !record.failureKind.equals("NONE")
                    || record.sequence != index + 1) {
                return false;
            }
        }
        return true;
    }

    private static void validate(StabilityRecord record, int lineNumber) {
        if (record.sequence < 1) {
            throw invalid(lineNumber, "sequence must be positive");
        }
        try {
            OffsetDateTime.parse(record.startedAt);
        } catch (NullPointerException | DateTimeParseException error) {
            throw invalid(lineNumber, "startedAt must be an ISO-8601 timestamp", error);
        }
        if (record.commit == null || !record.commit.matches("[0-9a-f]{40}")) {
            throw invalid(lineNumber, "commit must be a full lowercase Git SHA");
        }
        if (record.haloImage == null || !record.haloImage.matches(".+@sha256:[0-9a-f]{64}")) {
            throw invalid(lineNumber, "haloImage must be digest-pinned");
        }
        if (!Set.of("PASS", "FAIL").contains(record.result)) {
            throw invalid(lineNumber, "result must be PASS or FAIL");
        }
        if (!Double.isFinite(record.durationSeconds) || record.durationSeconds < 0) {
            throw invalid(lineNumber, "durationSeconds must be finite and non-negative");
        }
        if (!FAILURE_KINDS.contains(record.failureKind)) {
            throw invalid(lineNumber, "failureKind is unsupported");
        }
        if (record.result.equals("PASS") != record.failureKind.equals("NONE")) {
            throw invalid(lineNumber, "PASS requires NONE and FAIL requires a failure kind");
        }
    }

    private static IllegalArgumentException invalid(int lineNumber, String message) {
        return new IllegalArgumentException("Invalid stability record at line " + lineNumber + ": " + message);
    }

    private static IllegalArgumentException invalid(int lineNumber, String message, Exception cause) {
        return new IllegalArgumentException(
                "Invalid stability record at line " + lineNumber + ": " + message, cause);
    }
}
