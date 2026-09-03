package dev.quality.halo.environment;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Tag;
import org.junit.jupiter.api.Test;

@Tag("smoke")
class EnvironmentSmokeTest {
    @Test
    void setupEndpointIsReachable() throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:8090/system/setup"))
                .header("Accept", "text/html").GET().build();
        var response = HttpClient.newHttpClient()
                .send(request, HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isIn(200, 302);
    }
}
