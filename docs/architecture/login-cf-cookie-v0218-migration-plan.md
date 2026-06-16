# Migrate Login, Cloudflare, and Cookies to the v0.2.18 Knowledge Contract

## Breaking Change Notice

This is a breaking native/session refactor. Fire must stop treating the
Discourse Ember `/login` page as the password-login path and must expose richer
cookie/session records over UniFFI. Existing platform login controllers, cookie
replay assumptions, and low-confidence `name=value` cookie snapshots are not
sufficient for the v0.2.18-derived behavior now documented in `docs/knowledge/`.

Consumer migration:

1. Replace full-page WebView password-login callers with a native form plus
   minimal WebView JS login dialog.
2. Replace `PlatformCookieState` usage with expanded canonical cookie records
   that preserve host-only, Secure, HttpOnly, SameSite, Partitioned, expiry,
   creation time, version, source, and trust.
3. Route WebView login `{phase,status,body}` through the shared Rust classifier.
4. Treat Rust canonical cookie/session state as authoritative; platform code
   only reads/writes/deletes native WebView cookies.

## Feasibility Assessment

The migration is fully feasible. Fire already has iOS and Android WebView login
controllers, Cloudflare challenge handlers, platform cookie extraction hooks,
UniFFI session APIs, Rust auth epochs, bootstrap refresh, conservative logout
probes, Cloudflare `403`/`429` detection, and cookie replay/scoring foundations.
The missing pieces are the minimal WebView-owned login transaction, canonical
cookie version/freshness arbitration, cookie sweep/self-healing, and a
pre-dispatch CF freeze gate. Fully feasible.

## Current Surface Inventory

- `docs/knowledge/discourse-webview-login-guide.md` -- authoritative
  stack-neutral password-login contract.
- `docs/knowledge/discourse-cloudflare-challenge-guide.md` -- authoritative
  challenge detection, verification, and freeze contract.
- `docs/knowledge/discourse-cookie-session-state-guide.md` -- authoritative
  canonical cookie, priming, sweep, and self-healing contract.
- `docs/knowledge/api/02-auth-and-session.md` -- auth/session endpoint
  reference and login boundary summary.
- `docs/knowledge/api/01-global-conventions.md` -- shared cookie, CSRF, status,
  and Cloudflare signal conventions.
- `native/ios-app/App/Views/Other/FireLoginWebView.swift` -- current full
  WebView login surface; replace normal password path.
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` -- current login
  presentation and session application orchestration.
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- Swift actor
  facade over session UniFFI APIs.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` --
  current WebKit cookie extraction and login finalization helper.
- `native/ios-app/Sources/FireAppSession/FireWebViewBrowserProfile.swift` --
  shared WKWebView profile, UA, scripts, and login browser configuration.
- `native/ios-app/Sources/FireAppSession/FireCloudflareChallengeCoordinator.swift`
  -- current platform CF challenge handler.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` --
  hidden clearance refresh and challenge-cookie coordination.
- `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt`
  -- current full WebView login fragment; replace normal password path.
- `native/android-app/src/main/java/com/fire/app/session/FireLoginScripts.kt` --
  current `/login` probing scripts; replace with minimal login document builder.
- `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt`
  -- current WebView state capture and low-confidence cookie parsing.
- `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt` --
  Android wrapper over session UniFFI APIs.
- `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeActivity.kt`
  -- current foreground CF challenge WebView.
- `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeCoordinator.kt`
  -- current blocking CF challenge callback.
- `native/android-app/src/main/java/com/fire/app/ui/webview/FireWebViewSupport.kt`
  -- shared Android WebView settings and UA handling.
- `rust/crates/fire-models/src/cookie.rs` -- current cookie records; expand to
  canonical cookie metadata and sweep records.
- `rust/crates/fire-models/src/session.rs` -- current session state and login
  phase records; add WebView login classifier records and CF request modes.
- `rust/crates/fire-core/src/cookies.rs` -- current OpenWire cookie jar; replace
  scoring/merge with canonical save/load/freshness/sweep planning.
- `rust/crates/fire-core/src/core/session.rs` -- current
  `finalize_login_from_webview`, platform cookie apply, and challenge completion.
- `rust/crates/fire-core/src/core/network.rs` -- request execution, CSRF retry,
  CF detection, and auth signal classification.
- `rust/crates/fire-core/src/core/cf_challenge.rs` -- CF runtime state and
  platform handler registry.
- `rust/crates/fire-core/src/core/auth.rs` -- CSRF refresh, bootstrap refresh,
  probes, and passive logout.
- `rust/crates/fire-core/src/app_state_refresher.rs` -- login-ready and
  post-login refresh batches.
- `rust/crates/fire-uniffi-session/src/lib.rs` -- session FFI methods.
- `rust/crates/fire-uniffi-session/src/records.rs` -- session/cookie FFI records.
- `rust/crates/fire-store/src/cookie_replay.rs` -- transitional replay queue.
- `rust/crates/fire-store/src/migrations.rs` -- storage migrations if canonical
  cookies need persistence changes.

## Design

Fire implements the behavior documented in `docs/knowledge/` with the repository
ownership split:

- Platform owns native login UI, minimal WebView login/challenge execution,
  native cookie store reads/writes/deletes, user-agent repair, and secure
  credential storage.
- Rust owns login result parsing, session state, canonical cookie arbitration,
  sweep planning, self-healing, API orchestration, CF request blocking, auth
  generation, and login-ready refresh.

### Key Design Decisions

1. **Use WebView-owned login requests** -- Password login opens a small WebView
   document with base origin `https://linux.do/`; JS runs `/session/csrf`,
   hCaptcha create, and `/session.json`. Rejected alternative: Rust/OpenWire
   performs `/session/csrf` for login. Reason: login CSRF can be browser
   fingerprint sensitive, and the knowledge contract requires WebView-owned
   requests.

2. **Delete the old Ember `/login` implementation plan** -- The older plan is
   removed instead of marked superseded. Rejected alternative: keep it as
   historical guidance. Reason: the repository no longer depends on reference
   source files, so stale implementation docs must not compete with
   `docs/knowledge/`.

3. **Make `docs/knowledge/` the only protocol authority** -- Architecture plans
   and implementation code cite stack-neutral knowledge docs, not reference
   project paths. Rejected alternative: keep source-file references as comments.
   Reason: the reference submodule is not an implementation dependency.

4. **Parse `session.json` in Rust** -- iOS and Android send raw
   `{phase,status,body}` to Rust and render the returned decision. Rejected
   alternative: duplicate parsing in Swift and Kotlin. Reason: 2FA/error mapping
   is backend protocol logic.

5. **Finalize login in one Rust handoff** -- After JS success, platform extracts
   live WebView cookies and calls a single async Rust finalizer. Rust advances
   auth generation, applies trusted cookies, refreshes bootstrap with an 8
   second timeout, and always notifies login-ready. Rejected alternative:
   platform-triggered refresh batches after finalization. Reason: split
   finalization can permanently wedge UI when platform lifecycle objects
   disappear.

6. **Use Rust canonical cookies with platform action plans** -- Rust stores
   metadata, version, trust, and winner decisions. Platforms execute exact native
   cookie actions. Rejected alternative: implement independent sentinel logic in
   Swift and Kotlin. Reason: cookie invariants must be identical across both
   platforms.

7. **Store host-only as metadata, not identity** -- Canonical key is
   `(name, normalized_domain, path, partition_key)`. Rejected alternative:
   include host-only in the key. Reason: platform WebView APIs often cannot
   reliably expose host-only state, and keying by it recreates duplicate
   variants.

8. **Trusted writes bump versions; untrusted reads pass freshness** -- Network
   `Set-Cookie`, WebView login success, and confirmed CF values are trusted.
   Generic WebView bulk reads are untrusted. Rejected alternative: last writer
   wins. Reason: old WebView variants can otherwise overwrite fresh
   login/challenge values.

9. **Freeze business requests during CF verification** -- Rust blocks ordinary
   API, MessageBus, and timing requests while `cf_in_progress` is true, except
   explicit internal `skip_cf_block` requests. Rejected alternative: allow more
   requests to discover the same challenge. Reason: continued traffic with stale
   clearance can create request floods and retry loops.

### Concrete Type / Interface Definitions

Rust login classifier records:

```rust
pub enum WebViewLoginPhase {
    Csrf,
    Hcaptcha,
    Session,
    Exception,
}

pub struct WebViewLoginJsResult {
    pub phase: WebViewLoginPhase,
    pub status: u16,
    pub body: String,
}

pub enum WebViewLoginDecision {
    Success,
    NeedSecondFactor(SecondFactorRequirement),
    RetryCloudflare,
    Failure(LoginFailureKind),
}

pub struct SecondFactorRequirement {
    pub totp_enabled: bool,
    pub security_key_enabled: bool,
    pub backup_enabled: bool,
    pub message: Option<String>,
}
```

Rust canonical cookie records:

```rust
pub enum CookieSource {
    Unknown,
    NetworkSetCookie,
    WebViewLogin,
    WebViewChallenge,
    WebViewBulkRead,
    ManualRestore,
}

pub enum CookieTrust {
    Trusted,
    Untrusted,
}

pub enum CookieSameSite {
    Unspecified,
    Lax,
    Strict,
    None,
}

pub struct CanonicalCookie {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: String,
    pub host_only: bool,
    pub secure: bool,
    pub http_only: bool,
    pub same_site: CookieSameSite,
    pub partition_key: Option<String>,
    pub partitioned: bool,
    pub expires_at_unix_ms: Option<i64>,
    pub max_age_seconds: Option<i64>,
    pub creation_time_unix_ms: i64,
    pub last_access_time_unix_ms: i64,
    pub version: u64,
    pub source: CookieSource,
    pub raw_set_cookie: Option<String>,
    pub origin_url: Option<String>,
}
```

Rust/platform cookie action records:

```rust
pub enum CookieSweepIntent {
    EnsureUnique,
    Delete,
}

pub struct WebViewCookieInfo {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
    pub host_only: Option<bool>,
    pub secure: Option<bool>,
    pub http_only: Option<bool>,
    pub same_site: Option<CookieSameSite>,
    pub expires_at_unix_ms: Option<i64>,
}

pub enum WebViewCookieAction {
    SetRaw { url: String, set_cookie: String },
    DeleteExact { url: String, name: String, domain: Option<String>, path: String },
    DeleteByName { url: String, name: String },
}

pub struct CookieSweepPlan {
    pub name: String,
    pub intent: CookieSweepIntent,
    pub actions: Vec<WebViewCookieAction>,
    pub selected_winner: Option<CanonicalCookie>,
}

pub enum CookieSelfHealingPhase {
    Sweep,
    NuclearReset,
}

pub struct CookieSelfHealingRequest {
    pub operation: String,
    pub request_url: String,
    pub target_url: String,
    pub phase: CookieSelfHealingPhase,
    pub attempt: u8,
    pub cookie_names: Vec<String>,
    pub session_epoch: u64,
}

pub struct CookieSelfHealingResult {
    pub completed: bool,
    pub session_epoch: u64,
}
```

Usage example:

```rust
let decision = core.classify_webview_login_result(js_result)?;

match decision {
    WebViewLoginDecision::Success => {
        let cookies = platform.extract_webview_cookie_info("https://linux.do/").await?;
        core.finalize_webview_js_login(identifier, browser_ua, cookies).await?;
    }
    WebViewLoginDecision::NeedSecondFactor(requirement) => {
        platform.show_totp_dialog(requirement).await?;
    }
    WebViewLoginDecision::RetryCloudflare => {
        platform.verify_cloudflare_now().await?;
    }
    WebViewLoginDecision::Failure(kind) => return Err(kind.into()),
}
```

## Phased Implementation

## Phase 1: Documentation Authority Reset

**File: `docs/knowledge/discourse-webview-login-guide.md`**

- Keep this as the authoritative password-login protocol.
- Include JS bridge names, endpoint order, request headers, hCaptcha fallback,
  2FA retry, CSRF CF retry, priming, and finalization.

**File: `docs/knowledge/discourse-cloudflare-challenge-guide.md`**

- Keep this as the authoritative challenge protocol.
- Include `403 || 429`, `cf-mitigated: challenge`, request modes,
  `cf_in_progress`, manual verify, freshness filtering, and UA repair.

**File: `docs/knowledge/discourse-cookie-session-state-guide.md`**

- Keep this as the authoritative cookie/session invariant protocol.
- Include canonical fields, storage key, freshness, explicit delete, priming,
  sentinel sweep, winner selection, nuclear reset, and self-healing.

Rationale: implementation must be driven by framework-neutral knowledge docs,
not by a removed reference submodule or stale full-browser login plan.

## Phase 2: Rust Login Protocol And Finalization

**File: `rust/crates/fire-models/src/session.rs`**

- Add `WebViewLoginPhase`, `WebViewLoginJsResult`, `WebViewLoginDecision`,
  `SecondFactorRequirement`, `LoginFailureKind`, and `CloudflareRequestMode`.
- Keep response-body fields raw so Rust can parse once and platforms can render
  typed decisions.

**File: `rust/crates/fire-core/src/core/session.rs`**

- Add `classify_webview_login_result(result) -> WebViewLoginDecision`.
- Implement reason mapping from
  `docs/knowledge/discourse-webview-login-guide.md`.
- Add async `finalize_webview_js_login(...)`:
  - advance auth generation first;
  - apply WebView login cookies as trusted;
  - persist username and browser UA hints;
  - read `_t` from canonical cookies;
  - run login-ready refresh with 8 second timeout;
  - always notify session observers in finalization fallback.
- Keep `finalize_login_from_webview` only as a temporary compatibility wrapper
  until both platforms migrate.

**File: `rust/crates/fire-core/src/app_state_refresher.rs`**

- Add a login-finalization refresh entry that can run from Rust-owned state.
- Ensure delayed batches do not depend on platform view/fragment lifetimes.

**File: `rust/crates/fire-uniffi-session/src/lib.rs`**

- Expose `classify_webview_login_result`.
- Expose async `finalize_webview_js_login`.

**File: `rust/crates/fire-uniffi-session/src/records.rs`**

- Add FFI records for login JS result, login decision, second-factor
  requirement, failure kind, and CF request mode.

## Phase 3: Rust Canonical Cookie Engine

**File: `rust/crates/fire-models/src/cookie.rs`**

- Add `CanonicalCookie`, `CookieSource`, `CookieTrust`, `CookieSameSite`,
  `WebViewCookieInfo`, `WebViewCookieAction`, `CookieSweepPlan`, and
  `NuclearResetPlan`.
- Implement storage key, freshness comparison, Set-Cookie reconstruction, and
  host-only normalization.

**File: `rust/crates/fire-core/src/cookies.rs`**

- Parse `Set-Cookie` into canonical cookies with Secure, HttpOnly, SameSite,
  host-only, partition, expiry, creation time, and raw header.
- Save trusted writes with version bump on value change.
- Save untrusted writes only when fresher.
- Add `delete_by_name(uri, name)` that bypasses freshness.
- Build request cookie headers from canonical cookies with one critical winner.
- Preserve `_t` and `_forum_session` as host-only for `linux.do`.

**File: `rust/crates/fire-store/src/migrations.rs`**

- Add canonical cookie persistence migration if cookies are not stored in the
  existing session file.
- Preserve old replay data for transition.

**File: `rust/crates/fire-store/src/cookie_replay.rs`**

- Keep as a compatibility source for WebView priming until canonical priming is
  complete.
- Add removal notes for the later cleanup phase.

## Phase 4: Cookie Sentinel, Priming, And Self-Healing

**File: `rust/crates/fire-core/src/cookies.rs`**

- Add sweep plan generation for `EnsureUnique` and `Delete`.
- Implement winner rules from
  `docs/knowledge/discourse-cookie-session-state-guide.md`.
- Add nuclear reset plan generation.
- Add priming payload generation for `https://linux.do/`.
- Add commit hooks for platform sweep results.

**File: `rust/crates/fire-core/src/core/network.rs`**

- Add self-healing branch for `401`, `419`, and strong logged-out signals:
  sweep + retry, then nuclear reset + retry once, with recursion guard.
- Keep conservative session probe for true logout after healing fails.

**File: `rust/crates/fire-core/src/core/cookie_healing.rs`**

- Add the Rust-owned platform handler registry used by the network
  self-healing branch.
- Keep platform cookie-store mutation behind an explicit handler so normal API
  orchestration stays in Rust while native cookie stores remain platform-owned.

**File: `rust/crates/fire-uniffi-session/src/lib.rs`**

- Expose `webview_priming_payload`.
- Expose `cookie_sweep_plan`, `cookie_nuclear_reset_plan`, and
  `commit_cookie_sweep_result`.
- Expose `register_cookie_self_healing_handler` and
  `unregister_cookie_self_healing_handler`.

**File: `rust/crates/fire-uniffi-session/src/records.rs`**

- Add records for WebView cookie snapshots, raw set/delete actions, sweep
  status, and nuclear reset result.
- Add `CookieSelfHealingPhaseState`, `CookieSelfHealingRequestState`,
  `CookieSelfHealingResultState`, and the foreign `CookieSelfHealingHandler`
  trait.

Current branch status:

- Rust canonical cookie records, freshness arbitration, explicit delete,
  host-only normalization, request header generation, and network `Set-Cookie`
  ingestion are implemented.
- Legacy `PlatformCookie` inputs are now bridged into canonical state with
  source/trust distinctions so existing native call sites can migrate
  incrementally.
- `webview_priming_payload` is exposed over UniFFI and returns raw
  `Set-Cookie` actions reconstructed from canonical state.
- Sweep plan generation and nuclear reset plan generation are implemented and
  exposed over UniFFI.
- iOS and Android now have stack-local minimal login HTML/JS builders and unit
  tests for the WebView-owned CSRF, hCaptcha, and `/session.json` transaction.
- iOS and Android session facades now expose login classification, priming,
  sweep, and nuclear-reset APIs; both WebView login coordinators can execute
  Rust `SetRaw`, `DeleteExact`, and `DeleteByName` cookie actions against their
  native WebView cookie stores.
- The primary iOS and Android password-login entries now use native credential
  fields plus a minimal same-origin WebView document for hCaptcha and
  `window.__fireLogin`; they no longer load the Discourse Ember `/login` page as
  the normal password-login path.
- Login CSRF Cloudflare failures now trigger a one-shot platform foreground
  verification path, apply returned challenge cookies to Rust, wait briefly for
  platform cookie propagation, re-prime the same live login WebView, and re-run
  `window.__fireLogin` with the original hCaptcha/second-factor arguments.
- Rust detects Cloudflare challenge responses on `403` or `429`, treats
  `cf-mitigated: challenge` as sufficient even for non-HTML bodies, marks
  verification as in-progress, blocks ordinary business requests before
  dispatch, and allows only explicit `skip_cf_block` retries through the gate.
- Sweep commit hooks are now implemented: iOS and Android execute Rust
  WebView cookie action plans, re-sample the platform cookie store, and commit
  the post-sweep winner/delete result back into Rust canonical cookie state.
- Cookie self-healing retry orchestration is implemented in Rust network
  execution. `401`, `419`, and strong `discourse-logged-out` responses trigger
  sweep + retry twice, then nuclear reset + retry once, guarded by a request
  marker to prevent recursive healing.
- iOS and Android register runtime cookie self-healing handlers. The handlers
  call the existing platform WebView cookie sweep/nuclear-reset action
  executor against the default browser cookie store and return the observed
  session epoch to Rust.
- Platform cookie extraction now treats hidden `cf_clearance` SameSite metadata
  as `SameSite=None` when native APIs omit it; raw network `Set-Cookie`
  metadata still wins when present.
- Remaining follow-up hardening is higher-fidelity cookie-store observation and
  platform metadata extraction where native APIs expose it. The current login,
  CF, sweep, and self-healing paths no longer depend on the old Ember `/login`
  flow.

## Phase 5: Cloudflare Freeze Gate

**File: `rust/crates/fire-core/src/core/cf_challenge.rs`**

- Expose observable `cf_in_progress`.
- Add request mode fields and manual-verify bypass flags.
- Track fresh `cf_clearance` value returned by platform verification.

**File: `rust/crates/fire-core/src/core/network.rs`**

- Add pre-dispatch CF block:
  - reject ordinary business requests while `cf_in_progress`;
  - allow only `skip_cf_block` internal work;
  - classify blocked requests separately from network failures.
- Detect CF on `403 || 429` plus Cloudflare-specific header/body signals.

**File: `rust/crates/fire-core/src/core/interactions.rs`**

- Drop pending topic timings and suppress timing accumulation while
  `cf_in_progress`.

## Phase 6: iOS Native Path

**File: `native/ios-app/App/Views/Other/FireLoginWebView.swift`**

- Replace the normal full-page password login with native form plus modal
  minimal WebView login dialog.
- Load inline HTML with base URL `https://linux.do/`.
- Register bridge handlers `hcaptcha_pass`, `hcaptcha_error`,
  `hcaptcha_expired`, and `login_result`.
- Keep the same live WKWebView for TOTP retry.

**File: `native/ios-app/Sources/FireAppSession/FireWebViewBrowserProfile.swift`**

- Add a lean login-dialog WKWebView configuration.
- Omit Ember preloaded capture, credential autofill hooks, and fingerprint
  interception from the minimal login dialog.
- Keep browser-compatible UA and required hCaptcha compatibility settings.

**File: `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift`**

- Add priming into a specific WKWebView from Rust priming payload.
- Add full cookie extraction with host-only and SameSite mapping where WebKit
  exposes it.
- Add exact native set/delete action execution for Rust sweep plans.
- Register `WKHTTPCookieStoreObserver`, debounce external changes, and suppress
  observer loops during internal writes.

**File: `native/ios-app/Sources/FireAppSession/FireCloudflareChallengeCoordinator.swift`**

- Refactor full-screen challenge into contextual/manual verification behavior.
- Return fresh `cf_clearance`, related cookies, and browser UA to Rust.

**File: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`**

- Invalidate priming before deleting old challenge cookies.
- Re-read Rust canonical state before every async cookie write batch.

**File: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`**

- Bridge new login classifier, finalizer, priming, sweep, and CF APIs.

**File: `native/ios-app/App/ViewModels/FireAppViewModel.swift`**

- Route login entry to the new native form + JS dialog.
- Remove primary-path `/login` readiness polling.
- Apply the Rust finalizer session snapshot as the single success handoff.

## Phase 7: Android Native Path

**File: `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt`**

- Replace the normal full-page password login with native form plus dialog
  WebView.
- Use `loadDataWithBaseURL("https://linux.do/", ...)`.
- Register JS interfaces for hCaptcha and login result callbacks.
- Keep the same WebView instance for TOTP retry.

**File: `native/android-app/src/main/java/com/fire/app/session/FireLoginScripts.kt`**

- Replace `/login` page probing scripts with a minimal login HTML/JS builder.
- Name the new function `window.__fireLogin`.
- Do not manually forge browser-owned headers.

**File: `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt`**

- Add priming from Rust canonical payload into the target WebView.
- Extract full cookie info where WebView APIs expose it.
- Treat `CookieManager.getCookie()` as low-confidence fallback only.
- Force `_t` and `_forum_session` host-only metadata when Android fields are
  ambiguous.
- Execute Rust sweep set/delete actions through CookieManager/native helpers.

**File: `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeActivity.kt`**

- Mirror the CF verification contract from the knowledge guide.
- Return fresh `cf_clearance`, all related cookies, and browser UA.

**File: `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeCoordinator.kt`**

- Pass request mode and manual-verify options through the platform handler.

**File: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`**

- Bridge new login classifier, finalizer, priming, sweep, and CF APIs.

**File: `native/android-app/src/main/java/com/fire/app/ui/webview/FireWebViewSupport.kt`**

- Keep browser-compatible settings for login/challenge WebViews.
- Ensure JS bridge exposure is limited to the minimal login dialog and trusted
  challenge surfaces.

## Phase 8: Tests And Verification

**File: `rust/crates/fire-core/tests/login_finalization.rs`**

- Add classifier tests for success, 2FA, known failure reasons, non-JSON body,
  and CSRF CF retry.
- Add finalizer tests proving timeout still notifies session-ready.

**File: `rust/crates/fire-core/tests/session_flow.rs`**

- Add canonical cookie tests:
  - trusted value bumps version;
  - untrusted stale WebView read is ignored;
  - explicit delete removes persistent `cf_clearance`;
  - `_t` remains host-only;
  - winner rule picks non-canonical WebView value when multiple variants exist.

**File: `rust/crates/fire-core/tests/network.rs`**

- Add CF tests:
  - `429` with `cf-mitigated: challenge` enters CF path;
  - ordinary `429` does not;
  - business request is blocked during `cf_in_progress`;
  - `skip_cf_block` internal retry proceeds.

**File: `native/ios-app/Tests/Unit/FireSessionStoreTests.swift`**

- Add tests for login result routing, priming calls, trusted cookie extraction,
  and host-only mapping.

**File: `native/android-app/src/test/java/com/fire/app/session`**

- Add tests for minimal login HTML construction, JS bridge result routing,
  low-confidence fallback mapping, and host-only session forcing.

Verification commands:

```bash
cargo test --workspace
cd native/android-app && ./gradlew testDebugUnitTest
cd native/ios-app && xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Current branch targeted verification:

```bash
cargo test --manifest-path rust/crates/fire-core/Cargo.toml self_heal
cargo test --manifest-path rust/crates/fire-uniffi-session/Cargo.toml register_cookie_self_healing_handler
cd native/android-app && ./gradlew compileDebugKotlin compileDebugUnitTestKotlin testDebugUnitTest --rerun-tasks -x syncFireUniffiDebugBindings --tests com.fire.app.session.FireWebViewCookieActionSupportTest --tests com.fire.app.session.FireLoginScriptsTest
cd native/ios-app && xcodebuild test -quiet -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:FireTests/FireWebViewCookieActionSupportTests
```

Note: a full Android `--rerun-tasks` native archive rebuild was attempted, but
the local machine ran out of disk space while writing `libfire_uniffi.a`. The
targeted Android command above still forced Kotlin recompilation and unit tests
against the existing generated UniFFI bindings.

## Architectural Notes

- Semver impact: UniFFI records and methods change; generated Swift/Kotlin
  bindings must be regenerated in the same implementation branch.
- Object safety / trait coherence: platform cookie actions should use concrete
  UniFFI records, not generic Rust traits across FFI.
- Side effects: login finalization advances auth generation before writing new
  session state; stale request responses must not write cookies afterward.
- Not changed: Rust/OpenWire remains the HTTP client for normal authenticated
  API traffic after login.
- Not changed: platform remains owner of WebView UI, WebView cookie store
  mechanics, keychain/keystore, files, media, and notifications.
- New external dependencies: none required initially.
- Removed behavior: normal password login no longer depends on Discourse Ember
  `/login`, navigation-to-root success detection, page-bootstrap readiness
  polling, or fingerprint upload wait.
- Risk: Android WebView cookie metadata is incomplete on some versions. Treat
  those snapshots as low confidence and use Rust canonical metadata when writing
  winners.
- Risk: bootstrap refresh after login can hit CF. It must timeout and notify
  login-ready instead of blocking UI forever.

## File Change Summary

- `docs/architecture/login-cf-cookie-v0218-migration-plan.md` -- rewritten to depend only on `docs/knowledge/`.
- `docs/knowledge/api-overview.md` -- link the login, CF, and cookie authority docs.
- `docs/knowledge/api/01-global-conventions.md` -- link detailed session guides and update CF handling summary.
- `docs/knowledge/api/02-auth-and-session.md` -- update login boundary to the minimal WebView JS flow.
- `docs/knowledge/api/14-misc-apis.md` -- update recommended login order.
- `docs/knowledge/discourse-cloudflare-challenge-guide.md` -- new stack-neutral CF challenge contract.
- `docs/knowledge/discourse-cookie-session-state-guide.md` -- stack-neutral canonical cookie/session contract, including platform SameSite metadata gaps.
- `docs/knowledge/discourse-webview-login-guide.md` -- expanded stack-neutral password-login contract.
- `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeActivity.kt` -- implement CF verification result handoff.
- `native/android-app/src/main/java/com/fire/app/session/FireCloudflareChallengeCoordinator.kt` -- bridge CF request mode/manual verify options.
- `native/android-app/src/main/java/com/fire/app/session/FireCookieSelfHealingCoordinator.kt` -- bridge Rust cookie self-healing requests to Android WebView cookie actions.
- `native/android-app/src/main/java/com/fire/app/session/FireLoginScripts.kt` -- build minimal login HTML/JS.
- `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt` -- bridge new FFI login/cookie APIs.
- `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt` -- implement priming, extraction, and sweep actions.
- `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt` -- replace full browser login with native form + JS dialog.
- `native/android-app/src/main/java/com/fire/app/ui/webview/FireWebViewSupport.kt` -- constrain WebView settings and JS bridge exposure.
- `native/ios-app/App/ViewModels/FireAppViewModel.swift` -- route login and success handoff to the new single path.
- `native/ios-app/App/Views/Other/FireLoginWebView.swift` -- replace full browser login with native form + JS dialog.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- coordinate priming invalidation and CF refresh races.
- `native/ios-app/Sources/FireAppSession/FireCloudflareChallengeCoordinator.swift` -- implement CF verification result handoff.
- `native/ios-app/Sources/FireAppSession/FireCookieSelfHealingCoordinator.swift` -- bridge Rust cookie self-healing requests to WebKit cookie actions.
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- bridge new FFI login/cookie APIs.
- `native/ios-app/Sources/FireAppSession/FireWebViewBrowserProfile.swift` -- add lean login-dialog WebView profile.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` -- implement priming, extraction, observer, and sweep actions.
- `rust/crates/fire-core/src/app_state_refresher.rs` -- implement bounded login-ready finalization refresh.
- `rust/crates/fire-core/src/cookies.rs` -- implement canonical cookie jar, freshness, sweep planning, priming, and self-healing helpers.
- `rust/crates/fire-core/src/core/auth.rs` -- align probes/passive logout with cookie self-healing.
- `rust/crates/fire-core/src/core/cf_challenge.rs` -- expose CF in-progress state and request modes.
- `rust/crates/fire-core/src/core/cookie_healing.rs` -- register platform cookie self-healing handlers.
- `rust/crates/fire-core/src/core/interactions.rs` -- drop/suppress timings during CF verification.
- `rust/crates/fire-core/src/core/network.rs` -- implement CF pre-dispatch gate, detection, and healing retry guard.
- `rust/crates/fire-core/src/core/session.rs` -- implement WebView login classifier and async finalizer.
- `rust/crates/fire-core/tests/login_finalization.rs` -- add JS login classifier/finalizer tests.
- `rust/crates/fire-core/tests/network.rs` -- add CF detection/freeze/self-healing tests.
- `rust/crates/fire-core/tests/session_flow.rs` -- add canonical cookie versioning and host-only tests.
- `rust/crates/fire-models/src/cookie.rs` -- add canonical cookie and sweep models.
- `rust/crates/fire-models/src/session.rs` -- add WebView login and CF mode records.
- `rust/crates/fire-store/src/cookie_replay.rs` -- keep transitional replay and document removal path.
- `rust/crates/fire-store/src/migrations.rs` -- add canonical cookie persistence migration if needed.
- `rust/crates/fire-uniffi-session/src/lib.rs` -- expose login, priming, sweep, finalizer, and CF APIs.
- `rust/crates/fire-uniffi-session/src/records.rs` -- add expanded cookie and login records.
