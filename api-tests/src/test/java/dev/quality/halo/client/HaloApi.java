package dev.quality.halo.client;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import dev.quality.halo.support.EvidenceRedactor;
import dev.quality.halo.support.ResourceRef;
import io.restassured.RestAssured;
import io.restassured.config.RedirectConfig;
import io.restassured.filter.Filter;
import io.restassured.filter.FilterContext;
import io.restassured.response.Response;
import io.restassured.specification.FilterableRequestSpecification;
import io.restassured.specification.FilterableResponseSpecification;
import io.restassured.specification.RequestSpecification;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.CookieManager;
import java.net.CookiePolicy;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Cipher;

public final class HaloApi {
    private static final String CONSOLE_API = "/apis/api.console.halo.run/v1alpha1";
    private static final String CONTENT_API = "/apis/content.halo.run/v1alpha1";
    private static final String PUBLIC_CONTENT_API = "/apis/api.content.halo.run/v1alpha1";
    private static final String SECURITY_CONSOLE_API = "/apis/console.api.security.halo.run/v1alpha1";
    private static final ObjectMapper JSON = new ObjectMapper();

    private final URI baseUri;
    private final Credentials credentials;
    private final Filter sessionAuthenticationFilter;
    private final Filter evidenceFilter;

    public HaloApi(URI baseUri, Credentials credentials) {
        this.baseUri = Objects.requireNonNull(baseUri, "baseUri");
        this.credentials = Objects.requireNonNull(credentials, "credentials");
        this.sessionAuthenticationFilter = new SessionAuthenticationFilter(this.baseUri, this.credentials);
        this.evidenceFilter = new RedactedEvidenceFilter(
                System.getProperty("qe.runId", "local"), System.getProperty("qe.testId", "unscoped"));
    }

    public Credentials credentials() {
        return credentials;
    }

    public Response createUser(String name, String email, String password, Set<String> roles) {
        ObjectNode request = JSON.createObjectNode();
        request.put("name", name);
        request.put("displayName", name);
        request.put("email", email);
        request.put("password", password);
        stringArray(request, "roles", roles);
        return request().body(request).post(CONSOLE_API + "/users");
    }

    public Response grantRoles(String name, Set<String> roles) {
        ObjectNode request = JSON.createObjectNode();
        stringArray(request, "roleNames", roles);
        return request().body(request).post(CONSOLE_API + "/users/{name}/permissions", name);
    }

    public Response disableUser(String name) {
        return request().post(SECURITY_CONSOLE_API + "/users/{name}/disable", name);
    }

    public Response enableUser(String name) {
        return request().post(SECURITY_CONSOLE_API + "/users/{name}/enable", name);
    }

    public Response draftPost(String name, String owner, String title, String slug) {
        return request().body(PostPayloads.draft(name, owner, title, slug)).post(CONSOLE_API + "/posts");
    }

    public Response publishPost(String name) {
        return request().put(CONSOLE_API + "/posts/{name}/publish", name);
    }

    public Response unpublishPost(String name) {
        return request().put(CONSOLE_API + "/posts/{name}/unpublish", name);
    }

    public Response recyclePost(String name) {
        return request().put(CONSOLE_API + "/posts/{name}/recycle", name);
    }

    public Response consolePost(String name) {
        return request().get(CONTENT_API + "/posts/{name}", name);
    }

    public Response publicPost(String name) {
        return request().get(PUBLIC_CONTENT_API + "/posts/{name}", name);
    }

    public Response headContent(String name) {
        return request().get(CONSOLE_API + "/posts/{name}/head-content", name);
    }

    public Response updatePost(String name, JsonNode request) {
        return request().body(request).put(CONSOLE_API + "/posts/{name}", name);
    }

    public Response deleteExtension(ResourceRef resource) {
        Objects.requireNonNull(resource, "resource");
        return request().delete("/apis/{group}/{version}/{plural}/{name}", resource.apiGroup(), resource.version(),
                resource.plural(), resource.name());
    }

    public Response currentUser() {
        return request().get(CONSOLE_API + "/users/-");
    }

    public Response user(String name) {
        return request().get(CONSOLE_API + "/users/{name}", name);
    }

    public Response deleteUser(String name) {
        return request().delete("/api/v1alpha1/users/{name}", name);
    }

    private RequestSpecification request() {
        return RestAssured.given()
                .baseUri(baseUri.toString())
                .auth()
                .preemptive()
                .basic(credentials.username(), credentials.password())
                .contentType("application/json")
                .accept("application/json")
                .config(RestAssured.config().redirect(RedirectConfig.redirectConfig().followRedirects(false)))
                .filter(evidenceFilter)
                .filter(sessionAuthenticationFilter);
    }

    private static ArrayNode stringArray(ObjectNode parent, String field, Set<String> values) {
        ArrayNode array = parent.putArray(field);
        values.stream().sorted().forEach(array::add);
        return array;
    }

    private static final class RedactedEvidenceFilter implements Filter {
        private final Path directory;
        private final AtomicLong sequence = new AtomicLong();

        private RedactedEvidenceFilter(String runId, String testId) {
            this.directory = Path.of("build", "evidence", safeSegment(runId), safeSegment(testId));
        }

        @Override
        public Response filter(
                FilterableRequestSpecification request,
                FilterableResponseSpecification responseSpecification,
                FilterContext context) {
            long requestNumber = sequence.incrementAndGet();
            Response response = context.next(request, responseSpecification);
            write(requestNumber, "request", requestEvidence(request));
            write(requestNumber, "response", responseEvidence(response));
            return response;
        }

        private void write(long requestNumber, String direction, ObjectNode evidence) {
            try {
                Files.createDirectories(directory);
                Files.writeString(
                        directory.resolve("%03d-%s.json".formatted(requestNumber, direction)),
                        JSON.writerWithDefaultPrettyPrinter().writeValueAsString(evidence),
                        StandardCharsets.UTF_8);
            } catch (IOException error) {
                throw new UncheckedIOException("Unable to write redacted HTTP evidence", error);
            }
        }

        private static ObjectNode requestEvidence(FilterableRequestSpecification request) {
            ObjectNode evidence = JSON.createObjectNode();
            evidence.put("method", request.getMethod());
            evidence.put("uri", request.getURI());
            evidence.set("headers", JSON.valueToTree(redactHeaders(request.getHeaders().asList())));
            evidence.set("body", redactedBody(request.getBody()));
            return evidence;
        }

        private static ObjectNode responseEvidence(Response response) {
            ObjectNode evidence = JSON.createObjectNode();
            evidence.put("statusCode", response.statusCode());
            evidence.set("headers", JSON.valueToTree(redactHeaders(response.getHeaders().asList())));
            evidence.set("body", redactedBody(response.asString()));
            return evidence;
        }

        private static Map<String, List<String>> redactHeaders(List<io.restassured.http.Header> headers) {
            Map<String, List<String>> values = new java.util.LinkedHashMap<>();
            headers.forEach(header -> values.merge(
                    header.getName(), List.of(header.getValue()),
                    (existing, added) -> {
                        java.util.ArrayList<String> combined = new java.util.ArrayList<>(existing);
                        combined.addAll(added);
                        return List.copyOf(combined);
                    }));
            return EvidenceRedactor.redactHeaders(values);
        }

        private static JsonNode redactedBody(Object body) {
            if (body == null || body.toString().isBlank()) {
                return JSON.nullNode();
            }
            String text = body instanceof JsonNode node ? toJson(node) : body.toString();
            try {
                return JSON.readTree(EvidenceRedactor.redactJson(text));
            } catch (IllegalArgumentException | JsonProcessingException ignored) {
                return JSON.getNodeFactory().textNode("[NON_JSON_BODY]");
            }
        }

        private static String toJson(JsonNode node) {
            try {
                return JSON.writeValueAsString(node);
            } catch (JsonProcessingException error) {
                throw new IllegalArgumentException("Unable to serialize HTTP evidence body", error);
            }
        }

        private static String safeSegment(String value) {
            return value.replaceAll("[^a-zA-Z0-9._-]", "-");
        }
    }

    private static final class SessionAuthenticationFilter implements Filter {
        private static final Pattern PUBLIC_KEY = Pattern.compile("const publicKey = \\\"([^\\\"]+)\\\"", Pattern.DOTALL);
        private static final Pattern CSRF = Pattern.compile("name=\\\"_csrf\\\" value=\\\"([^\\\"]+)\\\"");

        private final URI baseUri;
        private final Credentials credentials;
        private volatile String cookie;

        private SessionAuthenticationFilter(URI baseUri, Credentials credentials) {
            this.baseUri = baseUri;
            this.credentials = credentials;
        }

        @Override
        public Response filter(
                FilterableRequestSpecification request,
                FilterableResponseSpecification responseSpecification,
                FilterContext context) {
            if (cookie != null) {
                request.header("Cookie", cookie);
            }
            Response response = context.next(request, responseSpecification);
            if (requiresSession(response) && establishSession()) {
                return retry(request);
            }
            return response;
        }

        private boolean requiresSession(Response response) {
            return response.statusCode() == 302 && response.getHeader("Location") != null
                    && response.getHeader("Location").startsWith("/login");
        }

        private synchronized boolean establishSession() {
            if (cookie != null) {
                return true;
            }
            try {
                CookieManager cookies = new CookieManager(null, CookiePolicy.ACCEPT_ALL);
                HttpClient client = HttpClient.newBuilder()
                        .cookieHandler(cookies)
                        .followRedirects(HttpClient.Redirect.NEVER)
                        .build();
                HttpResponse<String> login = client.send(
                        HttpRequest.newBuilder(baseUri.resolve("/login")).GET().build(),
                        HttpResponse.BodyHandlers.ofString());
                if (login.statusCode() != 200) {
                    return false;
                }
                String encryptedPassword = encryptPassword(login.body());
                String form = form("_csrf", match(CSRF, login.body()))
                        + "&" + form("username", credentials.username())
                        + "&" + form("password", encryptedPassword);
                HttpResponse<Void> authenticated = client.send(
                        HttpRequest.newBuilder(baseUri.resolve("/login"))
                                .header("Content-Type", "application/x-www-form-urlencoded")
                                .POST(HttpRequest.BodyPublishers.ofString(form))
                                .build(),
                        HttpResponse.BodyHandlers.discarding());
                if (authenticated.statusCode() != 302) {
                    return false;
                }
                List<String> values = cookies.get(baseUri, Map.of()).getOrDefault("Cookie", List.of());
                if (values.isEmpty()) {
                    return false;
                }
                cookie = String.join("; ", values);
                return true;
            } catch (Exception error) {
                return false;
            }
        }

        private Response retry(FilterableRequestSpecification request) {
            RequestSpecification retry = RestAssured.given()
                    .baseUri(baseUri.toString())
                    .contentType("application/json")
                    .accept("application/json")
                    .config(RestAssured.config().redirect(RedirectConfig.redirectConfig().followRedirects(false)))
                    .header("Cookie", cookie);
            if (request.getBody() != null) {
                retry.body((Object) request.getBody());
            }
            return retry.request(request.getMethod(), request.getURI());
        }

        private String encryptPassword(String loginPage) throws Exception {
            String encodedKey = match(PUBLIC_KEY, loginPage)
                    .replace("\\n", "")
                    .replace("\\/", "/")
                    .replaceAll("\\s", "");
            PublicKey publicKey = KeyFactory.getInstance("RSA")
                    .generatePublic(new X509EncodedKeySpec(Base64.getDecoder().decode(encodedKey)));
            Cipher cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
            cipher.init(Cipher.ENCRYPT_MODE, publicKey);
            return Base64.getEncoder().encodeToString(cipher.doFinal(credentials.password().getBytes(StandardCharsets.UTF_8)));
        }

        private static String match(Pattern pattern, String input) {
            Matcher matcher = pattern.matcher(input);
            if (!matcher.find()) {
                throw new IllegalArgumentException("Expected login field is absent");
            }
            return matcher.group(1);
        }

        private static String form(String key, String value) {
            return URLEncoder.encode(key, StandardCharsets.UTF_8) + "=" + URLEncoder.encode(value, StandardCharsets.UTF_8);
        }
    }
}
