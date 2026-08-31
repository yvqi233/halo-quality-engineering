package dev.quality.halo.support;

import dev.quality.halo.client.Credentials;
import dev.quality.halo.client.HaloApi;
import io.restassured.response.Response;
import java.net.URI;
import java.time.Clock;
import java.util.List;
import java.util.Objects;
import java.util.Set;

public final class HaloFixture implements AutoCloseable {
    private static final String USER_API_GROUP = "api.console.halo.run";
    private static final String API_VERSION = "v1alpha1";
    private static final String USERS = "users";

    private final URI baseUri;
    private final RunIdentity runIdentity;
    private final ResourceLedger ledger;
    private final HaloApi admin;

    public HaloFixture() {
        this(URI.create(System.getProperty("halo.baseUrl", "http://127.0.0.1:8090")),
                RunIdentity.create(Clock.systemUTC(), System.getProperty("qe.workerId", "api")));
    }

    public HaloFixture(URI baseUri, RunIdentity runIdentity) {
        this.baseUri = Objects.requireNonNull(baseUri, "baseUri");
        this.runIdentity = Objects.requireNonNull(runIdentity, "runIdentity");
        this.ledger = new ResourceLedger();
        this.admin = new HaloApi(this.baseUri, new Credentials("qe-admin", "HaloQE!2026"));
    }

    public RoleUsers createRoles() {
        Credentials adminCredentials = admin.credentials();
        Credentials author = createUser("author", Set.of("role-template-post-author", "role-template-post-contributor"));
        Credentials readonly = createUser("readonly", Set.of());
        return new RoleUsers(adminCredentials, author, readonly);
    }

    public HaloApi admin() {
        return admin;
    }

    public HaloApi api(Credentials credentials) {
        return new HaloApi(baseUri, credentials);
    }

    public String unique(String logicalSuffix) {
        return ResourceRef.scoped(runIdentity, "content.halo.run", API_VERSION, "posts", logicalSuffix).name();
    }

    @Override
    public void close() {
        List<?> failures = ledger.cleanup(this::delete);
        if (!failures.isEmpty()) {
            throw new IllegalStateException("Fixture cleanup failed for " + failures.size() + " resource(s)");
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

    private static void requireSuccess(Response response, String operation) {
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IllegalStateException(operation + " returned HTTP " + response.statusCode());
        }
    }

    public record RoleUsers(Credentials admin, Credentials author, Credentials readonly) {}
}
