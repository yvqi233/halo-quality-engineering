package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

class RunIdentityTest {
    @Test
    void createsSafeDistinctPrefixesForParallelWorkers() {
        Clock fixed = Clock.fixed(Instant.parse("2026-08-31T01:02:03Z"), ZoneOffset.UTC);
        RunIdentity first = RunIdentity.create(fixed, "chromium-1");
        RunIdentity second = RunIdentity.create(fixed, "firefox-2");

        assertThat(first.prefix()).matches("qe-20260831t010203z-chromium-1-[0-9a-f]{8}");
        assertThat(second.prefix()).matches("qe-20260831t010203z-firefox-2-[0-9a-f]{8}");
        assertThat(first.prefix()).isNotEqualTo(second.prefix());
    }
}
