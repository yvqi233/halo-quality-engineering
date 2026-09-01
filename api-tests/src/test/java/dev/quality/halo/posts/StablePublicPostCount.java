package dev.quality.halo.posts;

import io.restassured.response.Response;
import java.util.List;
import java.util.Objects;
import java.util.function.Predicate;

final class StablePublicPostCount implements Predicate<Response> {
    private final String name;
    private final int requiredObservations;
    private int consecutiveObservations;

    StablePublicPostCount(String name, int requiredObservations) {
        this.name = Objects.requireNonNull(name, "name");
        if (requiredObservations < 1) {
            throw new IllegalArgumentException("Required observations must be positive");
        }
        this.requiredObservations = requiredObservations;
    }

    @Override
    public boolean test(Response response) {
        if (response.statusCode() != 200 || exactNameCount(response) != 1) {
            consecutiveObservations = 0;
            return false;
        }
        return ++consecutiveObservations >= requiredObservations;
    }

    private long exactNameCount(Response response) {
        List<String> names = response.jsonPath().getList("items.metadata.name", String.class);
        return names == null ? 0 : names.stream().filter(name::equals).count();
    }
}
