package dev.quality.halo.permissions;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.quality.halo.client.HaloApi;
import dev.quality.halo.support.Eventually;
import dev.quality.halo.support.HaloFixture;
import io.restassured.response.Response;
import java.net.URI;
import java.time.Duration;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInfo;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.TestMethodOrder;

@Tag("integration")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.DisplayName.class)
class PostPermissionIT {
    private static final URI BASE_URI = URI.create("http://127.0.0.1:8090");
    private static final Duration DEADLINE = Duration.ofSeconds(15);
    private static final Duration INITIAL_DELAY = Duration.ofMillis(100);
    private static final ObjectMapper JSON = new ObjectMapper();

    private HaloFixture fixture;
    private HaloApi admin;
    private HaloApi contributor;
    private HaloApi readonly;
    private HaloFixture.RoleUsers users;

    @BeforeAll
    void createRoleUsers() {
        System.setProperty("qe.testId", "R01");
        fixture = new HaloFixture();
        users = fixture.createRoles();
        System.clearProperty("qe.testId");
    }

    @BeforeEach
    void setUp(TestInfo testInfo) {
        System.setProperty("qe.testId", scenarioId(testInfo));
        admin = new HaloApi(BASE_URI, users.admin());
        contributor = new HaloApi(BASE_URI, users.contributor());
        readonly = new HaloApi(BASE_URI, users.readonly());
    }

    @org.junit.jupiter.api.AfterEach
    void clearTestId() {
        System.clearProperty("qe.testId");
    }

    @AfterAll
    void closeFixture() {
        fixture.close();
    }

    @Test
    @DisplayName("R01 admin creates draft")
    void adminCreatesDraft() {
        String name = createAdminDraft("r01");
        waitForPhase(name, "DRAFT").then().body("spec.owner", org.hamcrest.Matchers.equalTo(admin.credentials().username()));
    }

    @Test
    @DisplayName("R02 contributor creates own draft")
    void contributorCreatesOwnDraft() {
        authenticate(contributor);
        String name = createContributorDraft("r02");
        contributor.ownPost(name).then().statusCode(200)
                .body("spec.owner", org.hamcrest.Matchers.equalTo(contributor.credentials().username()))
                .body("status.phase", org.hamcrest.Matchers.equalTo("DRAFT"));
    }

    @Test
    @DisplayName("R03 readonly create is denied")
    void readonlyCreateIsDenied() {
        authenticate(readonly);
        String guard = createAdminDraft("r03-guard");
        String deniedName = fixture.unique("r03-denied");
        PostState before = state(guard, deniedName);

        readonly.ownDraftPost(deniedName, readonly.credentials().username(), "R03 " + deniedName, deniedName)
                .then().statusCode(403);

        assertThat(state(guard, deniedName)).isEqualTo(before);
        admin.consolePost(deniedName).then().statusCode(404);
    }

    @Test
    @DisplayName("R04 readonly denial leaves no resource")
    void readonlyDenialLeavesNoResource() {
        authenticate(readonly);
        String guard = createAdminDraft("r04-guard");
        String deniedName = fixture.unique("r04-denied");
        PostState before = state(guard, deniedName);

        readonly.ownDraftPost(deniedName, readonly.credentials().username(), "R04 " + deniedName, deniedName)
                .then().statusCode(403);

        assertThat(state(guard, deniedName)).isEqualTo(before);
        admin.postsByName(deniedName).then().statusCode(200).body("total", org.hamcrest.Matchers.equalTo(0));
        admin.consolePost(deniedName).then().statusCode(404);
    }

    @Test
    @DisplayName("R05 contributor cannot publish")
    void contributorCannotPublish() {
        authenticate(contributor);
        String name = createContributorDraft("r05");
        PostState before = state(name, name);

        contributor.ownPublishPost(name).then().statusCode(403);

        assertThat(state(name, name)).isEqualTo(before);
    }

    @Test
    @DisplayName("R06 contributor publish denial leaves post in DRAFT")
    void contributorPublishDenialPreservesDraft() {
        authenticate(contributor);
        String name = createContributorDraft("r06");
        PostState before = state(name, name);

        contributor.ownPublishPost(name).then().statusCode(403);

        PostState after = state(name, name);
        assertThat(after).isEqualTo(before);
        assertThat(after.phase()).isEqualTo("DRAFT");
    }

    @Test
    @DisplayName("R07 admin publishes contributor post")
    void adminPublishesContributorPost() {
        authenticate(contributor);
        String name = createContributorDraft("r07");
        admin.publishPost(name).then().statusCode(200);
        waitForPhase(name, "PUBLISHED").then().body("spec.owner",
                org.hamcrest.Matchers.equalTo(contributor.credentials().username()));
    }

    @Test
    @DisplayName("R08 contributor cannot update another owner's post")
    void contributorCannotUpdateAnotherOwnersPost() throws Exception {
        authenticate(contributor);
        String name = createAdminDraft("r08-other-owner");
        PostState before = state(name, name);
        JsonNode post = JSON.readTree(admin.consolePost(name).then().statusCode(200).extract().asString());
        ((com.fasterxml.jackson.databind.node.ObjectNode) post.path("spec")).put("title", "R08 forbidden title");

        contributor.ownUpdatePost(name, post).then().statusCode(404);

        assertThat(state(name, name)).isEqualTo(before);
        admin.consolePost(name).then().body("spec.title", org.hamcrest.Matchers.not("R08 forbidden title"));
    }

    @Test
    @DisplayName("R09 unauthenticated create is denied with 401")
    void unauthenticatedCreateIsDenied() {
        String guard = createAdminDraft("r09-guard");
        String deniedName = fixture.unique("r09-denied");
        PostState before = state(guard, deniedName);

        admin.unauthenticatedDraftPost(deniedName, admin.credentials().username(), "R09 " + deniedName, deniedName)
                .then().statusCode(401);

        assertThat(state(guard, deniedName)).isEqualTo(before);
        admin.consolePost(deniedName).then().statusCode(404);
    }

    private String createAdminDraft(String suffix) {
        String name = fixture.unique(suffix);
        admin.draftPost(name, admin.credentials().username(), suffix + " " + name, name).then().statusCode(200);
        fixture.trackPost(name);
        return name;
    }

    private String createContributorDraft(String suffix) {
        String name = fixture.unique(suffix);
        contributor.ownDraftPost(
                        name, contributor.credentials().username(), suffix + " " + name, name)
                .then().statusCode(200);
        fixture.trackPost(name);
        return name;
    }

    private Response waitForPhase(String name, String phase) {
        return Eventually.until(DEADLINE, INITIAL_DELAY, () -> admin.consolePost(name), response ->
                response.statusCode() == 200 && phase.equals(response.jsonPath().getString("status.phase")));
    }

    private PostState state(String guardName, String countedName) {
        Response guard = settledPost(guardName);
        guard.then().statusCode(200);
        long count = admin.postsByName(countedName).then().statusCode(200).extract().jsonPath().getLong("total");
        return new PostState(
                guard.jsonPath().getLong("metadata.version"), guard.jsonPath().getString("status.phase"), count);
    }

    private void authenticate(HaloApi api) {
        api.authenticatedUser().then().statusCode(200)
                .body("name", org.hamcrest.Matchers.equalTo(api.credentials().username()));
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
