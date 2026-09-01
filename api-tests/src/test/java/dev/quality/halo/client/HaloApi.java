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
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.KeyFactory;
import java.security.PublicKey;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.crypto.Cipher;

public final class HaloApi {
    private static final String CONSOLE_API = "/apis/api.console.halo.run/v1alpha1";
    private static final String CONTENT_API = "/apis/content.halo.run/v1alpha1";
    private static final String PUBLIC_CONTENT_API = "/apis/api.content.halo.run/v1alpha1";
    private static final String SECURITY_CONSOLE_API = "/apis/console.api.security.halo.run/v1alpha1";
    private static final String USER_CENTER_CONTENT_API = "/apis/uc.api.content.halo.run/v1alpha1";
    private static final String USER_CENTER_IDENTITY_API = "/apis/uc.api.halo.run/v1alpha1/users/-";
    private static final String XHR_HEADER = "X-Requested-With";
    private static final Path EVIDENCE_ROOT = Path.of("build", "evidence").toAbsolutePath().normalize();
    private static final ObjectMapper JSON = new ObjectMapper();
    private static final ConcurrentMap<Path, EvidenceWriter> EVIDENCE_WRITERS = new ConcurrentHashMap<>();

    private final URI baseUri;
    private final Credentials credentials;
    private final Filter evidenceFilter;
    private final SessionAuthenticationFilter sessionAuthenticationFilter;

    public HaloApi(URI baseUri, Credentials credentials) {
        this(baseUri, credentials, System.getProperty("qe.runId", "local"), System.getProperty("qe.testId", "unscoped"));
    }

    HaloApi(URI baseUri, Credentials credentials, String runId, String testId) {
        this.baseUri = Objects.requireNonNull(baseUri, "baseUri");
        this.credentials = Objects.requireNonNull(credentials, "credentials");
        EvidenceWriter writer = EVIDENCE_WRITERS.computeIfAbsent(evidenceDirectory(runId, testId), EvidenceWriter::new);
        this.evidenceFilter = new RedactedEvidenceFilter(writer);
        this.sessionAuthenticationFilter = new SessionAuthenticationFilter(this.baseUri, this.credentials, evidenceFilter);
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
        stringArray(request, "roles", roles);
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

    public Response ownDraftPost(String name, String owner, String title, String slug) {
        return request().header(XHR_HEADER, "XMLHttpRequest")
                .body(PostPayloads.ownDraft(name, owner, title, slug))
                .post(USER_CENTER_CONTENT_API + "/posts");
    }

    public Response unauthenticatedDraftPost(String name, String owner, String title, String slug) {
        return unauthenticatedRequest().body(PostPayloads.draft(name, owner, title, slug)).post(CONSOLE_API + "/posts");
    }

    public Response publishPost(String name) {
        return request().put(CONSOLE_API + "/posts/{name}/publish", name);
    }

    public Response ownPublishPost(String name) {
        return request().header(XHR_HEADER, "XMLHttpRequest")
                .put(USER_CENTER_CONTENT_API + "/posts/{name}/publish", name);
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

    public Response ownPost(String name) {
        return request().header(XHR_HEADER, "XMLHttpRequest")
                .get(USER_CENTER_CONTENT_API + "/posts/{name}", name);
    }

    public Response publicPost(String name) {
        return request().get(PUBLIC_CONTENT_API + "/posts/{name}", name);
    }

    public Response headContent(String name) {
        return request().get(CONSOLE_API + "/posts/{name}/head-content", name);
    }

    public Response snapshot(String name) {
        return request().get(CONTENT_API + "/snapshots/{name}", name);
    }

    public Response updatePost(String name, JsonNode request) {
        return request().body(request).put(CONSOLE_API + "/posts/{name}", name);
    }

    public Response ownUpdatePost(String name, JsonNode post) {
        return request().header(XHR_HEADER, "XMLHttpRequest").body(post)
                .put(USER_CENTER_CONTENT_API + "/posts/{name}", name);
    }

    public Response postsByName(String name) {
        return request().queryParam("fieldSelector", "metadata.name==" + name).get(CONSOLE_API + "/posts");
    }

    public Response publicPosts() {
        return request().queryParam("size", 100).get(PUBLIC_CONTENT_API + "/posts");
    }

    public Response devicesFor(String username) {
        return request().queryParam("fieldSelector", "spec.principalName==" + username)
                .get("/apis/security.halo.run/v1alpha1/devices");
    }

    public Response permalink(String permalink) {
        return request().accept("text/html").get(permalink);
    }

    public Response deleteExtension(ResourceRef resource) {
        Objects.requireNonNull(resource, "resource");
        return request().delete("/apis/{group}/{version}/{plural}/{name}", resource.apiGroup(), resource.version(),
                resource.plural(), resource.name());
    }

    public Response currentUser() {
        return request().get(CONSOLE_API + "/users/-");
    }

    public Response authenticatedUser() {
        return request().header(XHR_HEADER, "XMLHttpRequest").get(USER_CENTER_IDENTITY_API);
    }

    public Response unauthenticatedUser() {
        return unauthenticatedRequest().get(USER_CENTER_IDENTITY_API);
    }

    public void resetSession() {
        sessionAuthenticationFilter.clearSession();
    }

    public Response deleteUser(String name) {
        return request().delete("/api/v1alpha1/users/{name}", name);
    }

    static Path evidenceRoot() {
        return EVIDENCE_ROOT;
    }

    static Path evidenceDirectory(String runId, String testId) {
        Path directory = EVIDENCE_ROOT.resolve(safeSegment(runId)).resolve(safeSegment(testId)).normalize();
        if (!directory.startsWith(EVIDENCE_ROOT)) {
            throw new IllegalArgumentException("Evidence directory escapes the evidence root");
        }
        return directory;
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
                .filter(sessionAuthenticationFilter)
                .filter(evidenceFilter);
    }

    private RequestSpecification unauthenticatedRequest() {
        return RestAssured.given()
                .baseUri(baseUri.toString())
                .header(XHR_HEADER, "XMLHttpRequest")
                .contentType("application/json")
                .accept("application/json")
                .config(RestAssured.config().redirect(RedirectConfig.redirectConfig().followRedirects(false)))
                .filter(evidenceFilter);
    }

    private static ArrayNode stringArray(ObjectNode parent, String field, Set<String> values) {
        ArrayNode array = parent.putArray(field);
        values.stream().sorted().forEach(array::add);
        return array;
    }

    private static String safeSegment(String value) {
        Objects.requireNonNull(value, "evidence segment");
        if (value.isBlank()) {
            throw new IllegalArgumentException("Evidence segment must not be blank");
        }
        for (String segment : value.replace('\\', '/').split("/", -1)) {
            if (segment.equals(".") || segment.equals("..")) {
                throw new IllegalArgumentException("Evidence segment must not contain dot segments");
            }
        }
        return value.replaceAll("[^a-zA-Z0-9._-]", "-");
    }

    private static final class RedactedEvidenceFilter implements Filter {
        private final EvidenceWriter writer;

        private RedactedEvidenceFilter(EvidenceWriter writer) {
            this.writer = writer;
        }

        @Override
        public Response filter(
                FilterableRequestSpecification request,
                FilterableResponseSpecification responseSpecification,
                FilterContext context) {
            Response response = context.next(request, responseSpecification);
            writer.record(request, response);
            return response;
        }
    }

    private static final class EvidenceWriter {
        private final Path directory;
        private final String writerId = UUID.randomUUID().toString();
        private final AtomicLong sequence = new AtomicLong();

        private EvidenceWriter(Path directory) {
            this.directory = directory;
        }

        private void record(FilterableRequestSpecification request, Response response) {
            long attempt = sequence.incrementAndGet();
            String attemptId = writerId + "-%020d".formatted(attempt);
            write(attemptId, "request", requestEvidence(request));
            write(attemptId, "response", responseEvidence(response));
        }

        private void write(String attemptId, String direction, ObjectNode evidence) {
            try {
                Files.createDirectories(directory);
                String filename = "%s-%s.json".formatted(attemptId, direction);
                Files.writeString(
                        directory.resolve(filename),
                        JSON.writerWithDefaultPrettyPrinter().writeValueAsString(evidence),
                        StandardCharsets.UTF_8,
                        StandardOpenOption.CREATE_NEW);
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
            Map<String, List<String>> values = new LinkedHashMap<>();
            headers.forEach(header -> values.merge(
                    header.getName(), List.of(header.getValue()),
                    (existing, added) -> {
                        List<String> combined = new ArrayList<>(existing);
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
    }

    private static final class SessionAuthenticationFilter implements Filter {
        private static final Pattern PUBLIC_KEY = Pattern.compile("const publicKey = \\\"([^\\\"]+)\\\"", Pattern.DOTALL);
        private static final Pattern CSRF = Pattern.compile("name=\\\"_csrf\\\" value=\\\"([^\\\"]+)\\\"");
        private static final ConcurrentMap<SessionKey, String> SESSION_COOKIES = new ConcurrentHashMap<>();

        private final URI baseUri;
        private final Credentials credentials;
        private final Filter preflightEvidenceFilter;
        private final SessionKey sessionKey;
        private volatile String cookie;

        private SessionAuthenticationFilter(URI baseUri, Credentials credentials, Filter preflightEvidenceFilter) {
            this.baseUri = baseUri;
            this.credentials = credentials;
            this.preflightEvidenceFilter = preflightEvidenceFilter;
            this.sessionKey = new SessionKey(baseUri, credentials);
            this.cookie = SESSION_COOKIES.get(sessionKey);
        }

        @Override
        public Response filter(
                FilterableRequestSpecification request,
                FilterableResponseSpecification responseSpecification,
                FilterContext context) {
            if (cookie == null) {
                cookie = SESSION_COOKIES.get(sessionKey);
            }
            if (isMutation(request)) {
                preflightMutation();
            } else if (isProtectedIdentity(request) && cookie == null) {
                establishSession();
            }
            if (cookie != null) {
                request.header("Cookie", cookie);
            }
            return context.next(request, responseSpecification);
        }

        private static boolean isMutation(FilterableRequestSpecification request) {
            return switch (request.getMethod()) {
                case "POST", "PUT", "PATCH", "DELETE" -> true;
                default -> false;
            };
        }

        private static boolean isProtectedIdentity(FilterableRequestSpecification request) {
            return request.getMethod().equals("GET")
                    && URI.create(request.getURI()).getPath().equals(USER_CENTER_IDENTITY_API);
        }

        private static boolean requiresSession(Response response) {
            return response.statusCode() == 302 && response.getHeader("Location") != null
                    && response.getHeader("Location").startsWith("/login");
        }

        private void preflightMutation() {
            if (cookie == null) {
                establishSession();
            }
            Response preflight = identityPreflight();
            if (requiresSession(preflight) || hasUnexpectedPrincipal(preflight)) {
                clearSession();
                if (establishSession()) {
                    identityPreflight();
                }
            }
        }

        private Response identityPreflight() {
            RequestSpecification preflight = RestAssured.given()
                    .baseUri(baseUri.toString())
                    .auth()
                    .preemptive()
                    .basic(credentials.username(), credentials.password())
                    .header(XHR_HEADER, "XMLHttpRequest")
                    .accept("application/json")
                    .config(RestAssured.config().redirect(RedirectConfig.redirectConfig().followRedirects(false)))
                    .filter(preflightEvidenceFilter);
            if (cookie != null) {
                preflight.header("Cookie", cookie);
            }
            return preflight.get(USER_CENTER_IDENTITY_API);
        }

        private boolean hasUnexpectedPrincipal(Response response) {
            return response.statusCode() == 200
                    && !credentials.username().equals(response.jsonPath().getString("name"));
        }

        private synchronized boolean establishSession() {
            if (cookie != null) {
                return true;
            }
            cookie = SESSION_COOKIES.get(sessionKey);
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
                String form = form("_csrf", match(CSRF, login.body()))
                        + "&" + form("username", credentials.username())
                        + "&" + form("password", encryptPassword(login.body()));
                HttpResponse<Void> authenticated = client.send(
                        HttpRequest.newBuilder(baseUri.resolve("/login"))
                                .header("Content-Type", "application/x-www-form-urlencoded")
                                .POST(HttpRequest.BodyPublishers.ofString(form))
                                .build(),
                        HttpResponse.BodyHandlers.discarding());
                String location = authenticated.headers().firstValue("Location").orElse("");
                if (authenticated.statusCode() != 302 || location.startsWith("/login")) {
                    return false;
                }
                List<String> values = cookies.get(baseUri, Map.of()).getOrDefault("Cookie", List.of());
                if (values.isEmpty()) {
                    return false;
                }
                cookie = String.join("; ", values);
                SESSION_COOKIES.put(sessionKey, cookie);
                return true;
            } catch (Exception error) {
                return false;
            }
        }

        private synchronized void clearSession() {
            if (cookie != null) {
                SESSION_COOKIES.remove(sessionKey, cookie);
                cookie = null;
            }
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

        private record SessionKey(URI baseUri, Credentials credentials) {}
    }
}
