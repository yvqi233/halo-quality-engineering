package dev.quality.halo.posts;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.quality.halo.client.HaloApi;
import dev.quality.halo.client.PostPayloads;
import dev.quality.halo.support.Eventually;
import dev.quality.halo.support.HaloFixture;
import io.restassured.response.Response;
import java.net.URI;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInfo;

@Tag("integration")
class PostLifecycleIT {
    private static final URI BASE_URI = URI.create("http://127.0.0.1:8090");
    private static final Duration DEADLINE = Duration.ofSeconds(15);
    private static final Duration INITIAL_DELAY = Duration.ofMillis(100);
    private static final ObjectMapper JSON = new ObjectMapper();

    private HaloFixture fixture;
    private HaloApi admin;

    @BeforeEach
    void setUp(TestInfo testInfo) {
        System.setProperty("qe.testId", scenarioId(testInfo));
        fixture = new HaloFixture();
        admin = new HaloApi(BASE_URI, fixture.adminCredentials());
    }

    @AfterEach
    void tearDown() {
        try {
            fixture.close();
        } finally {
            System.clearProperty("qe.testId");
        }
    }

    @Test
    @DisplayName("P01 create draft reaches DRAFT phase")
    void createDraft() {
        String name = createDraft("p01", "P01");
        waitForPhase(name, "DRAFT").then().body("spec.publish", org.hamcrest.Matchers.equalTo(false));
    }

    @Test
    @DisplayName("P02 draft is absent from public API")
    void draftIsNotPublic() {
        String name = createDraft("p02", "P02");
        waitForPublic(name, 404).then().statusCode(404);
    }

    @Test
    @DisplayName("P03 publish reaches PUBLISHED phase")
    void publishReachesPublished() {
        String name = createDraft("p03", "P03");
        admin.publishPost(name).then().statusCode(200);
        waitForPhase(name, "PUBLISHED").then().body("spec.publish", org.hamcrest.Matchers.equalTo(true));
    }

    @Test
    @DisplayName("P04 public API returns matching title and slug")
    void publicApiMatchesTitleAndSlug() {
        String name = createDraft("p04", "P04");
        String title = "P04 " + name;
        admin.publishPost(name).then().statusCode(200);
        waitForPublic(name, 200).then().body("spec.title", org.hamcrest.Matchers.equalTo(title))
                .body("spec.slug", org.hamcrest.Matchers.equalTo(name));
    }

    @Test
    @DisplayName("P05 status permalink serves the published title")
    void permalinkServesTitle() {
        String name = createDraft("p05", "P05");
        String title = "P05 " + name;
        admin.publishPost(name).then().statusCode(200);
        Response published = waitForPhase(name, "PUBLISHED");
        String permalink = published.jsonPath().getString("status.permalink");
        assertThat(permalink).isNotBlank();
        admin.permalink(permalink).then().statusCode(200).body(org.hamcrest.Matchers.containsString(title));
    }

    @Test
    @DisplayName("P06 unpublish sets publish false")
    void unpublishClearsPublishFlag() {
        String name = createDraft("p06", "P06");
        admin.publishPost(name).then().statusCode(200);
        waitForPhase(name, "PUBLISHED");
        admin.unpublishPost(name).then().statusCode(200);
        waitForPublishFlag(name, false).then().body("spec.publish", org.hamcrest.Matchers.equalTo(false));
    }

    @Test
    @DisplayName("P07 unpublished post is absent from public API")
    void unpublishedPostIsNotPublic() {
        String name = createDraft("p07", "P07");
        admin.publishPost(name).then().statusCode(200);
        waitForPublic(name, 200);
        admin.unpublishPost(name).then().statusCode(200);
        waitForPublishFlag(name, false);
        waitForPublic(name, 404).then().statusCode(404);
    }

    @Test
    @DisplayName("P08 recycle sets deleted true and removes public post")
    void recycleRemovesPublicPost() {
        String name = createDraft("p08", "P08");
        admin.publishPost(name).then().statusCode(200);
        waitForPublic(name, 200);
        admin.recyclePost(name).then().statusCode(200);
        Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.consolePost(name),
                        response -> response.statusCode() == 200 && response.jsonPath().getBoolean("spec.deleted"))
                .then().body("spec.deleted", org.hamcrest.Matchers.equalTo(true));
        waitForPublic(name, 404).then().statusCode(404);
    }

    @Test
    @DisplayName("P09 publish unknown name is denied with 404")
    void publishUnknownNameIsDenied() {
        String guard = createDraft("p09-guard", "P09 guard");
        String unknown = fixture.unique("p09-unknown");
        PostState before = state(guard, unknown);

        admin.publishPost(unknown).then().statusCode(404);

        assertThat(state(guard, unknown)).isEqualTo(before);
        admin.consolePost(unknown).then().statusCode(404);
    }

    @Test
    @DisplayName("P10 repeated publish preserves one release snapshot and public resource")
    void repeatedPublishIsIdempotent() {
        String name = createDraft("p10", "P10");
        Response firstPublish = admin.publishPost(name).then().statusCode(200).extract().response();
        waitForPhase(name, "PUBLISHED");
        waitForPublic(name, 200);

        Response secondPublish = admin.publishPost(name).then().statusCode(200).extract().response();
        Response stableCollection = Eventually.until(
                DEADLINE, INITIAL_DELAY, admin::publicPosts, new StablePublicPostCount(name, 3));

        String firstSnapshot = firstPublish.jsonPath().getString("spec.releaseSnapshot");
        String secondSnapshot = secondPublish.jsonPath().getString("spec.releaseSnapshot");
        assertThat(firstSnapshot).isNotBlank().isEqualTo(secondSnapshot);
        assertThat(stableCollection.statusCode()).isEqualTo(200);
        waitForPublic(name, 200).then().statusCode(200);
    }

    @Test
    @DisplayName("P11 concurrent same-version updates yield 200 and 409 without mixed state")
    void concurrentUpdatesPreserveCompletePair() throws Exception {
        String name = createDraft("p11", "P11");
        JsonNode post = JSON.readTree(settledPost(name).then().statusCode(200).extract().asString());
        Response head = admin.headContent(name).then().statusCode(200).extract().response();
        String snapshotName = post.at("/spec/headSnapshot").asText();
        long contentVersion = admin.snapshot(snapshotName).then().statusCode(200).extract().jsonPath()
                .getLong("metadata.version");
        String titleA = "P11 A " + name;
        String titleB = "P11 B " + name;
        String htmlA = "<p>P11 A " + name + "</p>";
        String htmlB = "<p>P11 B " + name + "</p>";
        JsonNode requestA = PostPayloads.update(post, contentVersion, titleA, htmlA, htmlA);
        JsonNode requestB = PostPayloads.update(post, contentVersion, titleB, htmlB, htmlB);
        assertThat(requestA.at("/post/metadata/version")).isEqualTo(requestB.at("/post/metadata/version"));
        assertThat(requestA.at("/content/version")).isEqualTo(requestB.at("/content/version"));
        assertThat(head.jsonPath().getString("snapshotName")).isEqualTo(snapshotName);

        CountDownLatch ready = new CountDownLatch(2);
        CountDownLatch start = new CountDownLatch(1);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        try {
            Future<Response> first = executor.submit(() -> updateBehindLatch(name, requestA, ready, start));
            Future<Response> second = executor.submit(() -> updateBehindLatch(name, requestB, ready, start));
            ready.await();
            start.countDown();
            List<Integer> statuses = List.of(first.get().statusCode(), second.get().statusCode()).stream().sorted().toList();
            assertThat(statuses).containsExactly(200, 409);
        } finally {
            executor.shutdownNow();
        }

        Response finalPost = settledPost(name);
        assertThat(finalPost.jsonPath().getString("spec.title")).isIn(titleA, titleB);
        Response finalContent = admin.headContent(name).then().statusCode(200).extract().response();
        String finalTitle = finalPost.jsonPath().getString("spec.title");
        String finalRaw = finalContent.jsonPath().getString("raw");
        assertThat(List.of(finalTitle, finalRaw)).isIn(List.of(titleA, htmlA), List.of(titleB, htmlB));
        assertThat(finalContent.jsonPath().getString("content")).isEqualTo(finalRaw);
    }

    private Response updateBehindLatch(
            String name, JsonNode request, CountDownLatch ready, CountDownLatch start) throws InterruptedException {
        ready.countDown();
        start.await();
        return admin.updatePost(name, request);
    }

    private String createDraft(String suffix, String label) {
        String name = fixture.unique(suffix);
        admin.draftPost(name, admin.credentials().username(), label + " " + name, name).then().statusCode(200);
        fixture.trackPost(name);
        return name;
    }

    private Response waitForPhase(String name, String phase) {
        return Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.consolePost(name), response ->
                response.statusCode() == 200 && phase.equals(response.jsonPath().getString("status.phase")));
    }

    private Response waitForPublishFlag(String name, boolean publish) {
        return Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.consolePost(name), response ->
                response.statusCode() == 200 && response.jsonPath().getBoolean("spec.publish") == publish);
    }

    private Response waitForPublic(String name, int status) {
        return Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.publicPost(name),
                response -> response.statusCode() == status);
    }

    private PostState state(String guardName, String countedName) {
        Response guard = settledPost(guardName);
        guard.then().statusCode(200);
        long count = admin.postsByName(countedName).then().statusCode(200).extract().jsonPath().getLong("total");
        return new PostState(
                guard.jsonPath().getLong("metadata.version"), guard.jsonPath().getString("status.phase"), count);
    }

    private static String scenarioId(TestInfo testInfo) {
        return testInfo.getDisplayName().substring(0, 3);
    }

    private Response settledPost(String name) {
        long[] lastVersion = {Long.MIN_VALUE};
        int[] stableObservations = {0};
        return Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.consolePost(name), response -> {
            if (response.statusCode() != 200 || response.jsonPath().get("status.observedVersion") == null) {
                return false;
            }
            long version = response.jsonPath().getLong("metadata.version");
            long observed = response.jsonPath().getLong("status.observedVersion");
            stableObservations[0] = version == observed && version == lastVersion[0] ? stableObservations[0] + 1 : 1;
            lastVersion[0] = version;
            return version == observed && stableObservations[0] >= 3;
        });
    }

    private record PostState(long version, String phase, long count) {}
}
