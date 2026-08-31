package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.TimeUnit;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.Test;

class HaloFixtureTest {
    @Test
    void scopesRoleUsersAndDeletesThemInReverseCreationOrder() throws Exception {
        try (MockWebServer server = new MockWebServer()) {
            server.start();
            for (int index = 0; index < 3; index++) {
                server.enqueue(new MockResponse().setResponseCode(200).setBody("{}")
                        .addHeader("Content-Type", "application/json"));
            }
            for (int index = 0; index < 3; index++) {
                server.enqueue(new MockResponse().setResponseCode(200)
                        .setBody("{\"metadata\":{\"version\":7},\"status\":{\"observedVersion\":7}}")
                        .addHeader("Content-Type", "application/json"));
            }
            for (int index = 0; index < 4; index++) {
                server.enqueue(new MockResponse().setResponseCode(200).setBody("{}")
                        .addHeader("Content-Type", "application/json"));
            }
            RunIdentity run = RunIdentity.create(
                    Clock.fixed(Instant.parse("2026-08-31T01:02:03Z"), ZoneOffset.UTC), "fixture");
            HaloFixture.RoleUsers users;
            try (HaloFixture fixture = new HaloFixture(server.url("/").uri(), run)) {
                users = fixture.createRoles();
                assertThat(users.author().username()).startsWith(run.prefix());
                assertThat(users.contributor().username()).startsWith(run.prefix());
                assertThat(users.readonly().username()).startsWith(run.prefix());
                assertThat(fixture.unique("post")).isEqualTo(run.prefix() + "-post");
                fixture.trackPost(fixture.unique("post"));
            }

            java.util.ArrayList<RecordedRequest> requests = new java.util.ArrayList<>();
            for (int index = 0; index < 10; index++) {
                requests.add(server.takeRequest(2, TimeUnit.SECONDS));
            }
            assertThat(requests).allSatisfy(request -> assertThat(request).isNotNull());
            assertThat(requests).extracting(RecordedRequest::getPath).containsExactly(
                    "/apis/api.console.halo.run/v1alpha1/users",
                    "/apis/api.console.halo.run/v1alpha1/users",
                    "/apis/api.console.halo.run/v1alpha1/users",
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post",
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post",
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post",
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post",
                    "/api/v1alpha1/users/" + users.readonly().username(),
                    "/api/v1alpha1/users/" + users.contributor().username(),
                    "/api/v1alpha1/users/" + users.author().username());
        }
    }
}
