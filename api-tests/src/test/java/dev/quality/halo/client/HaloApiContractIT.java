package dev.quality.halo.client;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import dev.quality.halo.support.HaloFixture;
import dev.quality.halo.support.RunIdentity;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.util.Comparator;
import java.util.List;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

@Tag("integration")
class HaloApiContractIT {
    private static final URI BASE_URI = URI.create("http://127.0.0.1:8090");
    private static final ObjectMapper JSON = new ObjectMapper();

    @Test
    void createsRoleUsersExercisesPostPermissionsAndCleansThemUpInReverseOrder() throws Exception {
        RunIdentity run = RunIdentity.create(Clock.systemUTC(), "contract");
        System.setProperty("qe.runId", run.runId());
        System.setProperty("qe.testId", "halo-api-contract");
        HaloFixture.RoleUsers users;
        try {
            try (HaloFixture fixture = new HaloFixture(BASE_URI, run)) {
                users = fixture.createRoles();
                assertThat(users.author().username()).startsWith(run.prefix());
                assertThat(users.readonly().username()).startsWith(run.prefix());
                assertThat(users.author().username()).isNotEqualTo(users.readonly().username());

                HaloApi admin = new HaloApi(BASE_URI, users.admin());
                HaloApi author = new HaloApi(BASE_URI, users.author());
                HaloApi readonly = new HaloApi(BASE_URI, users.readonly());
                String post = fixture.unique("role-post");
                author.currentUser().then().statusCode(200);
                readonly.currentUser().then().statusCode(200);
                admin.draftPost(post, users.admin().username(), "Role post " + post, post).then().statusCode(200);
                admin.consolePost(post).then().statusCode(200).body("status.phase", org.hamcrest.Matchers.is("DRAFT"));
                readonly.draftPost(fixture.unique("readonly-denied"), users.readonly().username(), "Denied", "denied")
                        .then().statusCode(org.hamcrest.Matchers.anyOf(
                                org.hamcrest.Matchers.is(401), org.hamcrest.Matchers.is(403)));
            }
            List<JsonNode> evidence = Files.list(HaloApi.evidenceDirectory(run.runId(), "halo-api-contract"))
                    .sorted(Comparator.comparing(Path::getFileName))
                    .map(this::read).toList();
            assertThat(evidence).isNotEmpty();
            assertThat(evidence).allSatisfy(record -> assertThat(record.isObject()).isTrue());
            assertThat(evidence).anySatisfy(record -> assertThat(record.at("/body/metadata/name").asText())
                    .isEqualTo(users.author().username()));
            assertThat(evidence).anySatisfy(record -> assertThat(record.at(
                    "/body/metadata/annotations/rbac.authorization.halo.run~1role-names").asText())
                    .contains("role-template-post-author", "role-template-post-contributor"));
            assertThat(evidence.stream()
                    .map(record -> record.at("/body/metadata"))
                    .filter(metadata -> metadata.hasNonNull("deletionTimestamp"))
                    .map(metadata -> metadata.path("name").asText()))
                    .containsExactlyInAnyOrder(users.author().username(), users.readonly().username());
            List<String> deletedUris = evidence.stream()
                    .filter(record -> "DELETE".equals(record.path("method").asText()))
                    .map(record -> record.path("uri").asText())
                    .toList();
            assertThat(deletedUris.subList(0, 2)).containsExactly(
                    BASE_URI + "/api/v1alpha1/users/" + users.readonly().username(),
                    BASE_URI + "/api/v1alpha1/users/" + users.author().username());
        } finally {
            System.clearProperty("qe.runId");
            System.clearProperty("qe.testId");
        }
    }

    private JsonNode read(Path path) {
        try {
            return JSON.readTree(path.toFile());
        } catch (Exception error) {
            throw new AssertionError("Unable to parse evidence", error);
        }
    }

}
