package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class StabilityRecordTest {
    @Test
    void requiresTwentyConsecutiveGreenRuns() throws Exception {
        var records = StabilityRecord.read(Path.of("src/test/resources/stability/nineteen-green.jsonl"));
        assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isFalse();
        records = StabilityRecord.read(Path.of("src/test/resources/stability/twenty-green.jsonl"));
        assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isTrue();
    }

    @Test
    void rejectsRecordsOutsideTheSevenFieldInterface(@TempDir Path tempDirectory) throws Exception {
        Path record = tempDirectory.resolve("extra-field.jsonl");
        Files.writeString(record, """
                {"sequence":1,"startedAt":"2026-09-01T00:00:01Z","commit":"04379a211124cd52f7a2d08920dd0866fe24ed55","haloImage":"halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9","result":"PASS","durationSeconds":1.001,"failureKind":"NONE","attempt":2}
                """);

        assertThatThrownBy(() -> StabilityRecord.read(record))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("exactly");
    }

    @Test
    void sequenceMustRestartAtOneBeforeAQualifyingRun() throws Exception {
        var records = StabilityRecord.read(Path.of("src/test/resources/stability/twenty-green.jsonl"));
        var shifted = records.stream()
                .map(record -> new StabilityRecord(
                        record.sequence() + 1,
                        record.startedAt(),
                        record.commit(),
                        record.haloImage(),
                        record.result(),
                        record.durationSeconds(),
                        record.failureKind()))
                .toList();

        assertThat(StabilityRecord.hasConsecutiveGreen(shifted, 20)).isFalse();
    }

    @Test
    void rejectsFailureAfterTwentyGreenRuns() throws Exception {
        var records = new ArrayList<>(
                StabilityRecord.read(Path.of("src/test/resources/stability/twenty-green.jsonl")));
        records.add(new StabilityRecord(
                21,
                "2026-09-01T00:00:21Z",
                "04379a211124cd52f7a2d08920dd0866fe24ed55",
                "halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9",
                "FAIL",
                1.021,
                "PRODUCT"));

        assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isFalse();
    }

    @Test
    void rejectsTwentyOneGreenRuns() throws Exception {
        var records = new ArrayList<>(
                StabilityRecord.read(Path.of("src/test/resources/stability/twenty-green.jsonl")));
        records.add(new StabilityRecord(
                21,
                "2026-09-01T00:00:21Z",
                "04379a211124cd52f7a2d08920dd0866fe24ed55",
                "halohub/halo@sha256:37d0de36041e7da32a1f2d4ea02aa18f2f0e2757949d59e2e2659fac734f5ab9",
                "PASS",
                1.021,
                "NONE"));

        assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isFalse();
    }
}
