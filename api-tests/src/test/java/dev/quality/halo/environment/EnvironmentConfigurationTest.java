package dev.quality.halo.environment;

import static org.assertj.core.api.Assertions.assertThat;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

class EnvironmentConfigurationTest {
    @Test
    void sizesAuthenticationRateLimiterForRepeatedScenarioMatrix() throws Exception {
        String compose = Files.readString(Path.of("..", "environment", "docker-compose.yml"));

        assertThat(compose).contains(
                "RESILIENCE4J_RATELIMITER_CONFIGS_AUTHENTICATION_LIMITFORPERIOD: \"100\"");
        assertThat(compose).doesNotContain(
                "RESILIENCE4J_RATELIMITER_CONFIGS_AUTHENTICATION_LIMITREFRESHPERIOD",
                "RESILIENCE4J_RATELIMITER_CONFIGS_AUTHENTICATION_TIMEOUTDURATION");
    }
}
