package dev.quality.halo.auth;

import static org.assertj.core.api.Assertions.assertThat;

import dev.quality.halo.client.Credentials;
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
class AuthenticationIT {
    private static final URI BASE_URI = URI.create("http://127.0.0.1:8090");

    private HaloFixture fixture;
    private HaloApi admin;
    private HaloApi author;
    private HaloApi readonly;
    private HaloFixture.RoleUsers users;
    private boolean authorDisabled;

    @BeforeAll
    void createRoleUsers() {
        System.setProperty("qe.testId", "A01");
        fixture = new HaloFixture();
        users = fixture.createRoles();
        System.clearProperty("qe.testId");
    }

    @BeforeEach
    void setUp(TestInfo testInfo) {
        System.setProperty("qe.testId", scenarioId(testInfo));
        admin = new HaloApi(BASE_URI, users.admin());
        author = new HaloApi(BASE_URI, users.author());
        readonly = new HaloApi(BASE_URI, users.readonly());
        authorDisabled = false;
    }

    @org.junit.jupiter.api.AfterEach
    void restoreRoleState() {
        try {
            if (authorDisabled) {
                admin.enableUser(author.credentials().username()).then().statusCode(200);
                waitForNoDevice(author.credentials().username());
                authorDisabled = false;
            }
        } finally {
            System.clearProperty("qe.testId");
        }
    }

    @AfterAll
    void closeFixture() {
        fixture.close();
    }

    @Test
    @DisplayName("A01 admin valid credentials return authenticated identity")
    void adminValidCredentials() {
        assertIdentity(admin, admin.credentials().username());
    }

    @Test
    @DisplayName("A02 wrong password is denied with 401")
    void wrongPasswordIsDenied() {
        HaloApi wrong = new HaloApi(BASE_URI, new Credentials(admin.credentials().username(), "intentionally-wrong"));
        wrong.authenticatedUser().then().statusCode(401);
    }

    @Test
    @DisplayName("A03 missing authentication is denied with 401")
    void missingAuthenticationIsDenied() {
        admin.unauthenticatedUser().then().statusCode(401);
    }

    @Test
    @DisplayName("A04 author valid credentials return authenticated identity")
    void authorValidCredentials() {
        assertIdentity(author, author.credentials().username());
    }

    @Test
    @DisplayName("A05 readonly valid credentials return authenticated identity")
    void readonlyValidCredentials() {
        assertIdentity(readonly, readonly.credentials().username());
    }

    @Test
    @DisplayName("A06 disabled author is denied with 401")
    void disabledAuthorIsDenied() {
        assertIdentity(author, author.credentials().username());
        admin.disableUser(author.credentials().username()).then().statusCode(200);
        authorDisabled = true;
        author.authenticatedUser().then().statusCode(401);
    }

    @Test
    @DisplayName("A07 disabled author denial creates no post")
    void disabledAuthorCreatesNoPost() {
        String guard = createAdminDraft("a07-guard");
        String deniedName = fixture.unique("a07-denied");
        PostState before = state(guard, deniedName);

        admin.disableUser(author.credentials().username()).then().statusCode(200);
        authorDisabled = true;
        author.ownDraftPost(deniedName, author.credentials().username(), "A07 " + deniedName, deniedName)
                .then().statusCode(401);

        assertThat(state(guard, deniedName)).isEqualTo(before);
        admin.consolePost(deniedName).then().statusCode(404);
    }

    @Test
    @DisplayName("A08 re-enabled author returns authenticated identity")
    void reenabledAuthorAuthenticates() {
        admin.disableUser(author.credentials().username()).then().statusCode(200);
        authorDisabled = true;
        author.authenticatedUser().then().statusCode(401);
        admin.enableUser(author.credentials().username()).then().statusCode(200);
        authorDisabled = false;
        waitForNoDevice(author.credentials().username());
        author.resetSession();
        assertIdentity(author, author.credentials().username());
    }

    private String createAdminDraft(String suffix) {
        String name = fixture.unique(suffix);
        admin.draftPost(name, admin.credentials().username(), suffix + " " + name, name).then().statusCode(200);
        fixture.trackPost(name);
        return name;
    }

    private PostState state(String guardName, String countedName) {
        Response guard = settledPost(guardName);
        guard.then().statusCode(200);
        long count = admin.postsByName(countedName).then().statusCode(200).extract().jsonPath().getLong("total");
        return new PostState(
                guard.jsonPath().getLong("metadata.version"), guard.jsonPath().getString("status.phase"), count);
    }

    private static void assertIdentity(HaloApi api, String username) {
        Response response = api.authenticatedUser();
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.jsonPath().getString("name")).isEqualTo(username);
    }

    private void waitForNoDevice(String username) {
        Eventually.until(Duration.ofSeconds(15), Duration.ofMillis(100), () -> admin.devicesFor(username), response ->
                        response.statusCode() == 200 && response.jsonPath().getLong("total") == 0)
                .then().statusCode(200).body("total", org.hamcrest.Matchers.equalTo(0));
    }

    private Response settledPost(String name) {
        long[] lastVersion = {Long.MIN_VALUE};
        int[] stableObservations = {0};
        return Eventually.until(Duration.ofSeconds(15), Duration.ofMillis(100), () -> admin.consolePost(name), response -> {
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

    private static String scenarioId(TestInfo testInfo) {
        return testInfo.getDisplayName().substring(0, 3);
    }

    private record PostState(long version, String phase, long count) {}
}
