# Halo 全链路质量工程 MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建设一个可公开验证、可一键复现的 Halo 2.26 外置质量工程仓库，以 28 个 API 场景、10 条 Playwright 核心旅程、OpenAPI 破坏性差异检测和零默认重试 CI 覆盖认证、会话、文章生命周期、RBAC 与公开页面一致性。

**Architecture:** 仓库不修改 Halo 产品代码；Docker Compose 提供固定镜像的 Halo 与 PostgreSQL，一套 Java 21 测试模块承担状态和权限组合，TypeScript/Playwright 只承担关键浏览器旅程。Java 与 Playwright 使用相同 `runId-workerId` 命名协议但各自维护 Fixture，质量门禁按环境、契约、API、E2E 分层并分别保留脱敏证据。

**Tech Stack:** Java 21、Gradle 8.14、JUnit 5、RestAssured、AssertJ、TypeScript、Playwright、pnpm、Halo 2.26、PostgreSQL 16、Docker Compose、GitHub Actions、Node.js 22

**Spec:** `docs/superpowers/specs/2026-08-31-halo-quality-engineering-design.md`

## Global Constraints

- 新建独立 Git 仓库 `halo-quality-engineering`；本计划中的路径均相对该仓库根目录。
- 被测基线固定为 Halo `2.26`，实施时把实际拉取到的完整镜像摘要写入并提交 `environment/image-lock.env`，禁止使用 `latest`。
- API 测试只使用 Java 21、JUnit 5、RestAssured、AssertJ 和 Gradle；E2E 只使用 TypeScript、Playwright 和 pnpm。
- 合并门禁 `retries=0`，禁止固定时长 `sleep`；只允许等待 HTTP 状态、DOM 可见性或明确业务状态。
- 所有用户、文章和附件名称均含 `runId-workerId`；测试不直接写 Halo 数据库。
- 日志与附件必须过滤 `Authorization`、`Cookie`、`Set-Cookie`、密码和 `storageState`。
- 不建设测试管理后台或质量大屏，不引入 Selenium、额外微服务或共享在线演示环境。
- 25+ API、8+ E2E、20 次连续绿色 CI、耗时、Issue 和 PR 状态只有在实际达成并存在公开证据后才能写入简历。
- 上游行为、API 或功能修改遵守 Halo 贡献规范：先 Issue/OpenSpec，对 PR 中实质性 AI 辅助如实披露。

---

## File Structure Map

```text
halo-quality-engineering/
├─ settings.gradle.kts                 # Gradle 多项目入口，只纳入 api-tests
├─ build.gradle.kts                    # Java 21、仓库和统一测试约束
├─ gradle/wrapper/                     # 固定 Gradle 8.14
├─ api-tests/
│  ├─ build.gradle.kts                 # JUnit、RestAssured、AssertJ、Jackson、MockWebServer
│  └─ src/test/java/dev/quality/halo/
│     ├─ support/                      # 配置、runId、资源清单、证据脱敏
│     ├─ client/                       # Halo 黑盒 HTTP 客户端和请求体工厂
│     ├─ auth/                         # 认证场景 A01-A08
│     ├─ posts/                        # 生命周期场景 P01-P11
│     └─ permissions/                  # RBAC 场景 R01-R09
├─ environment/
│  ├─ docker-compose.yml              # Halo + PostgreSQL 一次性环境
│  └─ image-lock.env                  # 实际镜像 RepoDigest，不含凭据
├─ scripts/
│  ├─ pin-images.ps1                  # 解析并锁定公开镜像摘要
│  ├─ environment.ps1                 # up/down/logs/initialize
│  ├─ collect-evidence.ps1            # 容器状态和脱敏日志
│  └─ stability.ps1                   # 20 次独立、无重试运行
├─ e2e/
│  ├─ package.json
│  ├─ playwright.config.ts
│  ├─ fixtures/                       # 角色会话、API 数据工厂和清理
│  ├─ pages/                          # LoginPage、PostsPage；动作不隐藏断言
│  └─ specs/                          # E01-E08
├─ contracts/
│  ├─ baseline/halo-2.26-openapi.json # 人工确认后的固定基线
│  └─ openapi-check/                  # 结构化破坏性差异检查器及单元测试
├─ .github/workflows/
│  ├─ quality-gate.yml                # L0-L2 合并门禁
│  └─ nightly.yml                     # L3 双浏览器、全量 API、稳定性
├─ docs/
│  ├─ test-strategy.md                # 28+10 场景台账和分层依据
│  ├─ failure-triage.md               # 五类失败的判定与证据
│  └─ upstream-contributions.md       # 只记录真实公开链接及状态
├─ docs/superpowers/
│  ├─ specs/2026-08-31-halo-quality-engineering-design.md
│  └─ plans/2026-08-31-halo-quality-engineering-mvp.md
└─ README.md                           # 可复现命令、边界、报告和真实成果
```

### Task 1: Bootstrap the Independent Repository and Deterministic Run Identity

**Files:**
- Create: `settings.gradle.kts`
- Create: `build.gradle.kts`
- Create: `api-tests/build.gradle.kts`
- Create: `api-tests/src/test/java/dev/quality/halo/support/RunIdentityTest.java`
- Create: `api-tests/src/test/java/dev/quality/halo/support/RunIdentity.java`
- Create by verbatim copy: `docs/superpowers/specs/2026-08-31-halo-quality-engineering-design.md`
- Create by verbatim copy: `docs/superpowers/plans/2026-08-31-halo-quality-engineering-mvp.md`
- Create: `.gitignore`

**Interfaces:**
- Produces: `RunIdentity.create(Clock clock, String workerId): RunIdentity`
- Produces: `RunIdentity.prefix(): String` matching `qe-[0-9]{8}t[0-9]{6}z-[a-z0-9-]+-[0-9a-f]{8}`
- Produces: Gradle tasks `:api-tests:test`, `:api-tests:integrationTest`, `:api-tests:smokeTest`

- [ ] **Step 1: Create the repository and write the failing identity test**

Run `git init halo-quality-engineering`, enter that directory, copy the confirmed spec and this plan verbatim into the two `docs/superpowers` paths above, create the Gradle wrapper with `gradle wrapper --gradle-version 8.14`, and add this test:

```java
package dev.quality.halo.support;

import static org.assertj.core.api.Assertions.assertThat;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

class RunIdentityTest {
    @Test
    void createsSafeDistinctPrefixesForParallelWorkers() {
        Clock fixed = Clock.fixed(Instant.parse("2026-08-31T01:02:03Z"), ZoneOffset.UTC);
        RunIdentity first = RunIdentity.create(fixed, "chromium-1");
        RunIdentity second = RunIdentity.create(fixed, "firefox-2");

        assertThat(first.prefix()).matches("qe-20260831t010203z-chromium-1-[0-9a-f]{8}");
        assertThat(second.prefix()).matches("qe-20260831t010203z-firefox-2-[0-9a-f]{8}");
        assertThat(first.prefix()).isNotEqualTo(second.prefix());
    }
}
```

- [ ] **Step 2: Run the test and verify the missing type**

Run: `./gradlew :api-tests:test --tests '*RunIdentityTest'`

Expected: FAIL during `compileTestJava` because `RunIdentity` does not exist.

- [ ] **Step 3: Add the minimal Gradle configuration and identity implementation**

Use Java toolchains with language version 21, JUnit Platform, and test tags: ordinary `test` excludes `integration`/`smoke`; `integrationTest` includes `integration`; `smokeTest` includes `smoke`. Implement:

```java
package dev.quality.halo.support;

import java.time.Clock;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;
import java.util.UUID;

public record RunIdentity(String runId, String workerId) {
    private static final DateTimeFormatter FORMAT =
            DateTimeFormatter.ofPattern("yyyyMMdd'T'HHmmss'Z'").withZone(ZoneOffset.UTC);

    public static RunIdentity create(Clock clock, String workerId) {
        String safeWorker = workerId.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9-]", "-");
        String run = FORMAT.format(clock.instant()).toLowerCase(Locale.ROOT)
                + "-" + UUID.randomUUID().toString().substring(0, 8);
        return new RunIdentity(run, safeWorker);
    }

    public String prefix() {
        return "qe-" + runId + "-" + workerId;
    }
}
```

Dependencies are pinned through the JUnit BOM `5.12.2`, RestAssured `5.5.1`, AssertJ `3.27.3`, Jackson BOM `2.18.3`, and MockWebServer `4.12.0`.

- [ ] **Step 4: Verify the bootstrap**

Run: `./gradlew :api-tests:test`

Expected: PASS with one test and JVM toolchain 21.

- [ ] **Step 5: Commit**

```bash
git add .gitignore settings.gradle.kts build.gradle.kts gradle gradlew gradlew.bat api-tests docs/superpowers
git commit -m "build: bootstrap Halo quality engineering tests"
```

### Task 2: Reproducible Halo and PostgreSQL Environment

**Files:**
- Create: `environment/docker-compose.yml`
- Create: `scripts/pin-images.ps1`
- Create: `scripts/environment.ps1`
- Create after running the pin script: `environment/image-lock.env`
- Test: `api-tests/src/test/java/dev/quality/halo/environment/EnvironmentSmokeTest.java`

**Interfaces:**
- Consumes: Gradle `smokeTest` task from Task 1
- Produces: `scripts/environment.ps1 -Action Up|Down|Logs|Initialize`
- Produces: Halo base URL `http://127.0.0.1:8090`
- Produces: setup account `qe-admin` / `HaloQE!2026` only inside the disposable environment

- [ ] **Step 1: Write the failing HTTP readiness smoke test**

```java
@Tag("smoke")
class EnvironmentSmokeTest {
    @Test
    void setupEndpointIsReachable() throws Exception {
        var request = HttpRequest.newBuilder(URI.create("http://127.0.0.1:8090/system/setup"))
                .header("Accept", "text/html").GET().build();
        var response = HttpClient.newHttpClient().send(request, HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isIn(200, 302);
    }
}
```

- [ ] **Step 2: Confirm the environment test fails before containers start**

Run: `./gradlew :api-tests:smokeTest --tests '*EnvironmentSmokeTest'`

Expected: FAIL with a connection-refused exception for port `8090`.

- [ ] **Step 3: Add digest locking and Compose lifecycle**

`pin-images.ps1` must pull `halohub/halo:2.26` and `postgres:16.8-alpine`, read the first value from `.RepoDigests`, require `@sha256:[0-9a-f]{64}`, and generate the lock file with this logic:

```powershell
$images = [ordered]@{
    HALO_IMAGE = 'halohub/halo:2.26'
    POSTGRES_IMAGE = 'postgres:16.8-alpine'
}
$lines = foreach ($entry in $images.GetEnumerator()) {
    docker pull $entry.Value
    if ($LASTEXITCODE -ne 0) { throw "Unable to pull $($entry.Value)" }
    $digest = docker image inspect --format '{{index .RepoDigests 0}}' $entry.Value
    if ($digest -notmatch '@sha256:[0-9a-f]{64}$') { throw "Missing RepoDigest for $($entry.Value)" }
    "$($entry.Key)=$digest"
}
$temporaryLock = 'environment/image-lock.env.new'
$lines | Set-Content -LiteralPath $temporaryLock -Encoding ascii
Move-Item -LiteralPath $temporaryLock -Destination 'environment/image-lock.env' -Force
```

The script writes only after both digests pass validation, so a failed pull preserves the previous lock. `docker-compose.yml` consumes `${HALO_IMAGE:?run scripts/pin-images.ps1}` and `${POSTGRES_IMAGE:?run scripts/pin-images.ps1}`, exposes Halo on `127.0.0.1:8090`, and uses:

```yaml
environment:
  SPRING_R2DBC_URL: r2dbc:pool:postgresql://postgres:5432/halo
  SPRING_R2DBC_USERNAME: halo
  SPRING_R2DBC_PASSWORD: halo-qe-local
  SPRING_SQL_INIT_PLATFORM: postgresql
  HALO_EXTERNAL_URL: http://127.0.0.1:8090/
  SPRINGDOC_API_DOCS_ENABLED: "true"
  SERVER_REACTIVE_SESSION_TIMEOUT: ${HALO_SESSION_TIMEOUT:-PT30M}
```

`environment.ps1 -Action Up` runs Compose with `--env-file environment/image-lock.env`, then polls `GET /system/setup` every 2 seconds for at most 180 seconds. `-Action Initialize` submits URL-encoded fields `username=qe-admin`, `password=HaloQE!2026`, `email=qe-admin@example.test`, `siteTitle=Halo QE`, `language=en`, and `externalUrl=http://127.0.0.1:8090/`; HTTP 204 and an already-initialized 302 are both accepted.

- [ ] **Step 4: Pin, start, and verify**

Run:

```powershell
pwsh ./scripts/pin-images.ps1
pwsh ./scripts/environment.ps1 -Action Up
./gradlew :api-tests:smokeTest --tests '*EnvironmentSmokeTest'
pwsh ./scripts/environment.ps1 -Action Initialize
```

Expected: the smoke test PASSes; initialization returns 204 on a fresh volume and the admin Basic Auth request to `/apis/api.console.halo.run/v1alpha1/users/-` returns 200.

- [ ] **Step 5: Commit the public digest lock and environment files**

```bash
git add environment scripts/pin-images.ps1 scripts/environment.ps1 api-tests/src/test/java/dev/quality/halo/environment
git commit -m "feat: add reproducible Halo test environment"
```

### Task 3: Resource Isolation, Reverse Cleanup, and Evidence Redaction

**Files:**
- Create: `api-tests/src/test/java/dev/quality/halo/support/ResourceRef.java`
- Create: `api-tests/src/test/java/dev/quality/halo/support/ResourceLedger.java`
- Create: `api-tests/src/test/java/dev/quality/halo/support/EvidenceRedactor.java`
- Test: `api-tests/src/test/java/dev/quality/halo/support/ResourceLedgerTest.java`
- Test: `api-tests/src/test/java/dev/quality/halo/support/EvidenceRedactorTest.java`

**Interfaces:**
- Consumes: `RunIdentity.prefix()`
- Produces: `ResourceRef(String apiGroup, String version, String plural, String name)`
- Produces: `ResourceLedger.record(ResourceRef): void`
- Produces: `ResourceLedger.cleanup(ThrowingConsumer<ResourceRef>): List<CleanupFailure>` in reverse creation order
- Produces: `EvidenceRedactor.redactHeaders(Map<String,List<String>>): Map<String,List<String>>`
- Produces: `EvidenceRedactor.redactJson(String): String`

- [ ] **Step 1: Write failing cleanup and redaction tests**

```java
@Test
void cleanupRunsInReverseAndKeepsEveryFailure() {
    var ledger = new ResourceLedger();
    ledger.record(new ResourceRef("halo.run", "v1alpha1", "users", "user-a"));
    ledger.record(new ResourceRef("content.halo.run", "v1alpha1", "posts", "post-b"));
    List<String> calls = new ArrayList<>();

    var failures = ledger.cleanup(ref -> {
        calls.add(ref.name());
        if (ref.name().equals("post-b")) throw new IOException("delete failed");
    });

    assertThat(calls).containsExactly("post-b", "user-a");
    assertThat(failures).extracting(CleanupFailure::resourceName).containsExactly("post-b");
}

@Test
void removesCredentialsFromHeadersAndJson() {
    assertThat(EvidenceRedactor.redactHeaders(Map.of(
            "Authorization", List.of("Basic c2VjcmV0"), "X-Run-Id", List.of("r1"))))
            .containsEntry("Authorization", List.of("[REDACTED]"));
    assertThat(EvidenceRedactor.redactJson("{\"password\":\"secret\",\"title\":\"ok\"}"))
            .isEqualTo("{\"password\":\"[REDACTED]\",\"title\":\"ok\"}");
}
```

- [ ] **Step 2: Verify both types are missing**

Run: `./gradlew :api-tests:test --tests '*ResourceLedgerTest' --tests '*EvidenceRedactorTest'`

Expected: FAIL during compilation because `ResourceLedger` and `EvidenceRedactor` do not exist.

- [ ] **Step 3: Implement deterministic cleanup and structured JSON redaction**

Use `ArrayDeque<ResourceRef>`, `addFirst`, and continue after exceptions. Implement JSON redaction by parsing with Jackson and recursively replacing values whose case-insensitive key is one of `password`, `authorization`, `cookie`, `set-cookie`, `token`, or `storageState`; do not use regular expressions to edit JSON.

```java
public final class ResourceLedger {
    private final Deque<ResourceRef> resources = new ArrayDeque<>();
    public void record(ResourceRef ref) { resources.addFirst(ref); }
    public List<CleanupFailure> cleanup(ThrowingConsumer<ResourceRef> delete) {
        List<CleanupFailure> failures = new ArrayList<>();
        resources.forEach(ref -> {
            try { delete.accept(ref); }
            catch (Exception error) { failures.add(new CleanupFailure(ref.name(), error.getMessage())); }
        });
        return List.copyOf(failures);
    }
}
```

- [ ] **Step 4: Run support tests**

Run: `./gradlew :api-tests:test --tests 'dev.quality.halo.support.*'`

Expected: PASS; the original assertion failure and cleanup failures can be represented independently.

- [ ] **Step 5: Commit**

```bash
git add api-tests/src/test/java/dev/quality/halo/support
git commit -m "test: add isolated resource ledger and evidence redaction"
```

### Task 4: Typed Halo API Client and Account/Post Fixtures

**Files:**
- Create: `api-tests/src/test/java/dev/quality/halo/client/Credentials.java`
- Create: `api-tests/src/test/java/dev/quality/halo/client/HaloApi.java`
- Create: `api-tests/src/test/java/dev/quality/halo/client/PostPayloads.java`
- Create: `api-tests/src/test/java/dev/quality/halo/support/HaloFixture.java`
- Test: `api-tests/src/test/java/dev/quality/halo/client/HaloApiWireTest.java`
- Test: `api-tests/src/test/java/dev/quality/halo/client/HaloApiContractIT.java`

**Interfaces:**
- Consumes: `RunIdentity`, `ResourceLedger`, `EvidenceRedactor`
- Produces: `HaloApi(URI baseUri, Credentials credentials)`
- Produces: `Response createUser(String name, String email, String password, Set<String> roles)`
- Produces: `Response grantRoles(String name, Set<String> roles)`, `disableUser(String)`, `enableUser(String)`
- Produces: `Response draftPost(String name, String owner, String title, String slug)`
- Produces: `Response publishPost(String)`, `unpublishPost(String)`, `recyclePost(String)`
- Produces: `Response consolePost(String)`, `publicPost(String)`, `headContent(String)`, `updatePost(String, JsonNode)`, `deleteExtension(ResourceRef)`
- Produces: `HaloFixture.createRoles(): RoleUsers` where `RoleUsers` contains admin, author, and readonly credentials

- [ ] **Step 1: Write a MockWebServer test for exact paths and payloads**

```java
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
    assertThat(body.at("/content/rawType").asText())
            .isEqualTo("HTML");
}
```

- [ ] **Step 2: Verify the client test fails**

Run: `./gradlew :api-tests:test --tests '*HaloApiWireTest'`

Expected: FAIL during compilation because `HaloApi` and `Credentials` do not exist.

- [ ] **Step 3: Implement the client with the confirmed Halo 2.26 routes**

`PostPayloads.draft` returns this shape, with `name`, `owner`, `title`, `slug`, and HTML content supplied by arguments:

```json
{
  "post": {
    "apiVersion": "content.halo.run/v1alpha1",
    "kind": "Post",
    "metadata": {"name": "p1"},
    "spec": {
      "title": "Title", "slug": "title", "owner": "qe-admin",
      "deleted": false, "publish": false, "pinned": false,
      "allowComment": true, "visible": "PUBLIC", "priority": 0,
      "excerpt": {"autoGenerate": true, "raw": ""},
      "categories": [], "tags": [], "htmlMetas": []
    }
  },
  "content": {"raw": "<p>Title</p>", "content": "<p>Title</p>", "rawType": "HTML"}
}
```

Use these confirmed routes:

```text
POST /apis/api.console.halo.run/v1alpha1/users
POST /apis/api.console.halo.run/v1alpha1/users/{name}/permissions
POST /apis/console.api.security.halo.run/v1alpha1/users/{name}/disable
POST /apis/console.api.security.halo.run/v1alpha1/users/{name}/enable
POST /apis/api.console.halo.run/v1alpha1/posts
PUT  /apis/api.console.halo.run/v1alpha1/posts/{name}/publish
PUT  /apis/api.console.halo.run/v1alpha1/posts/{name}/unpublish
PUT  /apis/api.console.halo.run/v1alpha1/posts/{name}/recycle
GET  /apis/content.halo.run/v1alpha1/posts/{name}
GET  /apis/api.content.halo.run/v1alpha1/posts/{name}
GET  /apis/api.console.halo.run/v1alpha1/posts/{name}/head-content
PUT  /apis/api.console.halo.run/v1alpha1/posts/{name}
```

Create the author with `role-template-post-author` and `role-template-post-contributor`; create readonly with an empty role set. Every RestAssured filter writes redacted request/response evidence under `build/evidence/{runId}/{testId}/`.

- [ ] **Step 4: Verify wire format and live fixture creation**

Run:

```powershell
./gradlew :api-tests:test --tests '*HaloApiWireTest'
./gradlew :api-tests:integrationTest --tests '*HaloApiContractIT'
```

Expected: both PASS; the integration test creates uniquely named author and readonly users, reads them with Basic Auth, then deletes them in reverse order.

- [ ] **Step 5: Commit**

```bash
git add api-tests/src/test/java/dev/quality/halo/client api-tests/src/test/java/dev/quality/halo/support/HaloFixture.java
git commit -m "feat: add typed Halo API fixtures"
```

### Task 5: 28 API Scenarios for Authentication, Lifecycle, and RBAC

**Files:**
- Create: `docs/test-strategy.md`
- Create: `api-tests/src/test/java/dev/quality/halo/auth/AuthenticationIT.java`
- Create: `api-tests/src/test/java/dev/quality/halo/posts/PostLifecycleIT.java`
- Create: `api-tests/src/test/java/dev/quality/halo/permissions/PostPermissionIT.java`
- Create: `api-tests/src/test/java/dev/quality/halo/support/Eventually.java`
- Test: the three integration classes above

**Interfaces:**
- Consumes: all `HaloApi` and `HaloFixture` methods from Task 4
- Produces: `Eventually.until(Duration deadline, Duration initialDelay, Supplier<Response>, Predicate<Response>): Response`
- Produces: scenario IDs `A01-A08`, `P01-P11`, `R01-R09` in JUnit display names and evidence paths

- [ ] **Step 1: Write the exact scenario ledger and the first failing lifecycle test**

The ledger contains exactly these MVP cases:

```text
A01 admin valid credentials=200; A02 wrong password=401; A03 missing auth=401;
A04 author valid credentials=200; A05 readonly valid identity endpoint=200;
A06 disabled author=401; A07 denied disabled request creates no post; A08 re-enabled author=200.
P01 create draft phase=DRAFT; P02 draft public API=404; P03 publish phase=PUBLISHED;
P04 public API title/slug match; P05 status.permalink serves title; P06 unpublish sets publish=false;
P07 unpublished public API=404; P08 recycle sets deleted=true and public=404;
P09 publish unknown name=404; P10 two publish calls preserve one releaseSnapshot and one public resource;
P11 two concurrent extension PUTs carrying the same metadata.version yield one success and one 409, with no mixed title/content state.
R01 admin creates draft; R02 author creates own draft; R03 readonly create is denied;
R04 R03 leaves no resource; R05 author without publisher role cannot publish;
R06 R05 leaves the post in DRAFT; R07 admin can publish author's post;
R08 author cannot update another owner's post; R09 unauthenticated create is denied.
```

Start with:

```java
@Test
@DisplayName("P02 draft is absent from public API")
void draftIsNotPublic() {
    String name = fixture.unique("p02");
    admin.draftPost(name, admin.credentials().username(), "P02 " + name, name).then().statusCode(200);
    admin.publicPost(name).then().statusCode(404);
}
```

- [ ] **Step 2: Verify P02 fails before fixture lifecycle wiring exists**

Run: `./gradlew :api-tests:integrationTest --tests '*PostLifecycleIT.draftIsNotPublic'`

Expected: FAIL because the shared fixture extension and cleanup callback are not wired into the class.

- [ ] **Step 3: Implement deadline-based polling and all ledger cases**

`Eventually.until` uses `System.nanoTime()`, starts at 100 ms, doubles to a maximum 1 second, and stops at a 15-second deadline. It never resends mutating requests; only `GET` observations are passed to it.

```java
static Response waitForPublic(HaloApi api, String name, int status) {
    return Eventually.until(Duration.ofSeconds(15), Duration.ofMillis(100),
            () -> api.publicPost(name), response -> response.statusCode() == status);
}

@Test
@DisplayName("R05 author without publisher role cannot publish")
void authorCannotPublish() {
    String name = fixture.unique("r05");
    author.draftPost(name, author.credentials().username(), "R05 " + name, name).then().statusCode(200);
    author.publishPost(name).then().statusCode(anyOf(is(401), is(403)));
    author.consolePost(name).then().body("status.phase", equalTo("DRAFT"));
}
```

For every denial, first record the pre-operation `metadata.version` and `status.phase`, execute the denied request, then re-read and assert both state and resource count are unchanged. `P10` issues the second publish only after the first reaches `PUBLISHED`, then compares `spec.releaseSnapshot` from both responses.

`P11` reads one authenticated extension representation and its head content, creates two complete `PostRequest` bodies from the same `metadata.version` and content version, gives them distinct title/content pairs, starts both Console update requests behind one `CountDownLatch`, and asserts HTTP statuses contain exactly one 200 and one 409. Final extension GET plus `head-content` GET must equal one complete pair, never title from one request and content from the other.

- [ ] **Step 4: Run all API scenarios twice in the same environment**

Run:

```powershell
./gradlew :api-tests:integrationTest
./gradlew :api-tests:integrationTest
```

Expected: both runs PASS; JUnit XML contains 28 scenario display names, and the second run has distinct resource names with no collision from the first.

- [ ] **Step 5: Commit**

```bash
git add docs/test-strategy.md api-tests/src/test/java/dev/quality/halo/auth api-tests/src/test/java/dev/quality/halo/posts api-tests/src/test/java/dev/quality/halo/permissions api-tests/src/test/java/dev/quality/halo/support/Eventually.java
git commit -m "test: cover Halo lifecycle and permission matrix"
```

### Task 6: Playwright Role Fixtures and Ten Core Journeys

**Files:**
- Create: `e2e/package.json`
- Create: `e2e/tsconfig.json`
- Create: `e2e/playwright.config.ts`
- Create: `e2e/fixtures/auth.setup.ts`
- Create: `e2e/fixtures/halo-api.ts`
- Create: `e2e/fixtures/test.ts`
- Create: `e2e/pages/login-page.ts`
- Create: `e2e/pages/posts-page.ts`
- Create: `e2e/specs/auth.spec.ts`
- Create: `e2e/specs/posts.spec.ts`

**Interfaces:**
- Consumes: Halo routes and role definitions from Tasks 2 and 4
- Produces: `HaloApi.createDraft(owner, scenarioId): Promise<PostRef>` and `cleanup(): Promise<CleanupFailure[]>`
- Produces: `LoginPage.login(username, password): Promise<void>`
- Produces: `PostsPage.open()`, `publish(title)`, `unpublish(title)`; these methods perform actions only
- Produces: storage states `e2e/.auth/admin.json`, `author.json`, `readonly.json`, all ignored by Git

- [ ] **Step 1: Write E01 and a Playwright configuration with no retries**

```ts
// e2e/playwright.config.ts
export default defineConfig({
  testDir: './specs', retries: 0, workers: process.env.CI ? 2 : 1,
  use: {
    baseURL: process.env.HALO_BASE_URL ?? 'http://127.0.0.1:8090',
    trace: 'retain-on-failure', screenshot: 'only-on-failure', video: 'retain-on-failure'
  },
  reporter: [['html', { outputFolder: 'artifacts/html-report', open: 'never' }], ['junit', { outputFile: 'artifacts/junit.xml' }]],
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.ts/ },
    { name: 'chromium', use: { ...devices['Desktop Chrome'] }, dependencies: ['setup'] }
  ]
});
```

```ts
test('E01 admin login reaches console', async ({ page }) => {
  const login = new LoginPage(page);
  await login.open();
  await login.login('qe-admin', 'HaloQE!2026');
  await expect(page).toHaveURL(/\/console(?:\/|$)/);
});
```

- [ ] **Step 2: Run E01 and verify the missing Page Object**

Run: `pnpm --dir e2e install && pnpm --dir e2e exec playwright test specs/auth.spec.ts --grep E01`

Expected: FAIL during TypeScript compilation because `LoginPage` does not exist.

- [ ] **Step 3: Implement role-isolated fixtures and Page Objects**

`LoginPage` uses `getByLabel('Account')`, `getByLabel('Password')`, and `getByRole('button', {name: 'Login'})`. `auth.setup.ts` creates a fresh browser context per role and verifies the returned identity before saving each state. `HaloApi` records resources with the same `qe-{runId}-{workerId}` convention and deletes them in reverse order after each test.

Implement these ten independent journeys:

```text
E01 admin logs in and reaches /console.
E02 wrong password shows role=alert text "Invalid credentials." and remains unauthenticated.
E03 author storageState opens the Posts page but readonly storageState is redirected from /console.
E04 author creates a draft through the editor; API observation reports DRAFT.
E05 admin publishes an API-prepared draft through Posts; API and status.permalink become public.
E06 an API-published post title is visible at its exact status.permalink in a fresh anonymous context.
E07 admin unpublishes through Posts; public API and anonymous permalink cease to expose the post.
E08 readonly directly calls POST /apis/api.console.halo.run/v1alpha1/posts from page.request, receives 401/403, and resource GET remains 404.
E09 admin chooses the accessible-name "Logout" action, confirms it, and the former context is redirected to Login on the next /console visit.
E10 a login session left idle beyond a dedicated PT5S environment's timeout is redirected to Login; tag this test `@session-expiry`, wait on local monotonic elapsed-time with expect.poll, and make no authenticated server request during the idle interval. The ordinary environment remains PT30M so this test cannot destabilize other journeys.
```

Use `getByRole('link', {name: 'Posts'})`, `getByRole('button', {name: 'New Post'})`, `getByLabel('Title')`, `getByRole('button', {name: 'Save'})`, and `getByRole('button', {name: 'Publish'})`. Assertions remain in spec files; Page Objects contain no `expect` calls and no timeout-based waits.

- [ ] **Step 4: Run all Chromium journeys without retry**

Run the ordinary journeys, then recreate only the disposable environment for the expiry journey:

```powershell
pnpm --dir e2e exec playwright test --project=chromium --grep-invert '@session-expiry'
pwsh ./scripts/environment.ps1 -Action Down
$env:HALO_SESSION_TIMEOUT = 'PT5S'
pwsh ./scripts/environment.ps1 -Action Up
pwsh ./scripts/environment.ps1 -Action Initialize
pnpm --dir e2e exec playwright test --project=chromium --grep '@session-expiry' --no-deps
Remove-Item Env:HALO_SESSION_TIMEOUT
```

Expected: 9 ordinary tests and 1 session-expiry test PASS, `retries` is 0 in both reports, and three role state files remain untracked because `e2e/.auth/` is ignored.

- [ ] **Step 5: Commit**

```bash
git add .gitignore e2e
git commit -m "test: add role-isolated Halo browser journeys"
```

### Task 7: OpenAPI Breaking-Change Detector

**Files:**
- Create: `contracts/openapi-check/check.mjs`
- Create: `contracts/openapi-check/check.test.mjs`
- Create: `contracts/openapi-check/fixtures/base.json`
- Create: `contracts/openapi-check/fixtures/remove-field.json`
- Create: `contracts/openapi-check/fixtures/add-optional.json`
- Create after review: `contracts/baseline/halo-2.26-openapi.json`
- Create: `scripts/capture-openapi.ps1`

**Interfaces:**
- Produces: `findBreakingChanges(baseline, candidate): BreakingChange[]`
- Produces: `BreakingChange { kind: 'PATH_REMOVED'|'METHOD_REMOVED'|'SCHEMA_REMOVED'|'PROPERTY_REMOVED'|'PROPERTY_REQUIRED'|'TYPE_CHANGED', pointer: string, before?: string, after?: string }`
- Consumes: `GET /v3/api-docs/apis_aggregated.api_v1alpha1`

- [ ] **Step 1: Write node:test cases for one breaking and one compatible change**

```js
test('removed property is breaking', () => {
  const changes = findBreakingChanges(read('base.json'), read('remove-field.json'));
  assert.deepEqual(changes, [{
    kind: 'PROPERTY_REMOVED', pointer: '#/components/schemas/Post/properties/spec'
  }]);
});

test('new optional property is compatible', () => {
  assert.deepEqual(findBreakingChanges(read('base.json'), read('add-optional.json')), []);
});
```

- [ ] **Step 2: Verify the exported function is missing**

Run: `node --test contracts/openapi-check/check.test.mjs`

Expected: FAIL because `check.mjs` does not export `findBreakingChanges`.

- [ ] **Step 3: Implement structural comparison and baseline capture**

Parse JSON with `JSON.parse`; compare `paths`, HTTP methods, `components.schemas`, schema `properties`, `required`, and property `type`. Sort findings by `pointer` then `kind`, print JSON to stdout, and exit 2 when findings are non-empty. `capture-openapi.ps1` downloads the endpoint, parses and reserializes JSON with stable key order, and refuses to overwrite the baseline unless `-AcceptReviewedBaseline` is passed.

- [ ] **Step 4: Prove pass and fail behavior, then capture the actual baseline**

Run:

```powershell
node --test contracts/openapi-check/check.test.mjs
node contracts/openapi-check/check.mjs contracts/openapi-check/fixtures/base.json contracts/openapi-check/fixtures/remove-field.json
pwsh ./scripts/capture-openapi.ps1 -AcceptReviewedBaseline
node contracts/openapi-check/check.mjs contracts/baseline/halo-2.26-openapi.json contracts/baseline/halo-2.26-openapi.json
```

Expected: unit tests PASS; the known removal exits 2 and reports `PROPERTY_REMOVED`; identical real baselines exit 0.

- [ ] **Step 5: Commit**

```bash
git add contracts scripts/capture-openapi.ps1
git commit -m "feat: detect breaking Halo OpenAPI changes"
```

### Task 8: Failure Classification and Evidence Collection

**Files:**
- Create: `scripts/collect-evidence.ps1`
- Create: `docs/failure-triage.md`
- Create: `docs/quarantine.yaml`
- Create: `scripts/validate-quarantine.mjs`
- Create: `api-tests/src/test/java/dev/quality/halo/support/FailureClassifier.java`
- Test: `api-tests/src/test/java/dev/quality/halo/support/FailureClassifierTest.java`

**Interfaces:**
- Produces: `FailureClassifier.classify(Throwable, Optional<Response>): ENVIRONMENT|PRODUCT|CONTRACT|TEST_TOOL|FLAKY_CANDIDATE`
- Produces: `artifacts/environment/docker-ps.txt`, `halo.log`, `postgres.log`, `health.json`
- Consumes: `EvidenceRedactor` key policy from Task 3

- [ ] **Step 1: Write classification tests**

```java
@ParameterizedTest
@MethodSource("cases")
void classifiesByEvidence(Throwable error, Integer status, FailureKind expected) {
    Optional<Response> response = status == null ? Optional.empty() : Optional.of(response(status));
    assertThat(FailureClassifier.classify(error, response)).isEqualTo(expected);
}

static Stream<Arguments> cases() {
    return Stream.of(
        arguments(new ConnectException("refused"), null, ENVIRONMENT),
        arguments(new AssertionError("expected 403 but was 200"), 200, PRODUCT),
        arguments(new OpenApiBreakingChangeException("type changed"), null, CONTRACT),
        arguments(new JsonProcessingException("bad fixture") {}, null, TEST_TOOL)
    );
}
```

- [ ] **Step 2: Verify the classifier is absent**

Run: `./gradlew :api-tests:test --tests '*FailureClassifierTest'`

Expected: FAIL during compilation because `FailureClassifier` does not exist.

- [ ] **Step 3: Implement classification and evidence script**

Classification is deterministic: connection/health/startup exceptions are environment; OpenAPI findings are contract; assertion failures with a received product response are product; fixture serialization/cleanup failures are test-tool; `FLAKY_CANDIDATE` is assigned only by the stability task after identical input has both pass and fail outcomes. The script captures `docker compose ps --format json` and both container logs, then replaces Basic/Bearer tokens, Cookie values, and the fixed local password before writing artifacts.

`docs/quarantine.yaml` starts as `cases: []`. Every future entry must contain `testId`, public `issueUrl`, `owner`, `reason`, ISO-8601 `expiresAt`, and `restoreAfterGreenRuns` between 10 and 20. The validator exits 2 for missing fields or an expired entry. Quarantined cases run only in nightly, are excluded from the main-chain pass rate, and remain visible in GitHub Summary; L0 runs the validator so no expired isolation can be merged.

- [ ] **Step 4: Run unit tests and inspect the redacted bundle**

Run:

```powershell
./gradlew :api-tests:test --tests '*FailureClassifierTest'
pwsh ./scripts/collect-evidence.ps1
rg -n "HaloQE!2026|Authorization:|Cookie:" artifacts
```

Expected: tests PASS; the final `rg` returns no matches.

- [ ] **Step 5: Commit**

```bash
git add scripts/collect-evidence.ps1 scripts/validate-quarantine.mjs docs/failure-triage.md docs/quarantine.yaml api-tests/src/test/java/dev/quality/halo/support
git commit -m "feat: classify failures and collect redacted evidence"
```

### Task 9: Layered GitHub Actions Quality Gates

**Files:**
- Create: `.github/workflows/quality-gate.yml`
- Create: `.github/workflows/nightly.yml`
- Create: `scripts/quality-gate.ps1`
- Test: `.github/workflows/quality-gate.yml` via local command parity

**Interfaces:**
- Consumes: Gradle, Playwright, OpenAPI, environment, and evidence commands from Tasks 1-8
- Produces: L0 `contract`, L1 `api-smoke`, L2 `chromium-e2e`, L3 `nightly-regression`
- Produces: GitHub Summary rows `layer`, `result`, `durationSeconds`, `failureKind`, `artifactName`

- [ ] **Step 1: Add a local gate script that initially fails on a known contract removal**

The first script version calls the known failing fixture comparison before any tests.

Run: `pwsh ./scripts/quality-gate.ps1 -Layer L0`

Expected: exit 2 with `PROPERTY_REMOVED`; this proves the gate is capable of blocking.

- [ ] **Step 2: Replace the probe with the actual L0-L2 commands**

`quality-gate.ps1` uses `try/finally`: L0 runs Gradle compilation/unit tests and compares the live OpenAPI document to the committed baseline; L1 runs all 28 API cases; L2 runs Chromium E2E. On failure it invokes evidence collection; in all cases it invokes `environment.ps1 -Action Down`. It never reruns a failed test.

- [ ] **Step 3: Encode the same order in GitHub Actions**

Use `actions/checkout`, `actions/setup-java` with Java 21, `pnpm/action-setup`, `actions/setup-node` with Node 22, and Playwright Chromium installation. Upload JUnit XML, API evidence, Playwright report/trace/video, and container logs under distinct artifact names even when a previous step fails. Artifact uploads use `if: always()` with `continue-on-error: false`; GitHub Summary records test result and evidence-upload result separately, and the job is green only when both pass. Set job timeouts to 10 minutes for L0/L1 and 15 minutes for L2; record actual duration rather than claiming the design target was met.

- [ ] **Step 4: Run local parity and inspect generated evidence**

Run: `pwsh ./scripts/quality-gate.ps1 -Layer All`

Expected: L0, L1, and L2 PASS once each, no retry entry appears in JUnit or Playwright reports, and Compose has no running project containers after the command exits.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows scripts/quality-gate.ps1
git commit -m "ci: add layered Halo quality gates"
```

### Task 10: Nightly Dual-Browser and 20-Run Stability Evidence

**Files:**
- Modify: `e2e/playwright.config.ts`
- Modify: `.github/workflows/nightly.yml`
- Create: `scripts/stability.ps1`
- Create: `api-tests/src/test/java/dev/quality/halo/support/StabilityRecordTest.java`
- Create at execution time: `artifacts/stability/runs.jsonl`

**Interfaces:**
- Produces: Playwright project `firefox`
- Produces: `stability.ps1 -Runs 20 -Layer All`
- Produces: one JSONL record per independent run with `sequence`, `startedAt`, `commit`, `haloImage`, `result`, `durationSeconds`, `failureKind`

- [ ] **Step 1: Write a parser test that rejects fewer than 20 successful records**

```java
@Test
void requiresTwentyConsecutiveGreenRuns() throws Exception {
    var records = StabilityRecord.read(Path.of("src/test/resources/stability/nineteen-green.jsonl"));
    assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isFalse();
    records = StabilityRecord.read(Path.of("src/test/resources/stability/twenty-green.jsonl"));
    assertThat(StabilityRecord.hasConsecutiveGreen(records, 20)).isTrue();
}
```

- [ ] **Step 2: Verify the parser type is missing**

Run: `./gradlew :api-tests:test --tests '*StabilityRecordTest'`

Expected: FAIL during compilation because `StabilityRecord` does not exist.

- [ ] **Step 3: Implement the parser and stability runner**

Each iteration destroys volumes, starts and initializes a fresh environment, runs the requested layer once with retries disabled, writes one JSON object, and stops immediately on failure. A failed iteration is not reclassified as a retry. For `Layer All`, the runner also recreates one PT5S environment and executes E10 exactly once before declaring the iteration green. Add Firefox to the nightly workflow; PR workflows continue to run Chromium only.

- [ ] **Step 4: Execute the actual stability qualification**

Run: `pwsh ./scripts/stability.ps1 -Runs 20 -Layer All`

Expected: exactly 20 consecutive `result:"PASS"` records are required for acceptance. If any run fails, preserve all evidence, investigate under the failure-triage rules, fix the cause, and start a new 20-run sequence from record 1.

- [ ] **Step 5: Commit code and the factual run record**

```bash
git add e2e/playwright.config.ts .github/workflows/nightly.yml scripts/stability.ps1 api-tests/src/test artifacts/stability/runs.jsonl
git commit -m "test: qualify Halo gate stability across browsers"
```

### Task 11: Public Documentation and Factual Upstream Contribution

**Files:**
- Create: `README.md`
- Modify: `docs/test-strategy.md`
- Modify: `docs/failure-triage.md`
- Create: `docs/upstream-contributions.md`
- Create: `.github/ISSUE_TEMPLATE/halo-defect-evidence.md`
- Create: `scripts/verify-publication.ps1`

**Interfaces:**
- Consumes: actual CI URLs, reports, fixed image digest, measured durations, and confirmed defect/contribution evidence
- Produces: a publication check that rejects secrets, private host patterns, unverified result claims, and broken public links
- Produces: at least one real upstream Issue and one real upstream PR URL, with their current states stated independently

- [ ] **Step 1: Write the publication verifier before adding result claims**

`verify-publication.ps1` fails if tracked files contain IPv4 addresses outside loopback/documentation ranges, real credential/token patterns, committed `storageState`, enterprise names, or resume claims whose evidence link is absent. The declared synthetic local fixture password `HaloQE!2026` is permitted only in environment/test source; it is forbidden in `artifacts/`, reports, screenshots, contribution records, and README. The verifier also checks that every URL in `docs/upstream-contributions.md` returns HTTP 200/301/302 and that its visible state matches `OPEN`, `CLOSED`, `MERGED`, or `DRAFT` recorded beside the link.

Run: `pwsh ./scripts/verify-publication.ps1`

Expected: FAIL until README and contribution ledger contain only schema-compliant factual entries.

- [ ] **Step 2: Document reproducibility and measured results**

README includes prerequisites, one-command environment startup, L0-L3 commands, the 28+10 scenario map, architecture boundaries, evidence locations, non-goals, Halo commit/image digest, and actual measured durations read from reports. Do not copy design targets into the “results” section.

- [ ] **Step 3: Create a real Issue from confirmed evidence**

Select a reproducible product failure or a clearly motivated testability/documentation improvement discovered by the completed suite. Search existing Halo Issues/PRs first. The public Issue contains fixed Halo version and commit, minimal setup, exact request/action, expected and actual behavior, redacted evidence, and a link to the smallest reproducer. If no product defect exists, open an improvement Issue for a concrete regression-test, documentation, or testability gap confirmed against the inspected source; do not manufacture a failing behavior.

- [ ] **Step 4: Submit one single-purpose upstream PR**

Create a Halo fork branch tied to the Issue/OpenSpec, add the smallest product fix, regression test, documentation, or agreed testability improvement, run Halo's required Java/frontend formatting and test commands, and disclose substantive AI assistance in the PR description. Record `SUBMITTED` until the public page says merged; change to `MERGED` only after the upstream state changes.

- [ ] **Step 5: Verify the public record and commit documentation**

Run:

```powershell
pwsh ./scripts/verify-publication.ps1
./gradlew :api-tests:test
pnpm --dir e2e exec playwright test --list
```

Expected: publication verification PASSes, unit tests PASS, and Playwright lists exactly 10 non-setup journeys. Then commit:

```bash
git add README.md docs .github/ISSUE_TEMPLATE scripts/verify-publication.ps1
git commit -m "docs: publish verified Halo quality engineering evidence"
```

## Acceptance Check

Before calling the MVP complete, run:

```powershell
pwsh ./scripts/quality-gate.ps1 -Layer All
pwsh ./scripts/stability.ps1 -Runs 20 -Layer All
pwsh ./scripts/verify-publication.ps1
git status --short
```

The repository is complete only when the first three commands pass, `git status` is clean, JUnit reports contain all 28 API scenarios, Playwright reports contain all 10 journeys with zero retries, all failure types produce their required evidence, and the upstream ledger links to real public records. Comments and attachments remain P1 and are deliberately outside this MVP; adding them is a later independently specified milestone after the article chain is stable.
