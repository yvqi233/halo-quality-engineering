package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;

import java.security.KeyPairGenerator;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.concurrent.TimeUnit;
import okhttp3.mockwebserver.Dispatcher;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.Test;

class HaloFixtureTest {
    @Test
    void scopesRoleUsersAndDeletesThemInReverseCreationOrder() throws Exception {
        try (MockWebServer server = new MockWebServer()) {
            server.start();
            server.setDispatcher(fixtureDispatcher(true, 200));
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

            List<RecordedRequest> requests = domainRequests(server);
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

    @Test
    void settlingFailuresDoNotPreventReverseCleanupAndRemainSeparateFromDeletionFailures() throws Exception {
        try (MockWebServer server = new MockWebServer()) {
            server.start();
            server.setDispatcher(fixtureDispatcher(false, 500));
            RunIdentity run = RunIdentity.create(
                    Clock.fixed(Instant.parse("2026-08-31T01:02:03Z"), ZoneOffset.UTC), "cleanup");
            HaloFixture fixture = new HaloFixture(
                    server.url("/").uri(), run, Duration.ofNanos(1), Duration.ofNanos(1));
            HaloFixture.RoleUsers users = fixture.createRoles();
            fixture.trackPost(fixture.unique("post-a"));
            fixture.trackPost(fixture.unique("post-b"));

            AssertionError original = org.assertj.core.api.Assertions.catchThrowableOfType(() -> {
                try (fixture) {
                    throw new AssertionError("original test failure");
                }
            }, AssertionError.class);
            assertThat(original).hasMessage("original test failure");
            assertThat(original.getSuppressed()).hasSize(1);
            assertThat(original.getSuppressed()[0]).isInstanceOf(HaloFixture.CleanupException.class);
            HaloFixture.CleanupException failure = (HaloFixture.CleanupException) original.getSuppressed()[0];

            assertThat(failure.settlingFailures()).extracting(HaloFixture.CleanupIssue::resourceName)
                    .containsExactly(run.prefix() + "-post-a", run.prefix() + "-post-b");
            assertThat(failure.deletionFailures()).extracting(HaloFixture.CleanupIssue::resourceName)
                    .containsExactly(run.prefix() + "-post-b", run.prefix() + "-post-a", users.readonly().username(),
                            users.contributor().username(), users.author().username());
            assertThat(failure.getSuppressed()).hasSize(7);

            List<RecordedRequest> requests = domainRequests(server);
            assertThat(requests).allSatisfy(request -> assertThat(request).isNotNull());
            assertThat(requests.subList(5, 10)).extracting(RecordedRequest::getPath).containsExactly(
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post-b",
                    "/apis/content.halo.run/v1alpha1/posts/" + run.prefix() + "-post-a",
                    "/api/v1alpha1/users/" + users.readonly().username(),
                    "/api/v1alpha1/users/" + users.contributor().username(),
                    "/api/v1alpha1/users/" + users.author().username());
        }
    }

    private static Dispatcher fixtureDispatcher(boolean settled, int deleteStatus) throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        String publicKey = Base64.getEncoder().encodeToString(generator.generateKeyPair().getPublic().getEncoded());
        String loginPage = """
                <script>const publicKey = "%s";</script>
                <input type="hidden" name="_csrf" value="csrf-value"/>
                """.formatted(publicKey);
        return new Dispatcher() {
            @Override
            public MockResponse dispatch(RecordedRequest request) {
                String path = request.getPath();
                if (path.equals("/login") && request.getMethod().equals("GET")) {
                    return new MockResponse().setResponseCode(200).setBody(loginPage);
                }
                if (path.equals("/login") && request.getMethod().equals("POST")) {
                    return new MockResponse().setResponseCode(302).addHeader("Location", "/")
                            .addHeader("Set-Cookie", "SESSION=session-value; Path=/");
                }
                if (path.equals("/apis/uc.api.halo.run/v1alpha1/users/-")) {
                    return json(200, "{\"name\":\"qe-admin\"}");
                }
                if (request.getMethod().equals("DELETE")) {
                    return json(deleteStatus, "{}");
                }
                if (request.getMethod().equals("GET") && path.contains("/posts/")) {
                    int observedVersion = settled ? 7 : 6;
                    return json(200, "{\"metadata\":{\"version\":7},\"status\":{\"observedVersion\":"
                            + observedVersion + "}}");
                }
                return json(200, "{}");
            }
        };
    }

    private static MockResponse json(int status, String body) {
        return new MockResponse().setResponseCode(status).setBody(body)
                .addHeader("Content-Type", "application/json");
    }

    private static List<RecordedRequest> domainRequests(MockWebServer server) throws InterruptedException {
        List<RecordedRequest> requests = new ArrayList<>();
        int count = server.getRequestCount();
        for (int index = 0; index < count; index++) {
            RecordedRequest request = server.takeRequest(2, TimeUnit.SECONDS);
            assertThat(request).isNotNull();
            if (!request.getPath().startsWith("/login")
                    && !request.getPath().equals("/apis/uc.api.halo.run/v1alpha1/users/-")) {
                requests.add(request);
            }
        }
        return List.copyOf(requests);
    }
}
