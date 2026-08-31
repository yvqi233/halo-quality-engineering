package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class EvidenceRedactorTest {
    @Test
    void removesCredentialsFromHeadersAndJson() {
        assertThat(EvidenceRedactor.redactHeaders(Map.of(
                "Authorization", List.of("Basic c2VjcmV0"), "X-Run-Id", List.of("r1"))))
                .containsEntry("Authorization", List.of("[REDACTED]"));
        assertThat(EvidenceRedactor.redactJson("{\"password\":\"secret\",\"title\":\"ok\"}"))
                .isEqualTo("{\"password\":\"[REDACTED]\",\"title\":\"ok\"}");
    }
}
