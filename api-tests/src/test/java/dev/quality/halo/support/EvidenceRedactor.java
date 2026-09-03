package dev.quality.halo.support;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

public final class EvidenceRedactor {
    private static final String REDACTED = "[REDACTED]";
    private static final Set<String> SENSITIVE_KEYS =
            Set.of("password", "authorization", "cookie", "set-cookie", "token", "storagestate");
    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private EvidenceRedactor() {}

    public static Map<String, List<String>> redactHeaders(Map<String, List<String>> headers) {
        Map<String, List<String>> redacted = new LinkedHashMap<>();
        headers.forEach((name, values) -> redacted.put(
                name, isSensitive(name) ? List.of(REDACTED) : List.copyOf(values)));
        return Map.copyOf(redacted);
    }

    public static String redactJson(String json) {
        try {
            JsonNode root = OBJECT_MAPPER.readTree(json);
            redactNode(root);
            return OBJECT_MAPPER.writeValueAsString(root);
        } catch (JsonProcessingException error) {
            throw new IllegalArgumentException("Evidence must be valid JSON", error);
        }
    }

    private static void redactNode(JsonNode node) {
        if (node.isObject()) {
            ObjectNode object = (ObjectNode) node;
            object.fields().forEachRemaining(entry -> {
                if (isSensitive(entry.getKey())) {
                    object.put(entry.getKey(), REDACTED);
                } else {
                    redactNode(entry.getValue());
                }
            });
        } else if (node.isArray()) {
            node.forEach(EvidenceRedactor::redactNode);
        }
    }

    private static boolean isSensitive(String key) {
        return SENSITIVE_KEYS.contains(key.toLowerCase(Locale.ROOT));
    }
}
