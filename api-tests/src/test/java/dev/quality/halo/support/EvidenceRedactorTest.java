package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class EvidenceRedactorTest {
    @Test
    void removesCredentialsFromHeadersAndJson() {
        var headers = EvidenceRedactor.redactHeaders(Map.of(
                "Authorization", List.of("Basic c2VjcmV0"),
                "cOoKiE", List.of("session=secret"),
                "SET-cookie", List.of("session=secret"),
                "X-Run-Id", List.of("r1")));

        assertThat(headers)
                .containsEntry("Authorization", List.of("[REDACTED]"))
                .containsEntry("cOoKiE", List.of("[REDACTED]"))
                .containsEntry("SET-cookie", List.of("[REDACTED]"))
                .containsEntry("X-Run-Id", List.of("r1"));
        assertThat(EvidenceRedactor.redactJson(
                        "{\"password\":\"secret\",\"nested\":{\"TOKEN\":\"secret\",\"StOrAgEsTaTe\":{\"cookies\":[\"secret\"]}},\"items\":[{\"Cookie\":\"secret\"},{\"Set-Cookie\":\"secret\"}],\"title\":\"ok\"}"))
                .isEqualTo(
                        "{\"password\":\"[REDACTED]\",\"nested\":{\"TOKEN\":\"[REDACTED]\",\"StOrAgEsTaTe\":\"[REDACTED]\"},\"items\":[{\"Cookie\":\"[REDACTED]\"},{\"Set-Cookie\":\"[REDACTED]\"}],\"title\":\"ok\"}");
    }
}
