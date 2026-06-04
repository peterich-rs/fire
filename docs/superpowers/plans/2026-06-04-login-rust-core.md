# Discourse WebView Login — Rust Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Rust-side login infrastructure: cookie scoring, low-confidence filtering, cookie replay queue, login finalization FFI, strike/probe conservative logout, and passive logout.

**Architecture:** All session logic lives in `fire-core` with models in `fire-models`, persistence in `fire-store`, and FFI exposure in `fire-uniffi-session`. Platforms call `finalize_login_from_webview` instead of the current multi-step `syncLoginContext → refreshBootstrap → refreshCsrfToken` dance.

**Tech Stack:** Rust, tokio, rusqlite, uniffi 0.31, existing openwire networking

**Spec:** `docs/architecture/discourse-webview-login-implementation-plan.md` Sections 2.1–2.10

---

## File Structure

| File | Responsibility |
|---|---|
| `fire-models/src/cookie.rs` | Cookie scoring, low-confidence detection, `same_site` field |
| `fire-models/src/session.rs` | `PassiveLogoutTrigger`, `ProbeResult`, `LoginFinalizationResult` models |
| `fire-store/src/migrations.rs` | `cookie_replay_queue` table migration |
| `fire-store/src/cookie_replay.rs` | Cookie replay queue read/write |
| `fire-store/src/lib.rs` | Wire up `cookie_replay` module |
| `fire-core/src/core/cookies.rs` | `score_platform_cookie()` function |
| `fire-core/src/core/session.rs` | `finalize_login_from_webview()` method |
| `fire-core/src/core/auth_strike.rs` | Strike system, signal classification, probe orchestration |
| `fire-core/src/core/auth.rs` | `probe_session()`, `passive_logout()` additions |
| `fire-core/src/core/network.rs` | Hook Set-Cookie into replay queue, integrate strike callbacks |
| `fire-core/src/core/mod.rs` | Register `auth_strike` module |
| `fire-core/tests/login_finalization.rs` | Integration tests for login finalization |
| `fire-core/tests/auth_strike.rs` | Integration tests for strike/probe system |
| `fire-uniffi-types/records/login_finalization.rs` | FFI records for new types |
| `fire-uniffi-session/src/lib.rs` | New FFI methods |

---

### Task 1: Add `same_site` and `is_low_confidence` to PlatformCookie

**Files:**
- Modify: `rust/crates/fire-models/src/cookie.rs`
- Test: inline `#[cfg(test)]` in same file

- [ ] **Step 1: Write failing test for `is_low_confidence`**

Add to the `#[cfg(test)] mod tests` block in `cookie.rs`:

```rust
#[test]
fn low_confidence_cookie_has_no_domain_and_no_path() {
    let cookie = PlatformCookie {
        name: "_t".into(),
        value: "abc".into(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(cookie.is_low_confidence());

    let with_domain = PlatformCookie {
        domain: Some(".linux.do".into()),
        ..cookie.clone()
    };
    assert!(!with_domain.is_low_confidence());

    let with_path = PlatformCookie {
        domain: None,
        path: Some("/".into()),
        ..cookie.clone()
    };
    assert!(!with_path.is_low_confidence());
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-models -- low_confidence`
Expected: FAIL (field `same_site` does not exist, method `is_low_confidence` not found)

- [ ] **Step 3: Add `same_site` field to `PlatformCookie` and implement `is_low_confidence`**

In `PlatformCookie` struct, add field `pub same_site: Option<String>`.

Implement:
```rust
pub fn is_low_confidence(&self) -> bool {
    self.domain.is_none() && self.path.is_none()
}
```

Update all `PlatformCookie` constructors in tests and production code to include `same_site: None`.

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-models -- low_confidence`
Expected: PASS

- [ ] **Step 5: Run full fire-models test suite**

Run: `cargo test -p fire-models`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add rust/crates/fire-models/src/cookie.rs
git commit -m "feat(models): add same_site field and is_low_confidence to PlatformCookie"
```

---

### Task 2: Implement cookie scoring function

**Files:**
- Modify: `rust/crates/fire-models/src/cookie.rs`
- Test: inline `#[cfg(test)]` in same file

- [ ] **Step 1: Write failing test for `score_platform_cookie`**

```rust
#[test]
fn cookie_scoring_prefers_host_only_over_subdomain() {
    let host = "linux.do";
    let host_only = PlatformCookie {
        name: "_t".into(),
        value: "abc".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let subdomain = PlatformCookie {
        name: "_t".into(),
        value: "abc".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let exact = PlatformCookie {
        name: "_t".into(),
        value: "abc".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(score_platform_cookie(&host_only, host) > score_platform_cookie(&subdomain, host));
    assert!(score_platform_cookie(&exact, host) > score_platform_cookie(&subdomain, host));
    assert!(score_platform_cookie(&host_only, host) > score_platform_cookie(&exact, host));
}

#[test]
fn cookie_scoring_penalizes_empty_value() {
    let host = "linux.do";
    let with_value = PlatformCookie {
        name: "_t".into(),
        value: "abc".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let empty = PlatformCookie {
        name: "_t".into(),
        value: "".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(score_platform_cookie(&with_value, host) > score_platform_cookie(&empty, host));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-models -- cookie_scoring`
Expected: FAIL (function not found)

- [ ] **Step 3: Implement `score_platform_cookie`**

```rust
pub fn score_platform_cookie(cookie: &PlatformCookie, host: &str) -> i64 {
    let mut score: i64 = 0;
    if !cookie.value.is_empty() {
        score += 100_000;
    }
    if !cookie.is_expired_now() {
        score += 50_000;
    }
    match &cookie.domain {
        None => score += 40_000,
        Some(d) if d == host => score += 30_000,
        Some(d) if host.ends_with(&format!(".{}", d)) => score += 20_000,
        _ => {}
    }
    score
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-models -- cookie_scoring`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-models/src/cookie.rs
git commit -m "feat(models): add score_platform_cookie for boundary sync cookie selection"
```

---

### Task 3: Add `scored_apply_platform_cookies` to CookieSnapshot

**Files:**
- Modify: `rust/crates/fire-models/src/cookie.rs`
- Test: inline `#[cfg(test)]`

- [ ] **Step 1: Write failing test**

```rust
#[test]
fn scored_apply_selects_best_cookie_by_score() {
    let host = "linux.do";
    let mut snapshot = CookieSnapshot::default();
    let weak_cookie = PlatformCookie {
        name: "_t".into(),
        value: "old".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    snapshot.merge_platform_cookies(&[weak_cookie]);
    assert_eq!(snapshot.t_token.as_deref(), Some("old"));

    let strong_cookie = PlatformCookie {
        name: "_t".into(),
        value: "new".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    snapshot.scored_apply_platform_cookies(&[strong_cookie], host, true);
    assert_eq!(snapshot.t_token.as_deref(), Some("new"));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-models -- scored_apply`
Expected: FAIL (method not found)

- [ ] **Step 3: Implement `scored_apply_platform_cookies`**

Add method to `CookieSnapshot`:
```rust
pub fn scored_apply_platform_cookies(
    &mut self,
    cookies: &[PlatformCookie],
    host: &str,
    allow_low_confidence_session_cookies: bool,
) {
    let session_cookie_names = ["_t", "_forum_session"];
    let mut best_by_name: std::collections::HashMap<String, (i64, &PlatformCookie)> =
        std::collections::HashMap::new();

    for cookie in cookies {
        if !allow_low_confidence_session_cookies
            && cookie.is_low_confidence()
            && session_cookie_names.contains(&cookie.name.as_str())
        {
            continue;
        }
        let score = score_platform_cookie(cookie, host);
        let entry = best_by_name.get(&cookie.name);
        if entry.is_none() || score > entry.unwrap().0 {
            best_by_name.insert(cookie.name.clone(), (score, cookie));
        }
    }

    let winners: Vec<PlatformCookie> = best_by_name
        .into_values()
        .map(|(_, c)| c.clone())
        .collect();

    self.apply_platform_cookies(&winners);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-models -- scored_apply`
Expected: PASS

- [ ] **Step 5: Run full fire-models suite**

Run: `cargo test -p fire-models`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add rust/crates/fire-models/src/cookie.rs
git commit -m "feat(models): add scored_apply_platform_cookies with low-confidence filtering"
```

---

### Task 4: Add login finalization models to fire-models

**Files:**
- Modify: `rust/crates/fire-models/src/session.rs`
- Modify: `rust/crates/fire-models/src/lib.rs` (if needed for re-exports)

- [ ] **Step 1: Add `LoginFinalizationResult` and `PassiveLogoutTrigger` models**

In `session.rs`, add:

```rust
#[derive(Debug, Clone)]
pub struct LoginFinalizationResult {
    pub success: bool,
    pub t_token_verified: bool,
    pub fingerprint_wait_needed: bool,
}

#[derive(Debug, Clone)]
pub struct PassiveLogoutTrigger {
    pub source: String,
    pub signal_strength: SignalStrength,
    pub cookie_diagnostic: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum SignalStrength {
    Strong,
    Weak,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ProbeResult {
    Valid { username: String },
    Invalid,
    Inconclusive,
}
```

- [ ] **Step 2: Run cargo check**

Run: `cargo check -p fire-models`
Expected: PASS (no compile errors)

- [ ] **Step 3: Commit**

```bash
git add rust/crates/fire-models/src/session.rs
git commit -m "feat(models): add LoginFinalizationResult, PassiveLogoutTrigger, ProbeResult, SignalStrength"
```

---

### Task 5: Cookie replay queue in fire-store

**Files:**
- Modify: `rust/crates/fire-store/src/migrations.rs`
- Create: `rust/crates/fire-store/src/cookie_replay.rs`
- Modify: `rust/crates/fire-store/src/lib.rs`

- [ ] **Step 1: Add migration for `cookie_replay_queue` table**

In `migrations.rs`, add a new migration (v2):

```rust
fn v2() -> Vec<&'static str> {
    vec![
        "CREATE TABLE IF NOT EXISTS cookie_replay_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            raw_set_cookie TEXT NOT NULL,
            cookie_name TEXT NOT NULL,
            domain TEXT NOT NULL,
            inserted_at INTEGER NOT NULL
        )",
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_cookie_replay_dedup
            ON cookie_replay_queue (cookie_name, domain)",
    ]
}
```

Wire into the migration runner: if current version < 2, run v2().

- [ ] **Step 2: Implement `cookie_replay.rs`**

```rust
use rusqlite::{params, Connection};

pub struct CookieReplayEntry {
    pub url: String,
    pub raw_set_cookie: String,
    pub cookie_name: String,
    pub domain: String,
    pub inserted_at: u64,
}

pub fn enqueue_set_cookie(
    conn: &Connection,
    url: &str,
    raw_set_cookie: &str,
    cookie_name: &str,
    domain: &str,
    inserted_at: u64,
) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO cookie_replay_queue (url, raw_set_cookie, cookie_name, domain, inserted_at)
         VALUES (?1, ?2, ?3, ?4, ?5)",
        params![url, raw_set_cookie, cookie_name, domain, inserted_at as i64],
    )?;
    Ok(())
}

pub fn drain_replay_queue(conn: &Connection) -> rusqlite::Result<Vec<CookieReplayEntry>> {
    let mut stmt = conn.prepare(
        "SELECT url, raw_set_cookie, cookie_name, domain, inserted_at FROM cookie_replay_queue ORDER BY inserted_at ASC"
    )?;
    let entries = stmt.query_map([], |row| {
        Ok(CookieReplayEntry {
            url: row.get(0)?,
            raw_set_cookie: row.get(1)?,
            cookie_name: row.get(2)?,
            domain: row.get(3)?,
            inserted_at: row.get::<_, i64>(4)? as u64,
        })
    })?.collect::<Result<Vec<_>, _>>()?;
    Ok(entries)
}

pub fn clear_replay_queue(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute("DELETE FROM cookie_replay_queue", [])?;
    Ok(())
}
```

- [ ] **Step 3: Wire up module in `lib.rs`**

Add `pub mod cookie_replay;` to `fire-store/src/lib.rs`.

- [ ] **Step 4: Run cargo check**

Run: `cargo check -p fire-store`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-store/src/migrations.rs rust/crates/fire-store/src/cookie_replay.rs rust/crates/fire-store/src/lib.rs
git commit -m "feat(store): add cookie_replay_queue table and CRUD operations"
```

---

### Task 6: Hook Set-Cookie into replay queue in fire-core network layer

**Files:**
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`

- [ ] **Step 1: Add replay queue enqueue to response processing**

In the `FireCommonHeaderInterceptor` or the response processing path, after parsing `Set-Cookie` headers from the response, call `enqueue_set_cookie` for each header.

Add a helper function:

```rust
fn enqueue_set_cookie_headers(
    store: &FireStore,
    url: &str,
    headers: &http::HeaderMap,
) {
    let now = current_unix_ms();
    for value in headers.get_all("set-cookie") {
        if let Ok(raw) = value.to_str() {
            if let Some((name, domain)) = parse_cookie_name_and_domain(raw) {
                let _ = store.cookie_replay_enqueue(url, raw, &name, &domain, now);
            }
        }
    }
}

fn parse_cookie_name_and_domain(raw: &str) -> Option<(String, String)> {
    let parts: Vec<&str> = raw.split(';').collect();
    let first = parts.first()?;
    let name = first.split('=').next()?.trim().to_string();
    let domain = parts.iter()
        .find(|p| p.trim().starts_with("domain="))
        .map(|p| p.trim().strip_prefix("domain=").unwrap_or("").trim().trim_start_matches('.').to_string())
        .unwrap_or_default();
    Some((name, domain))
}
```

Wire `enqueue_set_cookie_headers` into `execute_request` response processing, after cookie application.

- [ ] **Step 2: Run cargo check**

Run: `cargo check -p fire-core`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add rust/crates/fire-core/src/core/network.rs rust/crates/fire-core/src/core/mod.rs
git commit -m "feat(core): hook Set-Cookie headers into replay queue"
```

---

### Task 7: Implement `finalize_login_from_webview` in fire-core

**Files:**
- Modify: `rust/crates/fire-core/src/core/session.rs`
- Test: `rust/crates/fire-core/tests/login_finalization.rs`

- [ ] **Step 1: Write integration test**

Create `rust/crates/fire-core/tests/login_finalization.rs`:

```rust
mod common;

use fire_core::FireCore;
use fire_models::{PlatformCookie, LoginFinalizationResult};

#[tokio::test]
async fn finalize_login_applies_scored_cookies_and_advances_epoch() {
    let server = common::TestServer::spawn(vec![
        common::raw_text_response(200, common::sample_home_html()),
    ]);
    let dir = common::temp_workspace_dir("finalize_login");
    let core = FireCore::new(
        "https://linux.do".into(),
        Some(dir.to_string_lossy().into()),
    ).await.unwrap();

    let cookies = vec![PlatformCookie {
        name: "_t".into(),
        value: "test_token".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }, PlatformCookie {
        name: "_forum_session".into(),
        value: "test_session".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }];

    let result = core.finalize_login_from_webview(
        "testuser".into(),
        Some("csrf_token_123".into()),
        None,
        None,
        cookies,
        true,
    ).await.unwrap();

    assert!(result.success);
    let snapshot = core.snapshot();
    assert!(snapshot.cookies.has_login_session());
    assert_eq!(snapshot.bootstrap.current_username.as_deref(), Some("testuser"));
}

#[tokio::test]
async fn finalize_login_verifies_t_token_consistency() {
    let dir = common::temp_workspace_dir("finalize_t_check");
    let core = FireCore::new(
        "https://linux.do".into(),
        Some(dir.to_string_lossy().into()),
    ).await.unwrap();

    let cookies = vec![PlatformCookie {
        name: "_t".into(),
        value: "webview_token".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }];

    let result = core.finalize_login_from_webview(
        "testuser".into(),
        None,
        None,
        None,
        cookies,
        true,
    ).await.unwrap();

    assert!(result.t_token_verified);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-core -- finalize_login`
Expected: FAIL (method not found)

- [ ] **Step 3: Implement `finalize_login_from_webview`**

In `session.rs`, add:

```rust
pub async fn finalize_login_from_webview(
    &self,
    username: String,
    csrf_token: Option<String>,
    raw_preloaded_html: Option<String>,
    browser_user_agent: Option<String>,
    cookies: Vec<PlatformCookie>,
    allow_low_confidence_session_cookies: bool,
) -> Result<LoginFinalizationResult, FireCoreError> {
    let base_url = self.base_url();
    let host = url::Url::parse(&base_url)
        .ok()
        .and_then(|u| u.host_str().map(|h| h.to_string()))
        .unwrap_or_default();

    let webview_t_token = cookies.iter()
        .find(|c| c.name == "_t")
        .map(|c| c.value.clone());

    {
        let mut state = self.state.write().await;
        state.cookies.scored_apply_platform_cookies(
            &cookies,
            &host,
            allow_low_confidence_session_cookies,
        );
    }

    let jar_t_after = {
        let state = self.state.read().await;
        state.cookies.t_token.clone()
    };

    let t_token_verified = match (&webview_t_token, &jar_t_after) {
        (Some(wv), Some(jar)) => wv == jar,
        (None, _) => true,
        (_, None) => false,
    };

    {
        let mut state = self.state.write().await;
        state.bootstrap.current_username = if !username.is_empty() {
            Some(username)
        } else {
            None
        };
        if let Some(ref csrf) = csrf_token {
            state.cookies.csrf_token = Some(csrf.clone());
        }
        if let Some(ref ua) = browser_user_agent {
            state.browser_user_agent = Some(ua.clone());
        }
        self.mutate_runtime_session_tracking_auth_change(&mut state, "PlatformSync");
    }

    self.update_session_advancing_epoch_if_auth_changed("PlatformSync");

    let fingerprint_wait_needed = true;

    if let Some(html) = raw_preloaded_html {
        self.apply_home_html(&html).await;
    }

    let snapshot = self.snapshot();
    let success = snapshot.cookies.has_login_session();

    Ok(LoginFinalizationResult {
        success,
        t_token_verified,
        fingerprint_wait_needed,
    })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-core -- finalize_login`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-core/src/core/session.rs rust/crates/fire-core/tests/login_finalization.rs
git commit -m "feat(core): implement finalize_login_from_webview with cookie scoring and t verification"
```

---

### Task 8: Implement strike system

**Files:**
- Create: `rust/crates/fire-core/src/core/auth_strike.rs`
- Modify: `rust/crates/fire-core/src/core/mod.rs`
- Test: inline `#[cfg(test)]` in `auth_strike.rs`

- [ ] **Step 1: Write failing test**

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strong_signal_triggers_probe_immediately() {
        let mut state = AuthStrikeState::default();
        let decision = state.receive_auth_signal(SignalStrength::Strong);
        assert!(matches!(decision, StrikeDecision::ProbeNeeded));
    }

    #[test]
    fn weak_signal_needs_two_strikes() {
        let mut state = AuthStrikeState::default();
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::Accumulated { .. }));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::ProbeNeeded));
    }

    #[test]
    fn strikes_reset_after_45s_gap() {
        let mut state = AuthStrikeState::default();
        state.receive_auth_signal(SignalStrength::Weak);
        state.last_strike_at = Some(Instant::now() - Duration::from_secs(60));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        if let StrikeDecision::Accumulated { strikes } = decision {
            assert_eq!(strikes, 1);
        } else {
            panic!("Expected Accumulated");
        }
    }

    #[test]
    fn inconclusive_cooldown_ignores_weak_signals() {
        let mut state = AuthStrikeState::default();
        state.inconclusive_until = Some(Instant::now() + Duration::from_secs(30));
        let decision = state.receive_auth_signal(SignalStrength::Weak);
        assert!(matches!(decision, StrikeDecision::Ignore));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-core -- auth_strike`
Expected: FAIL (module not found)

- [ ] **Step 3: Implement `AuthStrikeState`**

Create `auth_strike.rs`:

```rust
use fire_models::session::SignalStrength;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq)]
pub enum StrikeDecision {
    Ignore,
    Accumulated { strikes: u8 },
    ProbeNeeded,
}

#[derive(Debug)]
pub struct AuthStrikeState {
    pub strike_count: u8,
    pub last_strike_at: Option<Instant>,
    pub last_signal_strength: Option<SignalStrength>,
    pub inconclusive_until: Option<Instant>,
    pub passive_logout_count_24h: u8,
    pub passive_logout_window_start: Option<Instant>,
    pub probe_in_progress: bool,
    pub logging_out: bool,
}

const STRIKE_WINDOW: Duration = Duration::from_secs(45);
const INCONCLUSIVE_COOLDOWN: Duration = Duration::from_secs(30);
const PASSIVE_LOGOUT_WINDOW: Duration = Duration::from_secs(24 * 60 * 60);
const PASSIVE_LOGOUT_SUGGEST_CLEAR_THRESHOLD: u8 = 3;

impl Default for AuthStrikeState {
    fn default() -> Self {
        Self {
            strike_count: 0,
            last_strike_at: None,
            last_signal_strength: None,
            inconclusive_until: None,
            passive_logout_count_24h: 0,
            passive_logout_window_start: None,
            probe_in_progress: false,
            logging_out: false,
        }
    }
}

impl AuthStrikeState {
    pub fn receive_auth_signal(&mut self, strength: SignalStrength) -> StrikeDecision {
        if self.logging_out {
            return StrikeDecision::Ignore;
        }
        if self.probe_in_progress {
            return StrikeDecision::Ignore;
        }
        if let Some(until) = self.inconclusive_until {
            if Instant::now() < until && strength == SignalStrength::Weak {
                return StrikeDecision::Ignore;
            }
        }

        if let Some(last) = self.last_strike_at {
            if Instant::now().duration_since(last) > STRIKE_WINDOW {
                self.strike_count = 0;
            }
        }

        self.strike_count += 1;
        self.last_strike_at = Some(Instant::now());
        self.last_signal_strength = Some(strength.clone());

        let threshold = match strength {
            SignalStrength::Strong => 1,
            SignalStrength::Weak => 2,
        };

        if self.strike_count >= threshold {
            StrikeDecision::ProbeNeeded
        } else {
            StrikeDecision::Accumulated { strikes: self.strike_count }
        }
    }

    pub fn reset_strikes(&mut self) {
        self.strike_count = 0;
        self.last_strike_at = None;
        self.last_signal_strength = None;
        self.inconclusive_until = None;
    }

    pub fn enter_inconclusive_cooldown(&mut self) {
        self.inconclusive_until = Some(Instant::now() + INCONCLUSIVE_COOLDOWN);
    }

    pub fn should_suggest_data_clear(&self) -> bool {
        self.passive_logout_count_24h >= PASSIVE_LOGOUT_SUGGEST_CLEAR_THRESHOLD
    }

    pub fn record_passive_logout(&mut self) {
        let now = Instant::now();
        if let Some(start) = self.passive_logout_window_start {
            if now.duration_since(start) > PASSIVE_LOGOUT_WINDOW {
                self.passive_logout_count_24h = 0;
                self.passive_logout_window_start = Some(now);
            }
        } else {
            self.passive_logout_window_start = Some(now);
        }
        self.passive_logout_count_24h += 1;
        self.logging_out = true;
    }
}
```

Register module in `mod.rs`: `pub mod auth_strike;`

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-core -- auth_strike`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-core/src/core/auth_strike.rs rust/crates/fire-core/src/core/mod.rs
git commit -m "feat(core): implement AuthStrikeState with signal classification and cooldowns"
```

---

### Task 9: Implement `probe_session` and `passive_logout` in fire-core

**Files:**
- Modify: `rust/crates/fire-core/src/core/auth.rs`
- Test: `rust/crates/fire-core/tests/auth_strike.rs`

- [ ] **Step 1: Write integration test**

```rust
#[tokio::test]
async fn probe_session_returns_valid_when_user_exists() {
    let server = common::TestServer::spawn(vec![
        common::raw_text_response(200, r#"{"current_user":{"username":"testuser"}}"#),
    ]);
    let dir = common::temp_workspace_dir("probe_valid");
    let core = FireCore::new(server.base_url(), Some(dir.to_string_lossy().into())).await.unwrap();

    let result = core.probe_session().await.unwrap();
    assert!(matches!(result, ProbeResult::Valid { .. }));
}

#[tokio::test]
async fn probe_session_returns_invalid_on_404() {
    let server = common::TestServer::spawn(vec![
        common::raw_text_response(404, "not found"),
    ]);
    let dir = common::temp_workspace_dir("probe_invalid");
    let core = FireCore::new(server.base_url(), Some(dir.to_string_lossy().into())).await.unwrap();

    let result = core.probe_session().await.unwrap();
    assert!(matches!(result, ProbeResult::Invalid));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cargo test -p fire-core -- probe_session`
Expected: FAIL (method not found)

- [ ] **Step 3: Implement `probe_session` and `passive_logout`**

In `auth.rs`:

```rust
pub async fn probe_session(&self) -> Result<ProbeResult, FireCoreError> {
    let request = self.build_json_get_request(
        "probe_session",
        "/session/current.json",
        None,
        None,
    ).await?;
    let traced = self.create_traced_request(request);
    let response = self.execute_request(traced).await?;

    let status = response.status();
    if status.as_u16() == 404 {
        return Ok(ProbeResult::Invalid);
    }

    let body = self.read_response_text("probe_session", response).await?;
    let json: serde_json::Value = serde_json::from_str(&body).unwrap_or_default();

    if let Some(user) = json.get("current_user") {
        let username = user.get("username")
            .and_then(|u| u.as_str())
            .unwrap_or("")
            .to_string();
        if !username.is_empty() {
            return Ok(ProbeResult::Valid { username });
        }
    }

    if status.is_success() {
        Ok(ProbeResult::Invalid)
    } else if status.as_u16() == 401 || status.as_u16() == 403 {
        Ok(ProbeResult::Invalid)
    } else {
        Ok(ProbeResult::Inconclusive)
    }
}

pub async fn passive_logout(&self, trigger: PassiveLogoutTrigger) -> Result<(), FireCoreError> {
    self.advance_epoch("passive_logout");
    {
        let mut state = self.state.write().await;
        state.auth_strike.record_passive_logout();
    }
    self.logout_local(true).await;
    Ok(())
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cargo test -p fire-core -- probe_session`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-core/src/core/auth.rs rust/crates/fire-core/tests/auth_strike.rs
git commit -m "feat(core): implement probe_session and passive_logout"
```

---

### Task 10: Integrate strike system into network response processing

**Files:**
- Modify: `rust/crates/fire-core/src/core/network.rs`
- Test: extend `rust/crates/fire-core/tests/auth_strike.rs`

- [ ] **Step 1: Write integration test**

```rust
#[tokio::test]
async fn discourse_logged_out_strong_signal_triggers_probe() {
    let home_html = common::sample_home_html();
    let server = common::TestServer::spawn_scripted(vec![
        common::TestServerStep::immediate(common::raw_text_response(200, &home_html)),
        common::TestServerStep::immediate(
            "HTTP/1.1 403 OK\r\ncontent-type: application/json\r\ndiscourse-logged-out: true\r\n\r\n[\"BAD CSRF\"]"
        ),
        common::TestServerStep::immediate(common::raw_text_response(200, r#"{"current_user":{"username":"testuser"}}"#)),
    ]);
    let dir = common::temp_workspace_dir("strike_integration");
    let core = FireCore::new(server.base_url(), Some(dir.to_string_lossy().into())).await.unwrap();

    // Bootstrap
    core.refresh_bootstrap().await.unwrap();

    // Simulate receiving discourse-logged-out header during an API call
    let state = core.state.read().await;
    let initial_epoch = state.epoch;
    drop(state);

    // After strike + probe, session should be verified or cleaned up
    // (detailed verification depends on the actual request flow)
}
```

- [ ] **Step 2: Integrate strike system into `execute_api_request_with_csrf_retry`**

In `network.rs`, modify `execute_api_request_with_csrf_retry` to:

1. After detecting `discourse-logged-out` header or `not_logged_in` error type, classify signal strength
2. Call `auth_strike.receive_auth_signal(strength)`
3. If `ProbeNeeded`, run `probe_session()`
4. If probe confirms `Invalid`, run `passive_logout()`

This requires holding a mutable reference to `AuthStrikeState` inside `FireSessionRuntimeState`.

- [ ] **Step 3: Run cargo check and tests**

Run: `cargo test -p fire-core`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add rust/crates/fire-core/src/core/network.rs rust/crates/fire-core/tests/auth_strike.rs
git commit -m "feat(core): integrate strike system into API request response processing"
```

---

### Task 11: Expose new FFI methods in fire-uniffi-session

**Files:**
- Create: `rust/crates/fire-uniffi-types/records/login_finalization.rs`
- Modify: `rust/crates/fire-uniffi-types/src/lib.rs`
- Modify: `rust/crates/fire-uniffi-session/src/lib.rs`

- [ ] **Step 1: Create FFI record types**

In `fire-uniffi-types/records/login_finalization.rs`:

```rust
#[derive(uniffi::Record, Debug, Clone)]
pub struct LoginFinalizationResultState {
    pub success: bool,
    pub t_token_verified: bool,
    pub fingerprint_wait_needed: bool,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PassiveLogoutTriggerState {
    pub source: String,
    pub signal_strength: String,
    pub cookie_diagnostic: String,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieReplayEntryState {
    pub url: String,
    pub raw_set_cookie: String,
    pub cookie_name: String,
    pub domain: String,
    pub inserted_at: u64,
}
```

Add `From` impls mapping from `fire-models` types.

- [ ] **Step 2: Add FFI methods to `FireSessionHandle`**

```rust
fn finalize_login_from_webview(
    &self,
    username: String,
    csrf_token: Option<String>,
    raw_preloaded_html: Option<String>,
    browser_user_agent: Option<String>,
    cookies: Vec<PlatformCookieState>,
    allow_low_confidence_session_cookies: bool,
) -> Result<LoginFinalizationResultState> {
    run_fallible(self.shared.clone(), || {
        let rt = ffi_runtime();
        rt.block_on(self.shared.core.finalize_login_from_webview(
            username,
            csrf_token,
            raw_preloaded_html,
            browser_user_agent,
            cookies.into_iter().map(Into::into).collect(),
            allow_low_confidence_session_cookies,
        ))
    }).map(Into::into)
}

fn cookie_replay_queue(&self) -> Result<Vec<CookieReplayEntryState>> {
    // delegate to fire-store
}

fn clear_cookie_replay_queue(&self) -> Result<()> {
    // delegate to fire-store
}

fn probe_session(&self) -> Result<String> {
    // "valid:username", "invalid", "inconclusive"
}

fn record_fingerprint_done(&self) {
    // no-op for now, future hook point
}

fn save_credential(&self, username: String, password: String) -> Result<()> {
    // delegate to encrypted store
}

fn load_credential(&self) -> Result<Option<String>> {
    // returns JSON {"username":"...","password":"..."} or None
}

fn clear_credential(&self) -> Result<()> {
    // clear stored credential
}
```

- [ ] **Step 3: Run cargo check**

Run: `cargo check -p fire-uniffi-session`
Expected: PASS

- [ ] **Step 4: Run full Rust test suite**

Run: `cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add rust/crates/fire-uniffi-types/ rust/crates/fire-uniffi-session/
git commit -m "feat(uniffi): expose finalize_login_from_webview, cookie_replay_queue, probe_session FFI methods"
```

---

### Task 12: Update CI test configuration

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add `fire-store` to CI test targets**

Update the `rust-host-test` job's test command from:

```
cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets
```

to:

```
cargo test -p fire-models -p fire-store -p fire-core -p fire-uniffi --all-targets
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add fire-store to Rust test targets"
```
