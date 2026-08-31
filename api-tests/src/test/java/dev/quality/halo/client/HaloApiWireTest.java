package dev.quality.halo.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.quality.halo.support.ResourceRef;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import okhttp3.mockwebserver.MockResponse;
import okhttp3.mockwebserver.MockWebServer;
import okhttp3.mockwebserver.RecordedRequest;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class HaloApiWireTest {
    private final ObjectMapper json = new ObjectMapper();
    private MockWebServer server;

    @BeforeEach
    void startServer() throws Exception {
        server = new MockWebServer();
        server.start();
    }

    @AfterEach
    void stopServer() throws Exception {
        server.shutdown();
    }

    @Test
    void sendsEveryRequiredOperationWithExactRoutesAndPayloads() throws Exception {
        for (int index = 0; index < 26; index++) {
            server.enqueue(jsonResponse(200));
        }
        HaloApi api = api();

        api.createUser("user-a", "user-a@example.test", "user-password", Set.of("role-b", "role-a"));
        api.grantRoles("user-a", Set.of("role-b", "role-a"));
        api.disableUser("user-a");
        api.enableUser("user-a");
        api.draftPost("p1", "user-a", "Title", "title");
        api.ownDraftPost("p2", "user-a", "Own title", "own-title");
        api.ownPublishPost("p2");
        api.ownPost("p2");
        api.ownUpdatePost("p2", json.readTree("{\"metadata\":{\"name\":\"p2\",\"version\":2},\"spec\":{}}"));
        api.publishPost("has space");
        api.unpublishPost("p1");
        api.recyclePost("p1");
        api.consolePost("p1");
        api.publicPost("p1");
        api.headContent("p1");
        api.updatePost("p1", json.readTree("{\"metadata\":{\"version\":3}}"));
        api.postsByName("p1");
        api.publicPosts();
        api.devicesFor("user-a");
        api.snapshot("snapshot-1");
        api.permalink(server.url("/archives/p1").toString());
        api.deleteExtension(new ResourceRef("content.halo.run", "v1alpha1", "posts", "p1"));
        api.currentUser();
        api.unauthenticatedUser();
        api.unauthenticatedDraftPost("p3", "user-a", "Missing auth", "missing-auth");
        api.deleteUser("user-a");

        List<RecordedRequest> requests = take(26);
        assertThat(requests).extracting(RecordedRequest::getMethod).containsExactly(
                "POST", "POST", "POST", "POST", "POST", "POST", "PUT", "GET", "PUT", "PUT", "PUT", "PUT",
                "GET", "GET", "GET", "PUT", "GET", "GET", "GET", "GET", "GET", "DELETE", "GET", "GET", "POST",
                "DELETE");
        assertThat(requests).extracting(RecordedRequest::getPath).containsExactly(
                "/apis/api.console.halo.run/v1alpha1/users",
                "/apis/api.console.halo.run/v1alpha1/users/user-a/permissions",
                "/apis/console.api.security.halo.run/v1alpha1/users/user-a/disable",
                "/apis/console.api.security.halo.run/v1alpha1/users/user-a/enable",
                "/apis/api.console.halo.run/v1alpha1/posts",
                "/apis/uc.api.content.halo.run/v1alpha1/posts",
                "/apis/uc.api.content.halo.run/v1alpha1/posts/p2/publish",
                "/apis/uc.api.content.halo.run/v1alpha1/posts/p2",
                "/apis/uc.api.content.halo.run/v1alpha1/posts/p2",
                "/apis/api.console.halo.run/v1alpha1/posts/has%20space/publish",
                "/apis/api.console.halo.run/v1alpha1/posts/p1/unpublish",
                "/apis/api.console.halo.run/v1alpha1/posts/p1/recycle",
                "/apis/content.halo.run/v1alpha1/posts/p1",
                "/apis/api.content.halo.run/v1alpha1/posts/p1",
                "/apis/api.console.halo.run/v1alpha1/posts/p1/head-content",
                "/apis/api.console.halo.run/v1alpha1/posts/p1",
                "/apis/api.console.halo.run/v1alpha1/posts?fieldSelector=metadata.name%3D%3Dp1",
                "/apis/api.content.halo.run/v1alpha1/posts?size=100",
                "/apis/security.halo.run/v1alpha1/devices?fieldSelector=spec.principalName%3D%3Duser-a",
                "/apis/content.halo.run/v1alpha1/snapshots/snapshot-1",
                "/archives/p1",
                "/apis/content.halo.run/v1alpha1/posts/p1",
                "/apis/api.console.halo.run/v1alpha1/users/-",
                "/apis/uc.api.halo.run/v1alpha1/users/-",
                "/apis/api.console.halo.run/v1alpha1/posts",
                "/api/v1alpha1/users/user-a");

        JsonNode user = json.readTree(requests.getFirst().getBody().readUtf8());
        assertThat(user).isEqualTo(json.readTree("""
                {"name":"user-a","displayName":"user-a","email":"user-a@example.test",
                 "password":"user-password","roles":["role-a","role-b"]}
                """));
        assertThat(json.readTree(requests.get(1).getBody().readUtf8()))
                .isEqualTo(json.readTree("{\"roles\":[\"role-a\",\"role-b\"]}"));

        JsonNode post = json.readTree(requests.get(4).getBody().readUtf8());
        assertThat(post.at("/post/apiVersion").asText()).isEqualTo("content.halo.run/v1alpha1");
        assertThat(post.at("/post/kind").asText()).isEqualTo("Post");
        assertThat(post.at("/post/metadata/name").asText()).isEqualTo("p1");
        assertThat(post.at("/post/spec/title").asText()).isEqualTo("Title");
        assertThat(post.at("/post/spec/slug").asText()).isEqualTo("title");
        assertThat(post.at("/post/spec/owner").asText()).isEqualTo("user-a");
        assertThat(post.at("/post/spec/deleted").asBoolean()).isFalse();
        assertThat(post.at("/post/spec/publish").asBoolean()).isFalse();
        assertThat(post.at("/post/spec/pinned").asBoolean()).isFalse();
        assertThat(post.at("/post/spec/allowComment").asBoolean()).isTrue();
        assertThat(post.at("/post/spec/visible").asText()).isEqualTo("PUBLIC");
        assertThat(post.at("/post/spec/priority").asInt()).isZero();
        assertThat(post.at("/post/spec/excerpt/autoGenerate").asBoolean()).isTrue();
        JsonNode excerptRaw = post.at("/post/spec/excerpt/raw");
        assertThat(excerptRaw.isMissingNode()).isFalse();
        assertThat(excerptRaw.isTextual()).isTrue();
        assertThat(excerptRaw.textValue()).isEqualTo("");
        assertThat(post.at("/post/spec/categories").isArray()).isTrue();
        assertThat(post.at("/post/spec/tags").isArray()).isTrue();
        assertThat(post.at("/post/spec/htmlMetas").isArray()).isTrue();
        assertThat(post.at("/content/raw").asText()).isEqualTo("<p>Title</p>");
        assertThat(post.at("/content/content").asText()).isEqualTo("<p>Title</p>");
        assertThat(post.at("/content/rawType").asText()).isEqualTo("HTML");
        JsonNode ownPost = json.readTree(requests.get(5).getBody().readUtf8());
        assertThat(ownPost.at("/metadata/name").asText()).isEqualTo("p2");
        assertThat(ownPost.at("/spec/title").asText()).isEqualTo("Own title");
        assertThat(json.readTree(ownPost.at("/metadata/annotations/content.halo.run~1content-json").asText()))
                .isEqualTo(json.readTree("{\"raw\":\"<p>Own title</p>\",\"content\":\"<p>Own title</p>\",\"rawType\":\"HTML\"}"));
        assertThat(json.readTree(requests.get(15).getBody().readUtf8()).at("/metadata/version").asInt()).isEqualTo(3);
        assertThat(requests.get(23).getHeader("Authorization")).isNull();
        assertThat(requests.get(24).getHeader("Authorization")).isNull();
        assertThat(requests.get(23).getHeader("X-Requested-With")).isEqualTo("XMLHttpRequest");
    }

    @Test
    void establishesSessionBeforeProtectedIdentityAndAssertsPrincipalSurface() throws Exception {
        String runId = "wire-" + UUID.randomUUID();
        server.enqueue(loginPage());
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/")
                .addHeader("Set-Cookie", "SESSION=session-value; Path=/"));
        server.enqueue(new MockResponse().setResponseCode(200)
                .addHeader("Content-Type", "application/json")
                .setBody("{\"name\":\"account\",\"passwordSet\":true}"));

        HaloApi api = new HaloApi(server.url("/").uri(), new Credentials("account", "password-value"), runId, "identity");
        api.authenticatedUser().then().statusCode(200).body("name", org.hamcrest.Matchers.equalTo("account"));

        List<RecordedRequest> requests = take(3);
        assertThat(requests).extracting(RecordedRequest::getPath)
                .containsExactly("/login", "/login", "/apis/uc.api.halo.run/v1alpha1/users/-");
        assertThat(requests.get(2).getHeader("Cookie")).isNotBlank();
        assertThat(requests.get(2).getHeader("X-Requested-With")).isEqualTo("XMLHttpRequest");
        assertThat(Files.list(HaloApi.evidenceDirectory(runId, "identity")).toList()).hasSize(2);
    }

    @Test
    void retriesOnlyAllowlistedConsoleMutationAndWritesSeparateRedactedEvidenceForBothAttempts() throws Exception {
        String runId = "wire-" + UUID.randomUUID();
        String testId = "retry";
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/login?authentication_required"));
        server.enqueue(loginPage());
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/")
                .addHeader("Set-Cookie", "SESSION=session-value; Path=/"));
        server.enqueue(jsonResponse(200));

        HaloApi api = new HaloApi(server.url("/").uri(), new Credentials("account", "password-value"), runId, testId);
        api.draftPost("p1", "account", "Title", "title").then().statusCode(200);

        List<RecordedRequest> requests = take(4);
        assertThat(requests).extracting(RecordedRequest::getPath)
                .containsExactly("/apis/api.console.halo.run/v1alpha1/posts", "/login", "/login",
                        "/apis/api.console.halo.run/v1alpha1/posts");
        assertThat(requests.get(3).getHeader("Cookie")).isNotBlank();

        List<Path> evidence = Files.list(HaloApi.evidenceDirectory(runId, testId)).toList();
        assertThat(evidence).hasSize(4);
        List<JsonNode> records = evidence.stream().map(this::read).toList();
        Map<Boolean, Integer> attemptStatuses = evidence.stream()
                .filter(path -> path.getFileName().toString().endsWith("-request.json"))
                .collect(java.util.stream.Collectors.toMap(
                        path -> read(path).at("/headers/Cookie/0").asText().equals("[REDACTED]"),
                        path -> read(HaloApi.evidenceDirectory(runId, testId).resolve(path.getFileName().toString()
                                        .replace("-request.json", "-response.json")))
                                .at("/statusCode").asInt()));
        assertThat(attemptStatuses).containsEntry(false, 302).containsEntry(true, 200);
        assertThat(records).allSatisfy(record -> assertThat(record.toString())
                .doesNotContain("password-value", "session-value"));
    }

    @Test
    void leavesReadsAndUnlistedRedirectsUntouched() throws Exception {
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/login?authentication_required"));
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/login?authentication_required"));
        server.enqueue(new MockResponse().setResponseCode(302).addHeader("Location", "/login?authentication_required"));
        HaloApi api = api();

        assertThat(api.currentUser().statusCode()).isEqualTo(302);
        assertThat(api.consolePost("p1").statusCode()).isEqualTo(302);
        assertThat(api.deleteExtension(new ResourceRef("content.halo.run", "v1alpha1", "posts", "p1")).statusCode())
                .isEqualTo(302);

        assertThat(take(3)).extracting(RecordedRequest::getPath).containsExactly(
                "/apis/api.console.halo.run/v1alpha1/users/-", "/apis/content.halo.run/v1alpha1/posts/p1",
                "/apis/content.halo.run/v1alpha1/posts/p1");
        assertThat(server.takeRequest(100, TimeUnit.MILLISECONDS)).isNull();
    }

    @Test
    void writesParseableNonCollidingEvidenceAcrossConcurrentClients() throws Exception {
        String runId = "wire-" + UUID.randomUUID();
        String testId = "concurrent";
        int clients = 8;
        for (int index = 0; index < clients; index++) {
            server.enqueue(jsonResponse(200));
        }
        ExecutorService executor = Executors.newFixedThreadPool(clients);
        try {
            for (int index = 0; index < clients; index++) {
                int request = index;
                executor.submit(() -> new HaloApi(server.url("/").uri(), new Credentials("account", "password"), runId, testId)
                        .draftPost("p" + request, "account", "Title", "title"));
            }
        } finally {
            executor.shutdown();
        }
        assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue();
        assertThat(take(clients)).hasSize(clients);

        List<Path> evidence = Files.list(HaloApi.evidenceDirectory(runId, testId)).toList();
        assertThat(evidence).hasSize(clients * 2);
        assertThat(evidence).extracting(path -> path.getFileName().toString()).doesNotHaveDuplicates();
        evidence.forEach(path -> assertThat(read(path).isObject()).isTrue());
    }

    @Test
    void rejectsTraversalSegmentsAndKeepsEvidenceUnderTheEvidenceRoot() {
        assertThatThrownBy(() -> HaloApi.evidenceDirectory("..", "test"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> HaloApi.evidenceDirectory("run", "../test"))
                .isInstanceOf(IllegalArgumentException.class);

        Path directory = HaloApi.evidenceDirectory("safe/run", "safe\\test");
        assertThat(directory.startsWith(HaloApi.evidenceRoot())).isTrue();
    }

    private HaloApi api() {
        return new HaloApi(server.url("/").uri(), new Credentials("qe-admin", "HaloQE!2026"));
    }

    private MockResponse loginPage() throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        String publicKey = Base64.getEncoder().encodeToString(generator.generateKeyPair().getPublic().getEncoded());
        return new MockResponse().setResponseCode(200).setBody("""
                <script>const publicKey = "%s";</script>
                <input type="hidden" name="_csrf" value="csrf-value"/>
                """.formatted(publicKey));
    }

    private MockResponse jsonResponse(int status) {
        return new MockResponse().setResponseCode(status).setBody("{}").addHeader("Content-Type", "application/json");
    }

    private List<RecordedRequest> take(int count) throws InterruptedException {
        java.util.ArrayList<RecordedRequest> requests = new java.util.ArrayList<>();
        for (int index = 0; index < count; index++) {
            RecordedRequest request = server.takeRequest(2, TimeUnit.SECONDS);
            assertThat(request).isNotNull();
            requests.add(request);
        }
        return List.copyOf(requests);
    }

    private JsonNode read(Path path) {
        try {
            return json.readTree(path.toFile());
        } catch (Exception error) {
            throw new AssertionError("Unable to parse evidence " + path, error);
        }
    }
}
