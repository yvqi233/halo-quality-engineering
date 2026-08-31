package dev.quality.halo.client;

import static org.assertj.core.api.Assertions.assertThat;

import dev.quality.halo.support.HaloFixture;
import dev.quality.halo.support.RunIdentity;
import java.net.URI;
import java.time.Clock;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

@Tag("integration")
class HaloApiContractIT {
    @Test
    void createsReadableScopedRoleUsersAndCleansThemUpInReverseOrder() {
        RunIdentity run = RunIdentity.create(Clock.systemUTC(), "contract");
        System.setProperty("qe.runId", run.runId());
        System.setProperty("qe.testId", "halo-api-contract");
        try (HaloFixture fixture = new HaloFixture(URI.create("http://127.0.0.1:8090"), run)) {
            HaloFixture.RoleUsers users = fixture.createRoles();
            assertThat(users.author().username()).startsWith(run.prefix());
            assertThat(users.readonly().username()).startsWith(run.prefix());
            assertThat(users.author().username()).isNotEqualTo(users.readonly().username());

            new HaloApi(URI.create("http://127.0.0.1:8090"), users.author())
                    .currentUser().then().statusCode(200);
            new HaloApi(URI.create("http://127.0.0.1:8090"), users.readonly())
                    .currentUser().then().statusCode(200);
        } finally {
            System.clearProperty("qe.runId");
            System.clearProperty("qe.testId");
        }
    }
}
