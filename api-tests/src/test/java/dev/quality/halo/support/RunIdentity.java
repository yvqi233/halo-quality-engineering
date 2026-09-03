package dev.quality.halo.support;

import java.time.Clock;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.UUID;

public record RunIdentity(String runId, String workerId) {
    private static final DateTimeFormatter FORMAT =
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);

    public static RunIdentity create(Clock clock, String workerId) {
        String safeWorker = workerId.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9-]", "-");
        String run = FORMAT.format(clock.instant()).toLowerCase(Locale.ROOT);
        String suffix = UUID.randomUUID().toString().substring(0, 8);
        return new RunIdentity(run + "-" + suffix, safeWorker);
    }

    public String prefix() {
        String suffix = runId.substring(runId.lastIndexOf('-') + 1);
        String timestamp = runId.substring(0, runId.length() - suffix.length() - 1);
        return "qe-" + timestamp + "-" + workerId + "-" + suffix;
    }
}
