package dev.quality.halo.client;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
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
    void draftsPostAgainstConsoleApiWithHaloPostRequestShape() throws Exception {
        server.enqueue(new MockResponse().setResponseCode(200).setBody("{\"metadata\":{\"name\":\"p1\"}}")
                .addHeader("Content-Type", "application/json"));
        new HaloApi(server.url("/").uri(), new Credentials("qe-admin", "HaloQE!2026"))
                .draftPost("p1", "qe-admin", "Title", "title");

        RecordedRequest request = server.takeRequest();
        assertThat(request.getMethod()).isEqualTo("POST");
        assertThat(request.getPath()).isEqualTo("/apis/api.console.halo.run/v1alpha1/posts");
        JsonNode body = json.readTree(request.getBody().readUtf8());
        assertThat(body.at("/post/apiVersion").asText())
                .isEqualTo("content.halo.run/v1alpha1");
        assertThat(body.at("/content/rawType").asText()).isEqualTo("HTML");
    }
}
