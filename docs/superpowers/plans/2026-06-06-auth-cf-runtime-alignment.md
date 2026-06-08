# Auth / Cloudflare Runtime Alignment Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Fire 下一阶段双端运行时的登录态、后台踢出登录、Cloudflare challenge、自动续期和 WebView 手动验证收口到一条 Rust/openwire 权威网络链路，对齐 FluxDO v0.2.15 的 Dio/OkHttp 风格拦截器分层和保守 auth signal/probe 策略。

**Architecture:** Rust Core 拥有 session state、CookieJar、CSRF、auth signal classification、probe、passive logout、Cloudflare 分类、请求重试和 openwire interceptor 编排。iOS / Android 只拥有 WebView 登录、Cloudflare challenge 完成、平台 cookie 提取、可见 UI 和错误展示。平台不得自行把普通 403、CSRF、Cloudflare、`discourse-logged-out` 推断成登出。

**Tech Stack:** Rust + openwire + UniFFI + tokio / Swift + WebKit / Kotlin + Android WebView + androidx

**Design Inputs:**
- `docs/knowledge/api-overview.md`
- `docs/knowledge/api/01-global-conventions.md`
- `docs/knowledge/api/02-auth-and-session.md`
- `docs/architecture/fire-native-architecture.md`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/network/discourse_dio.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/discourse/_auth.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/network/cookie/app_cookie_manager.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/network/interceptors/cf_challenge_interceptor.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/cf_challenge_service.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/network/cookie/boundary_sync_service.dart`
- FluxDO v0.2.15 reference: `references/fluxdo/lib/services/network/interceptors/redirect_interceptor.dart`

---

## Audit Corrections (2026-06-06)

本计划基于当前 Fire 和 FluxDO v0.2.15 源码审查结果，以下事项为**强约束**：

- FluxDO v0.2.15 已经不是“任意 `discourse-logged-out` 即登出”的旧策略；它统一通过 auth signal、strike、`GET /session/current.json` probe 二次验证，避免 cookie 传输瞬时问题和 token rotation 窗口误判。Fire 下一阶段应对齐这条模型。
- Auth signal 强弱必须分开：`not_logged_in` / `401|403 + discourse-logged-out` 是强信号，1 次触发 probe；`2xx/3xx + discourse-logged-out` 是 mixed/弱信号，2 次累积后触发 probe。
- Probe 结果必须三态化：valid 保持登录并重置 strike；invalid 执行被动登出；inconclusive 先进入冷却期，若当前 strike 已累计到 FluxDO v0.2.15 的升级阈值（2 次）才升级为被动登出。
- `BAD CSRF` 只属于 CSRF 分支：清空 CSRF token，刷新 `/session/csrf`，重试原请求一次。不得触发登录弹窗、不得清登录态。
- `invalid_access` / 普通 `403` 是权限失败，不是后台踢出登录。
- 成功 `2xx` `/session/csrf` 即使带 `discourse-logged-out` 或清 cookie，也不立即登出；它是 mixed/弱 auth signal。会话 cookie 删除需要被拦截，最终是否登出由 probe 机制决定。
- Cloudflare challenge 判定必须同时依赖 Cloudflare 响应头和 HTML/body 特征，避免把帖子内容或 Discourse 自身 403 误判为 CF。
- WebView cookie 只在边界同步：登录完成、Cloudflare 验证完成、明确的 host cookie repair。不得常态轮询 WebView cookie 来覆盖 Rust session。
- Redirect 已完成差异审计：openwire 内置 follow-up 已覆盖 Fire 当前所需行为，不需要在 Fire 侧复制 FluxDO 的 `RedirectInterceptor`。若未来需要改变 redirect request 的 `Cookie` header 处理，应优先在 openwire 加可配置策略，而不是在 Fire app 层手写二次请求。
- 登录页下方用于测试的“恢复已有会话”入口必须删除，启动登录态恢复只由 PreheatGate / Rust startup authority 处理。

## Implementation Status (2026-06-06)

- 已落地：Android onboarding 删除隐藏的 `restore_session_button`、`onboarding_restore_session`、旧 `bootstrapping_layout`、旧 `error_banner`、只服务这些死 UI 的 `AuthViewModel`、`bg_error_banner`、未使用的 `action_onboarding_to_home` 和残留 `action_restore_session` 字符串。
- 已核对：iOS onboarding/login 没有生产级“恢复已有会话”入口；Developer Tools 的“恢复会话”只会重新执行 `loadInitialState()` 诊断路径。
- 已存在：Rust `is_cloudflare_challenge_response()` 已按 `403/429 + server=cloudflare + text/html + cf-mitigated/body` 分类 CF。
- 已存在：Rust `execute_api_request_with_csrf_retry()` 已做缺失 CSRF 预刷新和 `BAD CSRF` 一次重试。
- 已存在：Rust `response_login_invalidation_error()` 已把 `not_logged_in` 与普通 `invalid_access` 分开，且不会因成功 CSRF 响应直接登出。
- 已存在：Rust `AuthStrikeState`、`probe_session()`、`determine_login_state_with_probe()` 提供后台踢出登录判定雏形；需要按 FluxDO v0.2.15 明确三态 probe、mixed signal cookie deletion block 和 inconclusive escalation 语义。
- 已存在：iOS `FireCfClearanceRefreshService` 有登录态确认 gate 后的隐藏 Turnstile runtime；Android 尚无等价服务。
- 已存在：iOS `performWithCloudflareRecovery` / `performWriteWithCloudflareRetry` 目前只是直跑闭包，不会自动弹恢复 WebView；后续需要改名或接入新的 auth runtime handler，避免保留误导性命名。

---

## Runtime Signal Matrix

| 场景 | 信号 | 强度 | Rust 处理 | 平台处理 |
|---|---|---:|---|---|
| 本地无 `_t` / 无认证 cookie | `CookieSnapshot.can_authenticate_requests() == false` | terminal local | `NotLoggedIn`，不发认证写请求 | 显示登录入口 |
| 启动有 cookie 但无 current user | `/session/current.json` probe valid | terminal valid | 写入 current user，进入 logged-in | 进入主界面 |
| 启动 probe 404 / 无 `current_user` | `/session/current.json` invalid | terminal invalid | passive logout，保留 `cf_clearance` | 回 onboarding |
| 启动 probe 网络失败 / CF | inconclusive | none | 保留本地状态，暴露错误/诊断 | 不自动清登录态 |
| 后台踢出登录 | `401/403` JSON `error_type=not_logged_in` | strong | auth strike -> probe；probe invalid 或 inconclusive escalated 才 passive logout | 只消费最终 session state |
| 普通无权限 | `403` JSON `error_type=invalid_access` | none | 返回 `HttpStatus` / forbidden | 显示权限错误 |
| Discourse header | `401/403 + discourse-logged-out` | strong | 1 次触发 probe；不直接清 session cookie | 不自动弹登录 |
| Mixed logged-out signal | `2xx/3xx + discourse-logged-out` | weak | 记录 strike，拦截会话 cookie 删除，达到阈值后 probe | 平台不可见 |
| CSRF 坏 token | body `["BAD CSRF"]` | csrf only | 清 token -> 刷新 -> 重试一次 | 平台不可见 |
| CSRF 成功但带 logged-out | `2xx /session/csrf` + mixed signal | weak | 接受 CSRF token，拦截 cookie 删除，走弱 auth signal | 平台不可见 |
| Cloudflare challenge | `403/429` + CF headers + HTML/body marker | cf only | 触发 CF resolution path；不登出 | WebView 完成挑战并回灌 cookie |
| rate limit | `429` without CF challenge | rate only | backoff / classify rate limit | 显示稍后重试 |

## Target Interceptor Shape

FluxDO 的 Dio 链路是：

```text
SessionGuard -> RequestScheduler -> CookieManager -> retry/header/csrf
  -> Redirect -> Error -> CfChallenge -> NetworkLog
```

Fire 的 openwire 目标链路应收口为：

```text
RequestEpochGuard
  -> FireCommonHeaderInterceptor
  -> FireCookieJar / Set-Cookie ingress
  -> FireCsrfInterceptor
  -> FireRetry / RateLimit
  -> FireAuthSignalInterceptor
  -> FireCloudflareInterceptor
  -> Trace / Log
```

Redirect 不进入 Fire 侧 interceptor 链路。审计结果：openwire 的 `FollowUpPolicyService` 已提供默认 10 跳上限、HTTPS -> HTTP 降级保护、`301/302/303` method rewrite、`307/308` method/body preservation、跨 origin `Cookie` / `Authorization` 移除、以及每跳按目标 URL 重新走 `CookieJar` 的能力。Fire 当前不手动塞显式 `Cookie` header，因此不需要 FluxDO 式手动 redirect interceptor。

唯一保留边界：如果未来某个调用方显式写入 `Cookie` header，same-origin redirect 会保留该显式 header；这不是 Fire 当前路径。需要严格“每跳都清 Cookie header”时，应改 openwire redirect request policy。

---

## File Structure

| File | Responsibility |
|---|---|
| `rust/crates/fire-models/src/session.rs` | Auth signal、CF challenge request/result、runtime event models |
| `rust/crates/fire-models/src/cookie.rs` | Platform cookie scoring、low-confidence filtering、critical cookie helpers |
| `rust/crates/fire-core/src/core/network.rs` | HTTP status classification、CSRF retry、CF classification、auth-signal hook |
| `rust/crates/fire-core/src/core/auth.rs` | probe、passive logout、auth strike outcome policy |
| `rust/crates/fire-core/src/core/auth_strike.rs` | Strong/weak signal accumulation and cooldown |
| `rust/crates/fire-core/src/core/cf_challenge.rs` | NEW: challenge resolution orchestration and retry gate |
| `rust/crates/fire-core/src/core/session.rs` | WebView login finalization and boundary cookie application |
| `rust/crates/fire-uniffi-session/src/records.rs` | FFI records for auth runtime events and challenge outcomes |
| `rust/crates/fire-uniffi-session/src/lib.rs` | Register auth runtime handler and expose boundary sync methods |
| `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` | iOS hidden Turnstile refresh runtime |
| `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` | iOS login boundary sync |
| `native/ios-app/App/ViewModels/FireAppViewModel.swift` | iOS auth runtime host handler and UI routing |
| `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt` | Android login boundary sync |
| `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeCoordinator.kt` | NEW: Android manual CF WebView coordinator |
| `native/android-app/src/main/java/com/fire/app/session/FireCfClearanceRefreshService.kt` | NEW: Android hidden Turnstile refresh runtime |
| `native/android-app/src/main/java/com/fire/app/core/error/FireErrorHandling.kt` | Android error display, no local logout inference |
| `docs/knowledge/api/01-global-conventions.md` | Keep interceptor docs aligned after implementation |
| `docs/knowledge/api/02-auth-and-session.md` | Keep auth/session docs aligned after implementation |
| `docs/architecture/fire-native-architecture.md` | Keep Rust/platform ownership split aligned |

---

### Task 1: Rust — Align auth runtime signals with FluxDO v0.2.15

**Files:**
- Modify: `rust/crates/fire-models/src/session.rs`
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-core/src/core/auth.rs`
- Test: `rust/crates/fire-core/tests/network.rs`
- Test: `rust/crates/fire-core/tests/auth_strike.rs`

- [ ] **Step 1: Add explicit auth signal model**

Add `AuthRuntimeSignal` / `AuthRuntimeSignalStrength` / `AuthRuntimeSignalSource` models covering:

```text
NotLoggedInBody
DiscourseLoggedOutHeader
MixedLoggedOutHeader
AuthCookieDeletion
MixedSignalCookieDeletionBlocked
InvalidAccessForbidden
BadCsrf
CloudflareChallenge
RateLimit
ProbeValid
ProbeInvalid
ProbeInconclusive
ProbeInconclusiveEscalated
```

Only confirmed probe outcomes may mutate login state: `ProbeValid` preserves session and resets strikes; `ProbeInvalid` logs out; `ProbeInconclusive` cools down unless strike count has reached the v0.2.15 escalation threshold.

- [ ] **Step 2: Extract response classification**

Move `not_logged_in_message`, `response_login_invalidation_signal`, `is_bad_csrf_body`, and `is_cloudflare_challenge_response` into a classifier function that returns both `FireCoreError` and diagnostic `AuthRuntimeSignal`.

The classifier must map:

- `not_logged_in` body -> strong auth signal.
- `401/403 + discourse-logged-out` -> strong auth signal.
- `2xx/3xx + discourse-logged-out` -> weak/mixed auth signal.
- `invalid_access` -> forbidden, no auth signal.
- `BAD CSRF` -> csrf signal, no auth signal.
- Cloudflare HTML -> cf signal, no auth signal.

- [ ] **Step 3: Lock in forbidden-vs-login tests**

Add or update tests proving:

- `403 invalid_access` returns `HttpStatus` and preserves `_t`, `_forum_session`, CSRF.
- `401/403 not_logged_in` triggers strike/probe.
- `2xx /session/csrf` with `discourse-logged-out` still stores CSRF, blocks destructive session-cookie deletion, and records only a weak auth signal.
- `BAD CSRF` does not call auth strike.
- CF challenge does not call auth strike and does not clear session.
- `401/403 + discourse-logged-out` is strong and probes after one strike.
- two weak mixed signals probe after the second strike.

- [ ] **Step 4: Align inconclusive probe policy**

Match FluxDO v0.2.15:

- First inconclusive probe enters a 30-second weak-signal cooldown.
- Weak auth signals are suppressed during cooldown.
- If the probe was triggered with strike count >= 2 and remains inconclusive, escalate to passive logout with a distinct `probe_escalated` diagnostic reason.
- Startup login-state probe remains more conservative: network exceptions preserve local state.

- [ ] **Step 5: Update docs**

Sync `docs/knowledge/api/01-global-conventions.md` and `docs/knowledge/api/02-auth-and-session.md` so the table matches actual classifier behavior.

---

### Task 2: Rust — Keep session generation and stale response handling authoritative

**Files:**
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`
- Modify: `rust/crates/fire-core/src/cookies.rs`
- Test: `rust/crates/fire-core/tests/network.rs`

- [ ] **Step 1: Re-audit request epoch behavior**

Confirm every API request stores `FireRequestEpoch` before execution and every body read checks stale response context.

- [ ] **Step 2: Align auth cookie ingress with epoch**

Ensure `Set-Cookie` updates from stale responses never overwrite current session cookies. Keep FluxDO's `SessionGuardInterceptor` behavior mapped to Rust epoch rather than platform cancellation.

- [ ] **Step 3: Block mixed-signal session-cookie deletion**

Mirror FluxDO v0.2.15 `AppCookieManager`: if a `2xx/3xx` response carries `discourse-logged-out` and a session-cookie delete (`_t` / `_forum_session`) but the body is not `not_logged_in`, ignore the destructive cookie delete and let auth signal/probe decide the final session state.

- [ ] **Step 4: Add stale and mixed Set-Cookie tests**

Simulate a request whose response arrives after session epoch advances. Assert stale cookie changes are ignored and diagnostics record cancellation.

Also simulate `200 /session/csrf` with `discourse-logged-out` and session-cookie deletion headers. Assert CSRF is stored, `_t` / `_forum_session` remain, and a weak/mixed auth signal is recorded.

---

### Task 3: Rust + Platforms — Enforce boundary-only cookie sync

**Files:**
- Modify: `rust/crates/fire-models/src/cookie.rs`
- Modify: `rust/crates/fire-core/src/core/session.rs`
- Modify: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`
- Test: `rust/crates/fire-core/tests/login_finalization.rs`

- [ ] **Step 1: Default production login finalization to high-confidence cookies**

Audit current iOS/Android calls that pass `allowLowConfidenceSessionCookies: true`. Move production login completion toward FluxDO's default: reject low-confidence session cookies unless device-specific evidence proves the platform cannot provide domain/path/flags.

- [ ] **Step 2: Keep WebView sync entry points finite**

Allowed platform-to-Rust cookie sync events:

```text
finalize_login_from_webview
complete_cloudflare_challenge
host_cookie_repair_once_per_epoch
explicit developer diagnostics action
```

No screen may call cookie sync as a generic render/update side effect.

- [ ] **Step 3: Add duplicate cookie scoring tests**

Assert host-only `_t` beats `.linux.do` domain `_t`, non-empty beats empty, unexpired beats expired, and `cf_clearance` can be preserved across logout.

---

### Task 4: Rust — Finish CSRF as an interceptor-level behavior

**Files:**
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-core/src/core/auth.rs`
- Test: `rust/crates/fire-core/tests/network.rs`
- Test: `rust/crates/fire-core/tests/interactions.rs`

- [ ] **Step 1: Keep CSRF preflight in Rust**

All POST/PUT/DELETE/PATCH paths must use `execute_api_request_with_csrf_retry()` or an equivalent Rust-owned wrapper. Platform code must not decide when to call `/session/csrf`.

- [ ] **Step 2: Preserve Discourse web-client semantics**

When a write request somehow reaches build time without a CSRF token, continue sending `X-CSRF-Token: undefined` so the server can return `BAD CSRF` and Rust can retry once.

- [ ] **Step 3: Verify queued refresh behavior**

Keep single-flight `/session/csrf`; queued callers must skip refresh if auth cookies disappeared while waiting.

---

### Task 5: Rust + UniFFI — Add Cloudflare challenge resolution contract

**Files:**
- Create: `rust/crates/fire-core/src/core/cf_challenge.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-models/src/session.rs`
- Modify: `rust/crates/fire-uniffi-session/src/records.rs`
- Modify: `rust/crates/fire-uniffi-session/src/lib.rs`
- Test: `rust/crates/fire-core/tests/network.rs`

- [ ] **Step 1: Add challenge models**

Define:

```text
CloudflareChallengeRequest {
  operation,
  request_url,
  origin_url,
  is_foreground,
  session_epoch,
}

CloudflareChallengeResult {
  completed,
  user_cancelled,
  cookies,
  browser_user_agent,
}
```

- [ ] **Step 2: Register a platform challenge handler**

Expose a UniFFI registration point on the session/core handle. Rust may request challenge completion, but platform owns the WebView UI.

- [ ] **Step 3: Retry original operation once**

When the platform returns a completed result with a new `cf_clearance`, Rust applies cookies through scored boundary sync and retries the original request exactly once with stale cookie headers removed.

- [ ] **Step 4: Preserve failure semantics**

If the handler is unavailable, user cancels, or no new `cf_clearance` is observed, return `FireCoreError::CloudflareChallenge`. Do not log out, do not open login, do not clear `_t`.

- [ ] **Step 5: Add cooldown**

Mirror FluxDO's cooldown intent: repeated failed challenge completions enter a short cooldown so multiple blocked requests do not fan out into multiple WebViews.

---

### Task 6: iOS — Wire platform-owned manual challenge and keep auto refresh gated

**Files:**
- Modify: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`
- Modify: `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift`
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/ios-app/App/Views/Other/FireLoginWebView.swift`
- Test: `native/ios-app/Tests/Unit/FireSessionStoreTests.swift`
- Test: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`

- [ ] **Step 1: Implement `FireCloudflareChallengeCoordinator`**

Use the shared auth-browser profile. Load `originURL` when provided so topic/list context is preserved; otherwise load `/challenge` on the LinuxDo base URL.

- [ ] **Step 2: Detect successful challenge**

Use the existing iOS cookie snapshot helper pattern:

- Record baseline `cf_clearance`.
- Wait for a new `cf_clearance`.
- Confirm the page no longer contains active challenge markers.
- Return only the relevant platform cookies to Rust.

- [ ] **Step 3: Keep hidden refresh runtime behind gates**

`FireCfClearanceRefreshService.shouldAutoRefresh()` must remain gated by:

```text
scene active
login state confirmed
current user present
authenticated API readable
existing cf_clearance present
turnstile sitekey present
```

- [ ] **Step 4: Remove misleading no-op naming**

Rename or replace `performWithCloudflareRecovery` / `performWriteWithCloudflareRetry` after the Rust contract exists. Until then, do not reintroduce auto-present recovery behavior under those names.

---

### Task 7: Android — Add parity manual challenge and hidden refresh runtime

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeCoordinator.kt`
- Create: `native/android-app/src/main/java/com/fire/app/session/FireCfClearanceRefreshService.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/ui/webview/FireWebViewSupport.kt`
- Modify: `native/android-app/src/main/java/com/fire/app/core/error/FireErrorHandling.kt`
- Test: Android unit / instrumentation tests where available

- [ ] **Step 1: Reuse browser-like WebView configuration**

Manual CF WebView must share login WebView UA, cookie manager, JS settings, popup routing, safe browsing, and dark/light behavior.

- [ ] **Step 2: Implement foreground challenge UI**

Foreground user actions may present a visible challenge screen. Background/silent work may not steal focus; it should either use hidden refresh or return `CloudflareChallenge`.

- [ ] **Step 3: Implement hidden `cf_clearance` refresh**

Mirror the iOS runtime and FluxDO service:

- Load Turnstile HTML in an offscreen WebView only after login is confirmed.
- Intercept `/cdn-cgi/challenge-platform/.../rc/...`.
- Replay the rc call through native networking.
- Sync only `cf_clearance` back to Rust.

- [ ] **Step 4: Do not add an Android startup recovery shortcut**

Onboarding remains a single login entry. Startup session restoration stays in `PreheatGateFragment` and Rust `determineLoginStateWithProbe()`.

---

### Task 8: Double-end error presentation policy

**Files:**
- Modify: `native/ios-app/App/ViewModels/FireAppViewModel.swift`
- Modify: `native/android-app/src/main/java/com/fire/app/core/error/FireErrorHandling.kt`
- Modify: affected stores/view models that currently special-case auth errors

- [ ] **Step 1: LoginRequired presentation**

`LoginRequired` should be displayed as a request failure unless Rust session state has actually transitioned to logged out. Platform must not present login just because one request returned `LoginRequired`.

- [ ] **Step 2: Cloudflare presentation**

Foreground operations may route to manual challenge. Passive/background operations should record diagnostics and show a non-blocking retry message.

Current implementation note: Rust now carries Cloudflare presentation context on
the traced request. The full notification history fetch is explicitly
foreground-capable, while recent notification cache refreshes remain
background. This keeps notification-tab user gestures aligned with home/topic
detail/search reads without letting silent notification work steal focus.

- [ ] **Step 3: State-driven navigation**

Navigation to onboarding/login must be driven by authoritative session snapshot state, not by a local platform classifier.

---

### Task 9: Redirect delta audit against openwire

**Files:**
- Inspect: upstream `openwire` sources for the crates.io version in use
- No Fire-side redirect interceptor required
- Potential openwire change only if future callers need stricter explicit-`Cookie` redirect handling
- Test: openwire redirect tests

- [x] **Step 1: Audit current openwire redirect behavior**

Verified:

- Default max redirect count is 10.
- HTTPS -> HTTP downgrade is rejected unless explicitly allowed.
- `301/302/303` switch non-GET/HEAD requests to GET and drop body framing headers.
- `307/308` preserve method/body and require replayable body.
- Cross-origin redirect removes `Cookie` and `Authorization`.
- Normal Fire requests do not carry an explicit `Cookie` header before openwire's CookieJar injection, so redirect follow-ups recompute cookies for the redirected URL.
- Response `Set-Cookie` is persisted against the response request URL before following the next location; Fire's `FireSessionCookieJar` additionally rejects non same-site ingress.

- [x] **Step 2: Compare FluxDO behavior**

FluxDO disables Dio auto redirect and manually reissues redirect requests after clearing `Cookie` / `cookie` headers so its CookieManager recomputes cookies. Openwire already follows the same practical behavior for Fire's normal CookieJar-owned requests, with stronger built-in redirect guardrails. Fire should not copy FluxDO's manual redirect interceptor.

- [x] **Step 3: Decide ownership**

Decision: no Fire-specific redirect implementation in this auth/CF runtime plan.

If future product code explicitly sets `Cookie` headers and needs FluxDO's stricter per-hop clearing even for same-origin redirects, fix it in openwire by adding a redirect request policy knob and tests. Do not implement redirect recursion in a Fire application interceptor.

---

### Task 10: Remove legacy recovery surfaces and stale docs

**Files:**
- Already modified: `native/android-app/src/main/res/layout/fragment_onboarding.xml`
- Already modified: `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`
- Already modified: `native/android-app/src/main/res/navigation/fire_nav_graph.xml`
- Already modified: `native/android-app/src/main/res/values/strings.xml`
- Already modified: `native/android-app/src/main/java/com/fire/app/ui/auth/AuthViewModel.kt`
- Already modified: `native/android-app/src/main/res/drawable/bg_error_banner.xml`
- Modify after runtime implementation: `native/ios-app/README.md`
- Modify after runtime implementation: `docs/architecture/fire-native-architecture.md`
- Modify after runtime implementation: `docs/knowledge/api/01-global-conventions.md`
- Modify after runtime implementation: `docs/knowledge/api/02-auth-and-session.md`

- [x] **Step 1: Remove Android login-below restore entry**

Delete `restore_session_button`, `onboarding_restore_session`, unused onboarding-to-home action, and the same stale onboarding branch's hidden loading/error UI.

- [x] **Step 2: Re-audit iOS login/onboarding**

Confirm there is no equivalent login-below restore entry. Developer tools may keep a diagnostic “恢复会话” action if it only re-runs startup loading and is clearly not a production login shortcut.

- [x] **Step 3: Clean stale recovery docs**

After Tasks 5-8 land, remove any doc text claiming the app auto-opens login or recovery WebView for ordinary request errors.

---

### Task 11: Verification Matrix

**Rust commands:**

```bash
cargo test -p fire-models
cargo test -p fire-core --test network --test auth_strike --test login_finalization
cargo test -p fire-uniffi-session
cargo test -p openwire --features websocket --lib policy::
```

**Android commands:**

```bash
export ANDROID_HOME=/Users/zhangfan/Library/Android/sdk
export ANDROID_SDK_ROOT=/Users/zhangfan/Library/Android/sdk
./gradlew :app:assembleDebug
```

**iOS commands:**

```bash
cd native/ios-app
xcodegen generate
xcodebuild -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16' build
```

**Manual scenarios:**

- [ ] Cold start with no cookies: PreheatGate -> onboarding; no restore-account action visible.
- [ ] Cold start with valid `_t`: Rust probe valid -> home; MessageBus starts after first home refresh.
- [ ] Cold start with expired `_t`: probe invalid -> passive logout preserving `cf_clearance`.
- [ ] `/session/csrf` returns `2xx` with `discourse-logged-out`: CSRF stored, no login popup.
- [ ] `403 invalid_access`: no logout, no challenge UI.
- [ ] `403 not_logged_in` + probe valid: request fails, session preserved.
- [ ] `403 not_logged_in` + probe invalid: passive logout, onboarding after snapshot changes.
- [ ] `403 CF HTML`: manual challenge, new `cf_clearance`, original request retries once.
- [ ] Silent/background `403 CF HTML`: no foreground steal; error recorded or hidden refresh used.
- [x] Redirect across same origin: openwire audit confirms normal Fire CookieJar-owned requests recompute cookies for each follow-up URL.
- [x] Redirect across origin: openwire audit confirms cross-origin redirect removes `Cookie` / `Authorization`, and Fire cookie ingress remains same-site scoped.
