package dev.quality.halo.support;

import dev.quality.halo.client.Credentials;
import dev.quality.halo.client.HaloApi;
import io.restassured.response.Response;
import java.net.URI;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Objects;
import java.util.Set;

public final class HaloFixture implements AutoCloseable {
    private static final String USER_API_GROUP = "api.console.halo.run";
    private static final String API_VERSION = "v1alpha1";
    private static final String USERS = "users";

    private final RunIdentity runIdentity;
    private final ResourceLedger ledger;
    private final HaloApi admin;
    private final Duration settleDeadline;
    private final Duration settleInitialDelay;
    private final Set<String> trackedPosts = new LinkedHashSet<>();

    public HaloFixture() {
        this(URI.create(System.getProperty("halo.baseUrl", "http://127.0.0.1:8090")),
                RunIdentity.create(Clock.systemUTC(), System.getProperty("qe.workerId", "api")));
    }

    public HaloFixture(URI baseUri, RunIdentity runIdentity) {
        this(baseUri, runIdentity, Duration.ofSeconds(15), Duration.ofMillis(100));
    }

    HaloFixture(
            URI baseUri, RunIdentity runIdentity, Duration settleDeadline, Duration settleInitialDelay) {
        URI checkedBaseUri = Objects.requireNonNull(baseUri, "baseUri");
        this.runIdentity = Objects.requireNonNull(runIdentity, "runIdentity");
        this.settleDeadline = Objects.requireNonNull(settleDeadline, "settleDeadline");
        this.settleInitialDelay = Objects.requireNonNull(settleInitialDelay, "settleInitialDelay");
        this.ledger = new ResourceLedger();
        this.admin = new HaloApi(checkedBaseUri, new Credentials("qe-admin", "HaloQE!2026"));
    }

    public RoleUsers createRoles() {
        Credentials adminCredentials = admin.credentials();
        Credentials author = createUser("author", Set.of("role-template-post-author", "role-template-post-contributor"));
        Credentials contributor = createUser("contributor", Set.of("role-template-post-contributor"));
        Credentials readonly = createUser("readonly", Set.of());
        return new RoleUsers(adminCredentials, author, contributor, readonly);
    }

    public Credentials adminCredentials() {
        return admin.credentials();
    }

    public String unique(String logicalSuffix) {
        return ResourceRef.scoped(runIdentity, "content.halo.run", API_VERSION, "posts", logicalSuffix).name();
    }

    public void trackPost(String name) {
        trackedPosts.add(name);
        ledger.record(new ResourceRef("content.halo.run", API_VERSION, "posts", name));
    }

    @Override
    public void close() {
        List<CleanupIssue> settlingFailures = new ArrayList<>();
        List<CleanupFailure> deletionFailures;
        try {
            trackedPosts.forEach(name -> {
                try {
                    waitForSettledPost(name);
                } catch (RuntimeException error) {
                    settlingFailures.add(new CleanupIssue(name, error));
                }
            });
        } finally {
            deletionFailures = ledger.cleanup(this::delete);
        }
        if (!settlingFailures.isEmpty() || !deletionFailures.isEmpty()) {
            List<CleanupIssue> deletions = deletionFailures.stream()
                    .map(failure -> new CleanupIssue(failure.resourceName(), failure.cause()))
                    .toList();
            throw new CleanupException(settlingFailures, deletions);
        }
    }

    private Credentials createUser(String logicalSuffix, Set<String> roles) {
        ResourceRef ref = ResourceRef.scoped(runIdentity, USER_API_GROUP, API_VERSION, USERS, logicalSuffix);
        String password = "fixture-" + ref.name() + "-password";
        Response response = admin.createUser(ref.name(), ref.name() + "@example.test", password, roles);
        requireSuccess(response, "create user");
        ledger.record(ref);
        return new Credentials(ref.name(), password);
    }

    private void delete(ResourceRef ref) {
        Response response = USERS.equals(ref.plural()) ? admin.deleteUser(ref.name()) : admin.deleteExtension(ref);
        if (response.statusCode() >= 300 && response.statusCode() != 404) {
            throw new IllegalStateException("delete resource returned HTTP " + response.statusCode());
        }
    }

    private void waitForSettledPost(String name) {
        long[] lastVersion = {Long.MIN_VALUE};
        int[] stableObservations = {0};
        boolean[] settled = {false};
        Response last = Eventually.until(settleDeadline, settleInitialDelay, () -> admin.consolePost(name), response -> {
            if (response.statusCode() == 404) {
                return settled[0] = true;
            }
            if (response.statusCode() != 200 || response.jsonPath().get("status.observedVersion") == null) {
                return false;
            }
            long version = response.jsonPath().getLong("metadata.version");
            long observed = response.jsonPath().getLong("status.observedVersion");
            stableObservations[0] = version == observed && version == lastVersion[0] ? stableObservations[0] + 1 : 1;
            lastVersion[0] = version;
            return settled[0] = version == observed && stableObservations[0] >= 3;
        });
        if (!settled[0]) {
            throw new IllegalStateException(
                    "post did not settle before cleanup deadline; last HTTP " + last.statusCode());
        }
    }

    private static void requireSuccess(Response response, String operation) {
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IllegalStateException(operation + " returned HTTP " + response.statusCode());
        }
    }

    public record RoleUsers(Credentials admin, Credentials author, Credentials contributor, Credentials readonly) {}

    public record CleanupIssue(String resourceName, Throwable cause) {}

    public static final class CleanupException extends IllegalStateException {
        private final List<CleanupIssue> settlingFailures;
        private final List<CleanupIssue> deletionFailures;

        private CleanupException(List<CleanupIssue> settlingFailures, List<CleanupIssue> deletionFailures) {
            super("Fixture cleanup failed while settling " + settlingFailures.size() + " post(s) and deleting "
                    + deletionFailures.size() + " resource(s)");
            this.settlingFailures = List.copyOf(settlingFailures);
            this.deletionFailures = List.copyOf(deletionFailures);
            this.settlingFailures.forEach(failure -> addSuppressed(failure.cause()));
            this.deletionFailures.forEach(failure -> addSuppressed(failure.cause()));
        }

        public List<CleanupIssue> settlingFailures() {
            return settlingFailures;
        }

        public List<CleanupIssue> deletionFailures() {
            return deletionFailures;
        }
    }
}
