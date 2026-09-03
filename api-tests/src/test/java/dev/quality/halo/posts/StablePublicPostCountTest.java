package dev.quality.halo.posts;

import static org.assertj.core.api.Assertions.assertThat;

import io.restassured.builder.ResponseBuilder;
import io.restassured.http.ContentType;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;

class StablePublicPostCountTest {
    @Test
    void requiresThreeConsecutiveExactNameCountsAndResetsOnMismatch() {
        StablePublicPostCount observation = new StablePublicPostCount("target", 3);

        assertThat(observation.test(response("target"))).isFalse();
        assertThat(observation.test(response())).isFalse();
        assertThat(observation.test(response("target"))).isFalse();
        assertThat(observation.test(response("target", "target"))).isFalse();
        assertThat(observation.test(response("other", "target"))).isFalse();
        assertThat(observation.test(response("target"))).isFalse();
        assertThat(observation.test(response("target"))).isTrue();
    }

    private static Response response(String... names) {
        String items = java.util.Arrays.stream(names)
                .map(name -> "{\"metadata\":{\"name\":\"" + name + "\"}}")
                .collect(java.util.stream.Collectors.joining(","));
        return new ResponseBuilder()
                .setStatusCode(200)
                .setContentType(ContentType.JSON)
                .setBody("{\"items\":[" + items + "]}")
                .build();
    }
}
