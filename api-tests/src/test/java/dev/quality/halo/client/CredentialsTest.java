package dev.quality.halo.client;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class CredentialsTest {
    @Test
    void doesNotRenderThePassword() {
        Credentials credentials = new Credentials("account", "not-for-logs");

        assertThat(credentials).hasToString("Credentials[username=account, password=[REDACTED]]");
        assertThat(credentials.toString()).doesNotContain("not-for-logs");
    }
}
