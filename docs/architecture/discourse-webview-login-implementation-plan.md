# Discourse WebView Login Implementation Plan

> This document is the **single authoritative specification** for the Fire login system across iOS, Android, and Rust. All existing login code on both platforms must be rewritten to conform to this plan. The `docs/knowledge/discourse-webview-login-guide.md` is the behavioral reference; this document maps it to concrete file changes per platform.

---

## 1. Architecture Alignment

Per `docs/architecture/fire-native-architecture.md`:

- **Rust owns**: session state, CSRF management, session generation/epoch, HTTP interceptors, strike/probe conservative logout, `discourse-logged-out` detection, cookie scoring, cookie replay queue
- **Platform owns**: WebView rendering, JS injection, cookie extraction from WebView CookieStore, credential storage (Keychain/Keystore), Cloudflare challenge WebView
- **UniFFI boundary**: typed data flow only, zero business logic

### Responsibility Map per Guide Section

| Guide Section | Rust | iOS (UIKit) | Android (androidx) |
|---|---|---|---|
| 3.1 Login flow steps [1]-[2] (Cookie replay, hCaptcha inject) | Provides `set_cookie_queue` data | WKWebView cookie injection | WebView CookieManager injection |
| 3.1 Steps [3]-[4] (JS injection, auto-detection) | — | WKUserScript injection | WebView.evaluateJavascript |
| 3.1 Step [5] (Login detection: username + `_t`) | — | Read WKHTTPCookieStore + JS | CookieManager + JS |
| 3.1 Step [6] (Login finalization sequence) | `finalize_login_from_webview()` FFI | Orchestrates sequence, calls FFI | Orchestrates sequence, calls FFI |
| 3.2 (_t retry, 15x @ 500ms) | — | Platform timer loop | Platform coroutine loop |
| 3.3 (Email link login) | — | Deep link + clipboard handler | Deep link + clipboard handler |
| 4.1 (Preloaded data MutationObserver) | — | WKUserScript AT_DOCUMENT_START | WebView AT_DOCUMENT_START |
| 4.2 (Credential auto-fill + button hook) | — | WKUserScript | WebView evaluateJavascript |
| 4.3 (Fingerprint intercept) | — | WKUserScript + message handler | WebView JS interface |
| 4.4-4.5 (Username/CSRF reading) | — | JS evaluation | JS evaluation |
| 5.1 (Boundary sync WebView → CookieJar) | `apply_scored_platform_cookies()` | Reads WKHTTPCookieStore, sends to Rust | Reads CookieManager, sends to Rust |
| 5.2 (Cookie replay CookieJar → WebView) | `cookie_replay_queue()` FFI | Reads queue, writes to WKHTTPCookieStore | Reads queue, writes to CookieManager |
| 5.3 (HTTP request cookie handling) | OpenWire interceptors | — | — |
| 6 (Login state detection & maintenance) | `probe_session()`, memory-storage alignment | Calls FFI probe on demand | Calls FFI probe on demand |
| 7 (Conservative logout: strike + probe) | Strike system + probe + passive logout | Observes session snapshots | Observes session snapshots |
| 8 (CSRF management) | BAD CSRF retry + concurrent lock | — | — |
| 9 (Cloudflare) | Detection + signal | CF challenge WebView | CF challenge WebView |
| 10 (Session generation) | Epoch + request lifecycle | Observes epoch | Observes epoch |
| 11 (Platform differences) | — | iOS-specific cookie handling | Android-specific cookie handling |
| 12 (Security) | — | Keychain for credentials | Keystore for credentials |

---

## 2. Rust Core Changes

### 2.1 New FFI Method: `finalize_login_from_webview`

Replaces the current multi-step `syncLoginContext → refreshBootstrap → refreshCsrfToken` dance with a single atomic operation that implements the guide's step [6] login finalization sequence.

```rust
// fire-uniffi-session

fn finalize_login_from_webview(
    &self,
    username: String,
    csrf_token: Option<String>,
    raw_preloaded_html: Option<String>,
    browser_user_agent: Option<String>,
    cookies: Vec<PlatformCookieState>,
    allow_low_confidence_session_cookies: bool,
) -> Result<LoginFinalizationResultState>;

struct LoginFinalizationResultState {
    success: bool,
    session: SessionState,
    t_token_verified: bool,          // _t consistency: CookieJar vs WebView
    fingerprint_wait_needed: bool,   // platform should wait for fingerprint
}

// fire-core implementation:
// 1. Apply scored platform cookies (with low-confidence filtering)
// 2. Verify _t consistency between incoming cookies and merged CookieJar
// 3. Apply username
// 4. Apply CSRF token
// 5. Advance epoch (cuts off old requests)
// 6. Parse raw_preloaded_html → hydrate bootstrap (saves HTTP request)
// 7. If no preloaded data, schedule bootstrap refresh (async, non-blocking)
// 8. Return result
```

### 2.2 Cookie Scoring for Boundary Sync

New scoring system for selecting the best cookie when duplicates exist during WebView → CookieJar sync.

```rust
// fire-core/src/core/cookies.rs

fn score_platform_cookie(cookie: &PlatformCookie, host: &str) -> i64 {
    let mut score: i64 = 0;
    if !cookie.value.is_empty() { score += 100_000; }
    if !cookie.is_expired_now() { score += 50_000; }
    match &cookie.domain {
        None => score += 40_000,                                      // host-only
        Some(d) if d == host => score += 30_000,                     // exact match
        Some(d) if host.ends_with(&format!(".{}", d)) => score += 20_000, // subdomain
        _ => {}
    }
    score
}
```

### 2.3 Low-Confidence Cookie Filtering

Extend `PlatformCookie` with confidence detection.

```rust
// fire-models/src/cookie.rs

impl PlatformCookie {
    fn is_low_confidence(&self) -> bool {
        self.domain.is_none() && self.path.is_none()
    }
}
```

During boundary sync: by default, skip low-confidence session cookies. When `allow_low_confidence_session_cookies = true` (login time), include them.

### 2.4 Cookie Replay Queue

Persist raw `Set-Cookie` headers for replay into WebView.

```rust
// fire-core new module: cookie_replay.rs

struct CookieReplayEntry {
    url: String,
    raw_set_cookie: String,
    cookie_name: String,
    domain: String,
    inserted_at: u64,
}

// Persisted to SQLite in fire-store
// Deduplicated by (cookie_name, domain), keeps latest
// Queue methods:
fn enqueue_set_cookie(url: &str, raw_set_cookie: &str) -> Result<()>;
fn drain_replay_queue() -> Vec<CookieReplayEntry>;
fn clear_replay_queue() -> Result<()>;

// FFI exposure
fn cookie_replay_queue(&self) -> Result<Vec<CookieReplayEntryState>>;
fn clear_cookie_replay_queue(&self) -> Result<()>;
```

Hook into `FireCommonHeaderInterceptor` network interceptor: on every `Set-Cookie` response header, enqueue the raw header + URL.

### 2.5 Strike System and Conservative Logout

```rust
// fire-core new module: auth_strike.rs

struct AuthStrikeState {
    strike_count: u8,
    last_strike_at: Option<Instant>,
    last_signal_strength: Option<SignalStrength>,
    inconclusive_until: Option<Instant>,
    passive_logout_count_24h: u8,
    passive_logout_window_start: Option<Instant>,
}

enum SignalStrength {
    Strong,  // error_type: "not_logged_in" OR 4xx + discourse-logged-out
    Weak,    // 2xx + discourse-logged-out
}

fn receive_auth_signal(strength: SignalStrength) -> StrikeDecision;

enum StrikeDecision {
    Ignore,                    // in logout, cooling down, or probe in progress
    Accumulated { strikes: u8 }, // strike added but threshold not reached
    ProbeNeeded,               // threshold reached, need session probe
}

// fire-core integration:
// In execute_api_request_with_csrf_retry, after detecting
// discourse-logged-out or not_logged_in:
//   1. Classify signal strength
//   2. Call receive_auth_signal
//   3. If ProbeNeeded → run probe_session()
//   4. If probe confirms logout → trigger passive_logout()
```

### 2.6 Session Probe

```rust
// fire-core/src/core/auth.rs addition

fn probe_session(&self) -> Result<ProbeResult>;

enum ProbeResult {
    Valid { username: String },   // GET /session/current.json has current_user
    Invalid,                       // no current_user or 404
    Inconclusive,                  // network error
}

// After probe:
// Valid → reset strikes, restore _t from CookieJar
// Invalid → passive_logout()
// Inconclusive + strikes >= 2 → passive_logout() (prefer false-negative over false-positive)
// Inconclusive + strikes < 2 → enter 30s cooldown
```

### 2.7 Passive Logout

```rust
// fire-core/src/core/auth.rs addition

fn passive_logout(&self, trigger: PassiveLogoutTrigger);

struct PassiveLogoutTrigger {
    source: String,           // "strike_system", "probe_invalid"
    signal_strength: SignalStrength,
    cookie_diagnostic: String,
}

// Steps:
// 1. Advance epoch (cut off all in-flight requests)
// 2. Increment passive_logout_count_24h
// 3. Log passive logout with trigger info
// 4. Execute logout_local(preserve_cf_clearance: true)
// 5. Notify platform via StateObserver.on_session_snapshot()
```

### 2.8 StateObserver Enhancement

Add session state change notifications:

```rust
// fire-uniffi-types

trait StateObserver: Send + Sync {
    fn on_session_snapshot(&self, snapshot: SessionSnapshotState);
    fn on_passive_logout(&self, trigger: PassiveLogoutTriggerState);
    fn on_cf_clearance_expired(&self);
}
```

### 2.9 FFI Method Summary (New)

| Method | Purpose |
|---|---|
| `finalize_login_from_webview(...)` | Atomic login finalization (guide step [6]) |
| `cookie_replay_queue()` | Get Set-Cookie queue for WebView replay |
| `clear_cookie_replay_queue()` | Clear the replay queue |
| `probe_session()` | GET /session/current.json verification |
| `save_credential(username, password)` | Store credential in Rust-managed encrypted store |
| `load_credential()` | Retrieve stored credential |
| `clear_credential()` | Remove stored credential |
| `record_fingerprint_done()` | Notify Rust that fingerprint upload completed |

### 2.10 File Change Summary (Rust)

| File | Change |
|---|---|
| `fire-models/src/cookie.rs` | Add `is_low_confidence()`, add `same_site` field |
| `fire-models/src/session.rs` | Add `PassiveLogoutTrigger`, `ProbeResult` models |
| `fire-store/src/migrations.rs` | New table: `cookie_replay_queue` |
| `fire-store/src/lib.rs` | Add `cookie_replay_queue` module |
| `fire-core/src/core/cookies.rs` | Add `score_platform_cookie()` |
| `fire-core/src/core/session.rs` | Add `finalize_login_from_webview()` |
| `fire-core/src/core/auth.rs` | Add `probe_session()`, `passive_logout()`, strike system |
| `fire-core/src/core/network.rs` | Hook Set-Cookie into replay queue, integrate strike system |
| `fire-core/src/core/mod.rs` | Add `auth_strike` module, `cookie_replay` module |
| `fire-uniffi-types/` | New FFI records for finalization, probe, strike |
| `fire-uniffi-session/` | New FFI methods listed above |

---

## 3. iOS Platform Changes (UIKit, iOS 16+)

### 3.1 New File Structure

All existing login/session SwiftUI views will be **deleted** and replaced with UIKit implementations.

```
native/ios-app/
  App/
    Session/
      FireSessionStore.swift             # REWRITE: actor, sole Rust bridge
      FireWebViewLoginCoordinator.swift  # REWRITE: full guide compliance
      FireAuthCookieKeychainStore.swift  # REWRITE: add credential storage
      FireCfClearanceService.swift       # REWRITE: headless WKWebView auto-renewal
      FireWebViewBrowserProfile.swift    # KEEP: minor updates (add JS scripts)

  Screens/
    Auth/
      FireOnboardingViewController.swift   # NEW: UIKit replacement for OnboardingView
      FireLoginWebViewController.swift     # NEW: UIKit replacement for LoginWebView
      FireCloudflareChallengeViewController.swift  # NEW: dedicated Turnstile popup

  Shared/
    Scripts/
      FireLoginScripts.swift            # NEW: all JS injection scripts
    Widgets/
      FireProgressView.swift            # NEW: UIKit progress indicator
```

**Files to DELETE:**
- `App/Views/Other/LoginWebView.swift` (SwiftUI `FireAuthScreen`)
- `App/Views/Other/OnboardingView.swift` (SwiftUI)
- Any other SwiftUI login-related views

### 3.2 FireLoginScripts — JavaScript Injection Scripts

Centralized Swift object holding all JS scripts per the guide.

```swift
enum FireLoginScripts {
    // Section 4.1: Preloaded data capture (AT_DOCUMENT_START)
    static var preloadedDataCapture: WKUserScript {
        let source = """
        new MutationObserver(function(_, obs) {
          var el = document.querySelector('[data-preloaded]');
          if (!el) return;
          obs.disconnect();
          var parts = [el.outerHTML];
          document.querySelectorAll('meta[name]').forEach(function(m) {
            parts.push(m.outerHTML);
          });
          var setup = document.getElementById('data-discourse-setup');
          if (setup) parts.push(setup.outerHTML);
          window.__rawPreloaded = parts.join('\\n');
        }).observe(document.documentElement, {childList: true, subtree: true});
        """
        return WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    // Section 4.2: Credential auto-fill + login button hook
    static func credentialAutoFill(username: String?, password: String?) -> WKUserScript {
        let escapedUser = username.flatMap { JSONEncoder().encode($0) } ?? "null"
        let escapedPass = password.flatMap { JSONEncoder().encode($0) } ?? "null"
        // ... full script from guide Section 4.2
        // On button click: webkit.messageHandlers.loginCredentials.postMessage(...)
    }

    // Section 4.3: Fingerprint intercept
    static var fingerprintIntercept: WKUserScript {
        // ... full script from guide Section 4.3
        // On intercept: webkit.messageHandlers.fingerprintDone.postMessage("done")
    }

    // Section 4.4: Current username reading
    static var readCurrentUsername: String {
        """(function(){try{var m=document.querySelector('meta[name="current-username"]');if(m&&m.content)return m.content;if(typeof Discourse!=='undefined'&&Discourse.User&&Discourse.User.current())return Discourse.User.current().username;return null}catch(e){return null}})()"""
    }

    // Section 4.5: CSRF token extraction
    static var readCsrfToken: String {
        """(function(){var m=document.querySelector('meta[name="csrf-token"]');return m&&m.content?m.content:null})()"""
    }

    // Preloaded data reading
    static var readPreloadedData: String {
        """(function(){return window.__rawPreloaded||null})()"""
    }
}
```

### 3.3 FireLoginWebViewController — Full Guide Compliance

```swift
final class FireLoginWebViewController: UIViewController {
    // WKWebView + toolbar + loading indicator
    private let webView = WKWebView()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private var syncButton: UIBarButtonItem!
    private var statusLabel: UILabel!

    // State
    private var loginDetected = false
    private var fingerprintDone = false
    private var fingerprintWaitTimer: Timer?
    private var tCookieRetryCount = 0
    private var tCookieRetryTimer: Timer?
    private let maxTCookieRetries = 15
    private let tCookieRetryInterval: TimeInterval = 0.5

    // Dependencies (injected)
    private let sessionStore: FireSessionStore
    private let loginCoordinator: FireWebViewLoginCoordinator

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupWebView()
        replayCookiesAndLoadLogin()
    }

    // MARK: - Step [1]: Cookie replay (CookieJar → WebView)

    private func replayCookiesAndLoadLogin() {
        Task {
            // 1. Get replay queue from Rust
            let replayEntries = await sessionStore.cookieReplayQueue()

            // 2. Write each Set-Cookie into WKHTTPCookieStore
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            for entry in replayEntries {
                let cookies = HTTPCookie.cookies(
                    withResponseHeaderFields: ["Set-Cookie": entry.rawSetCookie],
                    for: URL(string: entry.url)!
                )
                for cookie in cookies {
                    await cookieStore.setCookie(cookie)
                }
            }

            // 3. hCaptcha cookie injection (if available)
            // Note: iOS WKWebView blocks 3rd-party iframe cookies,
            // so hc_accessibility injection is best-effort only

            // 4. Load login URL after replay completes
            let loginURL = URL(string: "\(sessionStore.baseUrl)/login")!
            webView.load(URLRequest(url: loginURL))
        }
    }

    // MARK: - Step [3]: Inject scripts on page load

    private func injectPageScripts() {
        // Scripts are already added via WKUserContentController in setupWebView()
        // This method is called from WKNavigationDelegate.didFinish navigation
    }

    // MARK: - Step [4]-[5]: Automatic login detection

    private func checkLoginState() {
        Task {
            // 1. Read current username via JS
            let username = try? await webView.evaluateJavaScript(
                FireLoginScripts.readCurrentUsername
            ) as? String

            guard username != nil else { return }

            // 2. Wait for initial cookie replay to complete
            let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
            let allCookies = await cookieStore.allCookies()

            // 3. Find _t cookie
            let tCookie = allCookies.first { $0.name == "_t" }

            if let tCookie, !tCookie.value.isEmpty {
                // _t found → proceed to finalization
                loginDetected = true
                cancelTCookieRetry()
                finalizeLogin()
            } else {
                // _t not found → schedule retry (guide: 15 times, 500ms)
                scheduleTCookieRetry()
            }
        }
    }

    private func scheduleTCookieRetry() {
        guard tCookieRetryCount < maxTCookieRetries else { return }
        tCookieRetryCount += 1
        tCookieRetryTimer = Timer.scheduledTimer(
            withTimeInterval: tCookieRetryInterval,
            blocks: { [weak self] _ in self?.checkLoginState() }
        )
    }

    private func cancelTCookieRetry() {
        tCookieRetryTimer?.invalidate()
        tCookieRetryTimer = nil
        tCookieRetryCount = 0
    }

    // MARK: - Step [6]: Login finalization

    private func finalizeLogin() {
        Task {
            // a. Read all relevant cookies from WKHTTPCookieStore
            let cookies = await loginCoordinator.readRelevantCookies(from: webView)

            // b. Read CSRF token via JS
            let csrfToken = try? await webView.evaluateJavaScript(
                FireLoginScripts.readCsrfToken
            ) as? String

            // c. Read preloaded data via JS
            let preloadedHTML = try? await webView.evaluateJavaScript(
                FireLoginScripts.readPreloadedData
            ) as? String

            // d. Read current username
            let username = try? await webView.evaluateJavaScript(
                FireLoginScripts.readCurrentUsername
            ) as? String

            // e. Call Rust finalize_login_from_webview (atomic)
            let result = try? await sessionStore.finalizeLoginFromWebView(
                username: username ?? "",
                csrfToken: csrfToken,
                rawPreloadedHtml: preloadedHTML,
                browserUserAgent: webView.customUserAgent,
                cookies: cookies,
                allowLowConfidenceSessionCookies: true
            )

            // f. Verify _t consistency
            if let result, !result.tTokenVerified {
                // Log warning: CookieJar _t differs from WebView _t
                // CookieJar value is authoritative (per guide)
            }

            // g. Wait for fingerprint (max 15s)
            if result?.fingerprintWaitNeeded == true {
                waitForFingerprintThenClose()
            } else {
                closeAndNotifySuccess()
            }
        }
    }

    // MARK: - Fingerprint wait

    private func waitForFingerprintThenClose() {
        // Already listening via WKScriptMessageHandler "fingerprintDone"
        // Set a 15-second timeout
        fingerprintWaitTimer = Timer.scheduledTimer(
            withTimeInterval: 15.0,
            blocks: { [weak self] _ in
                self?.fingerprintDone = true  // timeout, proceed anyway
                self?.closeAndNotifySuccess()
            }
        )
    }

    // Called by WKScriptMessageHandler when fingerprint intercept fires
    private func onFingerprintDone() {
        guard !fingerprintDone else { return }
        fingerprintDone = true
        fingerprintWaitTimer?.invalidate()
        Task { await sessionStore.recordFingerprintDone() }
        closeAndNotifySuccess()
    }

    // MARK: - Close

    private func closeAndNotifySuccess() {
        cancelTCookieRetry()
        dismiss(animated: true) {
            // Notify app that login completed
        }
    }
}

// MARK: - WKNavigationDelegate

extension FireLoginWebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Step [3]: Page load complete → inject scripts already done via WKUserScript
        // Check login state (first detection)
        checkLoginState()
    }
}

// MARK: - WKScriptMessageHandler

extension FireLoginWebViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        switch message.name {
        case "loginCredentials":
            // Section 4.2: Save captured credentials to Keychain
            if let body = message.body as? [String: String],
               let username = body["username"],
               let password = body["password"] {
                Task { await KeychainHelper.saveCredential(username: username, password: password) }
            }
        case "fingerprintDone":
            onFingerprintDone()
        default:
            break
        }
    }
}
```

### 3.4 FireOnboardingViewController

```swift
final class FireOnboardingViewController: UIViewController {
    // UIKit replacement for SwiftUI OnboardingView
    // - "Login LinuxDo" button → present FireLoginWebViewController
    // - "Restore Existing Session" button → restore persisted session
    // - Email link login: paste from clipboard + detect /session/email-login/ URLs
    // - Observe StateObserver.on_session_snapshot for automatic navigation to home
}
```

### 3.5 FireCloudflareChallengeViewController

```swift
final class FireCloudflareChallengeViewController: UIViewController {
    // Dedicated Turnstile challenge popup (guide Section 9.2 Plan B)
    // - Loads minimal page with Turnstile widget
    // - Monitors WKHTTPCookieStore for cf_clearance appearance
    // - On cf_clearance detected: sync to Rust via boundary sync
    // - Auto-close + notify retry
}
```

### 3.6 FireAuthCookieKeychainStore Enhancement

Add credential (username/password) storage alongside cookie storage:

```swift
extension FireKeychainAuthCookieStore {
    func saveCredential(username: String, password: String) async throws
    func loadCredential() async -> (username: String, password: String)?
    func clearCredential() async throws
}
```

### 3.7 FireCfClearanceService Rewrite

Existing headless WKWebView auto-renewal service. Rewrite to:
- Use the `AT_DOCUMENT_START` injection pattern from the guide
- Set proper `Sec-Fetch-*` headers on native rc requests
- Integrate with `StateObserver.on_cf_clearance_expired()` to start renewal

### 3.8 FireWebViewBrowserProfile Enhancement

Add JS scripts to the WKUserContentController:

```swift
static func makeLoginConfiguration(
    credential: (username: String, password: String)?
) -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    let contentController = WKUserContentController()

    // Section 4.1: Preloaded data capture (AT_DOCUMENT_START)
    contentController.addUserScript(FireLoginScripts.preloadedDataCapture)

    // Section 4.2: Credential auto-fill (AT_DOCUMENT_END)
    if let credential {
        contentController.addUserScript(
            FireLoginScripts.credentialAutoFill(
                username: credential.username,
                password: credential.password
            )
        )
    }

    // Section 4.3: Fingerprint intercept (AT_DOCUMENT_END)
    contentController.addUserScript(FireLoginScripts.fingerprintIntercept)

    // Message handlers
    contentController.add(self, name: "loginCredentials")
    contentController.add(self, name: "fingerprintDone")

    config.userContentController = contentController
    // ... rest of configuration
    return config
}
```

### 3.9 iOS File Change Summary

| File | Action | Description |
|---|---|---|
| `App/Views/Other/LoginWebView.swift` | **DELETE** | SwiftUI login screen, replaced by UIKit |
| `App/Views/Other/OnboardingView.swift` | **DELETE** | SwiftUI onboarding, replaced by UIKit |
| `Screens/Auth/FireOnboardingViewController.swift` | **NEW** | UIKit onboarding screen |
| `Screens/Auth/FireLoginWebViewController.swift` | **NEW** | UIKit login WebView, full guide compliance |
| `Screens/Auth/FireCloudflareChallengeViewController.swift` | **NEW** | Dedicated CF challenge popup |
| `Shared/Scripts/FireLoginScripts.swift` | **NEW** | All JS injection scripts |
| `Session/FireWebViewLoginCoordinator.swift` | **REWRITE** | Remove old capture logic, use `finalize_login_from_webview` FFI |
| `Session/FireSessionStore.swift` | **REWRITE** | Add new FFI methods, remove old multi-step dance |
| `Session/FireAuthCookieKeychainStore.swift` | **REWRITE** | Add credential storage |
| `Session/FireCfClearanceService.swift` | **REWRITE** | Full guide CF compliance |
| `Session/FireWebViewBrowserProfile.swift` | **UPDATE** | Add login JS scripts to configuration |
| `ViewModels/FireAppViewModel.swift` | **UPDATE** | Remove SwiftUI auth flow, use new UIKit VCs |

---

## 4. Android Platform Changes (androidx, API 26+)

### 4.1 New File Structure

```
native/android-app/src/main/java/com/fire/app/
  session/
    FireSessionStore.kt                 # REWRITE: add new FFI methods
    FireWebViewLoginCoordinator.kt      # REWRITE: full guide compliance
    FireCredentialStore.kt              # NEW: EncryptedSharedPreferences credential storage
    FireCfClearanceService.kt           # REWRITE: headless WebView auto-renewal

  ui/auth/
    FireOnboardingFragment.kt           # REWRITE: email link login, auto-detect
    FireLoginWebViewFragment.kt         # REWRITE: full guide compliance
    FireCloudflareChallengeFragment.kt  # NEW: dedicated Turnstile popup

  core/
    scripts/
      FireLoginScripts.kt               # NEW: all JS injection scripts
```

**Files to DELETE:**
- `session/FireSessionStoreRepository.kt` (unnecessary indirection)
- `data/repository/SessionRepository.kt` (logic moves to Rust)
- `ui/auth/AuthViewModel.kt` (login flow becomes coordinator-driven)

### 4.2 FireLoginScripts — JavaScript Injection Scripts (Kotlin)

```kotlin
object FireLoginScripts {
    // Section 4.1: Preloaded data capture (injected at page start)
    val preloadedDataCapture: String = """
        new MutationObserver(function(_, obs) {
          var el = document.querySelector('[data-preloaded]');
          if (!el) return;
          obs.disconnect();
          var parts = [el.outerHTML];
          document.querySelectorAll('meta[name]').forEach(function(m) {
            parts.push(m.outerHTML);
          });
          var setup = document.getElementById('data-discourse-setup');
          if (setup) parts.push(setup.outerHTML);
          window.__rawPreloaded = parts.join('\\n');
        }).observe(document.documentElement, {childList: true, subtree: true});
    """

    // Section 4.2: Credential auto-fill + login button hook
    fun credentialAutoFill(username: String?, password: String?): String {
        val escapedUser = username?.let { Gson().toJson(it) } ?: "null"
        val escapedPass = password?.let { Gson().toJson(it) } ?: "null"
        return """
        (function() {
          var savedUser = $escapedUser;
          var savedPass = $escapedPass;
          var filled = false;
          var hooked = false;
          var attempts = 0;
          var timer = setInterval(function() {
            var userInput = document.getElementById('login-account-name');
            var passInput = document.getElementById('login-account-password');
            if (userInput && passInput) {
              if (!filled && savedUser && savedPass) {
                filled = true;
                userInput.value = savedUser;
                passInput.value = savedPass;
                userInput.dispatchEvent(new Event('input', {bubbles: true}));
                passInput.dispatchEvent(new Event('input', {bubbles: true}));
              }
              if (!hooked) {
                hooked = true;
                var loginBtn = document.getElementById('login-button');
                if (loginBtn) {
                  loginBtn.addEventListener('click', function() {
                    var u = document.getElementById('login-account-name');
                    var p = document.getElementById('login-account-password');
                    if (u && p && u.value && p.value) {
                      Android.onLoginCredentials(u.value, p.value);
                    }
                  }, true);
                }
              }
              clearInterval(timer);
            }
            if (++attempts > 30) clearInterval(timer);
          }, 300);
        })();
        """
    }

    // Section 4.3: Fingerprint intercept
    val fingerprintIntercept: String = """
        (function() {
          if (window.__fpHooked) return;
          window.__fpHooked = true;
          function notify() {
            try { Android.onFingerprintDone(); } catch(e) {}
          }
          var _f = window.fetch;
          window.fetch = function(input, init) {
            var result = _f.apply(this, arguments);
            if (init && init.method && init.method.toUpperCase() === 'POST' &&
                typeof init.body === 'string' && init.body.indexOf('visitor_id=') !== -1) {
              result.then(notify, notify);
            }
            return result;
          };
          var _o = XMLHttpRequest.prototype.open;
          var _s = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function(m, u) {
            this._m = m;
            return _o.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function(body) {
            if (this._m === 'POST' && typeof body === 'string' &&
                body.indexOf('visitor_id=') !== -1) {
              this.addEventListener('loadend', notify);
            }
            return _s.apply(this, arguments);
          };
        })();
    """

    // Section 4.4: Current username reading
    val readCurrentUsername = """
        (function(){try{var m=document.querySelector('meta[name="current-username"]');
        if(m&&m.content)return m.content;
        if(typeof Discourse!=='undefined'&&Discourse.User&&Discourse.User.current())
        return Discourse.User.current().username;return null}catch(e){return null}})()
    """

    // Section 4.5: CSRF token extraction
    val readCsrfToken = """
        (function(){var m=document.querySelector('meta[name="csrf-token"]');
        return m&&m.content?m.content:null})()
    """

    // Preloaded data reading
    val readPreloadedData = """
        (function(){return window.__rawPreloaded||null})()
    """
}
```

### 4.3 FireLoginWebViewFragment — Full Guide Compliance

```kotlin
class FireLoginWebViewFragment : Fragment() {
    private lateinit var webView: WebView
    private lateinit var syncButton: Button
    private lateinit var progressBar: ProgressBar

    private var loginDetected = false
    private var fingerprintDone = false
    private var fingerprintJob: Job? = null
    private var tCookieRetryCount = 0
    private var tCookieRetryJob: Job? = null

    // MARK: - Step [1]: Cookie replay (CookieJar → WebView)

    private fun replayCookiesAndLoadLogin() {
        lifecycleScope.launch {
            // 1. Get replay queue from Rust
            val replayEntries = sessionStore.cookieReplayQueue()

            // 2. Write each Set-Cookie into CookieManager
            val cookieManager = CookieManager.getInstance()
            for (entry in replayEntries) {
                cookieManager.setCookie(entry.url, entry.rawSetCookie)
            }

            // 3. hCaptcha cookie injection (hc_accessibility to hcaptcha.com)
            // Only works on Android (iOS blocks 3rd-party iframe cookies)
            val hcCookie = sessionStore.hcaptchaAccessibilityCookie()
            if (hcCookie != null) {
                cookieManager.setCookie("https://hcaptcha.com", hcCookie)
            }

            // 4. Load login URL after replay
            cookieManager.flush()
            webView.loadUrl("${sessionStore.baseUrl()}/login")
        }
    }

    // MARK: - Step [3]-[5]: Automatic login detection

    private fun checkLoginState() {
        lifecycleScope.launch {
            // 1. Read username via JS
            val username = evaluateJS(FireLoginScripts.readCurrentUsername)

            if (username.isNullOrBlank()) return@launch

            // 2. Read _t from CookieManager
            val cookies = CookieManager.getInstance().getCookie(sessionStore.baseUrl()) ?: ""
            val tToken = cookies.split(";")
                .map { it.trim() }
                .firstOrNull { it.startsWith("_t=") }
                ?.removePrefix("_t=")

            if (!tToken.isNullOrBlank()) {
                loginDetected = true
                cancelTCookieRetry()
                finalizeLogin(username, tToken)
            } else {
                // _t not found → schedule retry (15 times, 500ms)
                scheduleTCookieRetry()
            }
        }
    }

    private fun scheduleTCookieRetry() {
        if (tCookieRetryCount >= 15) return
        tCookieRetryCount++
        tCookieRetryJob = lifecycleScope.launch {
            delay(500)
            checkLoginState()
        }
    }

    // MARK: - Step [6]: Login finalization

    private fun finalizeLogin(username: String, webViewTToken: String) {
        lifecycleScope.launch {
            // a. Read all cookies from CookieManager
            val cookies = readPlatformCookiesFromWebView()

            // b. Read CSRF via JS
            val csrfToken = evaluateJS(FireLoginScripts.readCsrfToken)

            // c. Read preloaded data via JS
            val preloadedHTML = evaluateJS(FireLoginScripts.readPreloadedData)

            // d. Call Rust finalize_login_from_webview (atomic)
            val result = sessionStore.finalizeLoginFromWebView(
                username = username,
                csrfToken = csrfToken,
                rawPreloadedHtml = preloadedHTML,
                browserUserAgent = webView.settings.userAgentString,
                cookies = cookies,
                allowLowConfidenceSessionCookies = true
            )

            // e. Verify _t consistency
            if (result != null && !result.tTokenVerified) {
                Log.w("Login", "CookieJar _t differs from WebView _t")
            }

            // f. Wait for fingerprint (max 15s)
            if (result?.fingerprintWaitNeeded == true) {
                waitForFingerprintThenClose()
            } else {
                closeAndNotifySuccess()
            }
        }
    }

    // MARK: - Fingerprint wait

    private fun waitForFingerprintThenClose() {
        fingerprintJob = lifecycleScope.launch {
            delay(15_000)  // 15 second timeout
            if (!fingerprintDone) {
                fingerprintDone = true
                sessionStore.recordFingerprintDone()
                closeAndNotifySuccess()
            }
        }
    }

    // Called by JS interface when fingerprint intercept fires
    fun onFingerprintDone() {
        if (fingerprintDone) return
        fingerprintDone = true
        fingerprintJob?.cancel()
        lifecycleScope.launch {
            sessionStore.recordFingerprintDone()
            closeAndNotifySuccess()
        }
    }

    // Called by JS interface when login button is clicked
    fun onLoginCredentials(username: String, password: String) {
        lifecycleScope.launch {
            FireCredentialStore.saveCredential(username, password)
        }
    }

    private fun closeAndNotifySuccess() {
        cancelTCookieRetry()
        // Navigate to home
    }
}

// WebView JS interface
class FireLoginJsInterface(private val fragment: FireLoginWebViewFragment) {
    @JavascriptInterface
    fun onLoginCredentials(username: String, password: String) {
        fragment.onLoginCredentials(username, password)
    }

    @JavascriptInterface
    fun onFingerprintDone() {
        fragment.onFingerprintDone()
    }
}
```

### 4.4 FireCredentialStore

```kotlin
object FireCredentialStore {
    private const val FILENAME = "fire_credentials"
    private const val KEY_USERNAME = "username"
    private const val KEY_PASSWORD = "password"

    suspend fun saveCredential(username: String, password: String) {
        val context = FireApplication.instance
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        val prefs = EncryptedSharedPreferences.create(
            context, FILENAME, masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
        prefs.edit()
            .putString(KEY_USERNAME, username)
            .putString(KEY_PASSWORD, password)
            .apply()
    }

    suspend fun loadCredential(): Pair<String, String>? { /* ... */ }
    suspend fun clearCredential() { /* ... */ }
}
```

### 4.5 FireCloudflareChallengeFragment

```kotlin
class FireCloudflareChallengeFragment : BottomSheetDialogFragment() {
    // Dedicated Turnstile challenge popup (guide Section 9.2 Plan B)
    // - Loads minimal page with Turnstile widget
    // - Monitors CookieManager for cf_clearance appearance
    // - On cf_clearance detected: sync to Rust via boundary sync
    // - Auto-dismiss + notify retry
}
```

### 4.6 WebViewClient Integration

```kotlin
inner class LoginWebViewClient : WebViewClient() {
    // Step [3]: onLoadStop → check login state
    override fun onPageFinished(view: WebView?, url: String?) {
        super.onPageFinished(view, url)
        checkLoginState()
    }

    // Step [4]: onUpdateVisitedHistory → check login state
    override fun doUpdateVisitedHistory(view: WebView?, url: String?, isReload: Boolean) {
        super.doUpdateVisitedHistory(view, url, isReload)
        checkLoginState()
    }

    // Step [4]: onLoadResource → detect home page response → check login state
    override fun onLoadResource(view: WebView?, url: String?) {
        super.onLoadResource(view, url)
        if (url == baseUrl || url == "$baseUrl/") {
            checkLoginState()
        }
    }
}
```

### 4.7 Android File Change Summary

| File | Action | Description |
|---|---|---|
| `session/FireSessionStoreRepository.kt` | **DELETE** | Unnecessary indirection |
| `data/repository/SessionRepository.kt` | **DELETE** | Logic moves to Rust |
| `ui/auth/AuthViewModel.kt` | **DELETE** | Login flow becomes coordinator-driven |
| `session/FireSessionStore.kt` | **REWRITE** | Add new FFI methods, remove old multi-step dance |
| `session/FireWebViewLoginCoordinator.kt` | **REWRITE** | Full guide compliance |
| `session/FireCfClearanceService.kt` | **REWRITE** | Headless WebView auto-renewal |
| `session/FireCredentialStore.kt` | **NEW** | EncryptedSharedPreferences credential storage |
| `ui/auth/FireOnboardingFragment.kt` | **REWRITE** | Email link login, auto-observe session |
| `ui/auth/FireLoginWebViewFragment.kt` | **REWRITE** | Full guide compliance, JS injection, auto-detect |
| `ui/auth/FireCloudflareChallengeFragment.kt` | **NEW** | Dedicated Turnstile popup |
| `core/scripts/FireLoginScripts.kt` | **NEW** | All JS injection scripts |
| `ui/cloudflare/CloudflareChallengeActivity.kt` | **DELETE** | Replaced by FireCloudflareChallengeFragment |
| `ui/cloudflare/CloudflareChallengeSupport.kt` | **DELETE** | Logic absorbed into new fragment |
| `cloudflare/CloudflareChallengeDetector.kt` | **DELETE** | Detection now in Rust |

### 4.8 New Gradle Dependency

```kotlin
// EncryptedSharedPreferences for credential storage
implementation("androidx.security:security-crypto:1.1.0-alpha06")
```

Note: `security-crypto` 1.1.0+ requires API 23+, which is within our API 26 minimum.

---

## 5. Cross-Platform Verification Checklist

After implementation, verify each guide requirement on both platforms:

| # | Requirement | iOS | Android |
|---|---|---|---|
| 1 | Cookie replay before loading `/login` | ☐ | ☐ |
| 2 | hCaptcha `hc_accessibility` injection | ☐ (best-effort, iOS blocks 3rd-party) | ☐ |
| 3 | `AT_DOCUMENT_START` MutationObserver for `__rawPreloaded` | ☐ | ☐ |
| 4 | Credential auto-fill (`#login-account-name/password`) | ☐ | ☐ |
| 5 | Login button hook (`#login-button` click → save credential) | ☐ | ☐ |
| 6 | Fingerprint intercept (`visitor_id=` POST hook) | ☐ | ☐ |
| 7 | Auto-detect login (`onLoadStop` / `onUpdateVisitedHistory` / `onLoadResource`) | ☐ | ☐ |
| 8 | `_t` cookie retry (15x @ 500ms) | ☐ | ☐ |
| 9 | Login finalization: atomic FFI call | ☐ | ☐ |
| 10 | Cookie scoring in boundary sync | ☐ (in Rust) | ☐ (in Rust) |
| 11 | Low-confidence cookie filtering | ☐ (in Rust) | ☐ (in Rust) |
| 12 | `_t` consistency verification | ☐ (in Rust) | ☐ (in Rust) |
| 13 | Epoch advance on login finalization | ☐ (in Rust) | ☐ (in Rust) |
| 14 | Fingerprint wait (max 15s) | ☐ | ☐ |
| 15 | Preloaded data hydration (avoid extra HTTP) | ☐ (in Rust) | ☐ (in Rust) |
| 16 | Strike system (strong=1, weak=2, 45s window) | ☐ (in Rust) | ☐ (in Rust) |
| 17 | Session probe (`GET /session/current.json`) | ☐ (in Rust) | ☐ (in Rust) |
| 18 | Passive logout with 24h count tracking | ☐ (in Rust) | ☐ (in Rust) |
| 19 | BAD CSRF retry (clear → refresh → retry once) | ☐ (in Rust) | ☐ (in Rust) |
| 20 | Concurrent CSRF refresh lock | ☐ (in Rust) | ☐ (in Rust) |
| 21 | `discourse-logged-out` header detection | ☐ (in Rust) | ☐ (in Rust) |
| 22 | CF challenge detection | ☐ (in Rust) | ☐ (in Rust) |
| 23 | CF challenge popup (Plan B) | ☐ | ☐ |
| 24 | CF clearance auto-renewal (Plan C) | ☐ | ☐ |
| 25 | `Sec-Fetch-*` / `Origin` / `Referer` headers | ☐ (in Rust) | ☐ (in Rust) |
| 26 | Credential storage (Keychain / EncryptedSharedPreferences) | ☐ | ☐ |
| 27 | Email link login (`/session/email-login/`) | ☐ | ☐ |
| 28 | `Discourse-Logged-In` / `Discourse-Present` headers | ☐ (in Rust) | ☐ (in Rust) |
| 29 | Session persistence (JSON file) | ☐ (in Rust) | ☐ (in Rust) |
| 30 | Cookie replay queue (Set-Cookie persistence) | ☐ (in Rust) | ☐ (in Rust) |
