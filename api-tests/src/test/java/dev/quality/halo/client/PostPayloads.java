package dev.quality.halo.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

public final class PostPayloads {
    private static final ObjectMapper JSON = new ObjectMapper();

    private PostPayloads() {}

    public static JsonNode draft(String name, String owner, String title, String slug) {
        String html = "<p>" + title + "</p>";
        ObjectNode request = JSON.createObjectNode();
        ObjectNode post = request.putObject("post");
        post.put("apiVersion", "content.halo.run/v1alpha1");
        post.put("kind", "Post");
        post.putObject("metadata").put("name", name);

        ObjectNode spec = post.putObject("spec");
        spec.put("title", title);
        spec.put("slug", slug);
        spec.put("owner", owner);
        spec.put("deleted", false);
        spec.put("publish", false);
        spec.put("pinned", false);
        spec.put("allowComment", true);
        spec.put("visible", "PUBLIC");
        spec.put("priority", 0);
        spec.putObject("excerpt").put("autoGenerate", true).put("raw", "");
        emptyArray(spec, "categories");
        emptyArray(spec, "tags");
        emptyArray(spec, "htmlMetas");

        ObjectNode content = request.putObject("content");
        content.put("raw", html);
        content.put("content", html);
        content.put("rawType", "HTML");
        return request;
    }

    private static ArrayNode emptyArray(ObjectNode parent, String field) {
        return parent.putArray(field);
    }
}
