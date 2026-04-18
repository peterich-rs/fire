# Fix iOS Auth Cookie Invalidation

This document only covers the false-positive logout path caused by non-authoritative auth-cookie deletion signals. The later support snapshot that showed a successful response rotating `_forum_session` before `/topics/timings` is tracked separately in `docs/architecture/ios-auth-cookie-rotation-recovery-plan.md`.

## Feasibility Assessment

This change is fully achievable inside the current Fire architecture. The false-positive logout behavior is controlled by a small shared Rust surface: `rust/crates/fire-core/src/cookies.rs` decides whether network `Set-Cookie` headers mutate the session snapshot, and `rust/crates/fire-core/src/core/network.rs` decides whether a response should become `LoginRequired`. The existing strong signals (`discourse-logged-out` and `error_type: "not_logged_in"`) already exist and remain valid, while the stale-response epoch guard already protects the separate in-flight race. No platform API changes or new dependencies are required. Fully feasible.

## Current Surface Inventory

- `rust/crates/fire-core/src/cookies.rs::FireSessionCookieJar::set_cookies` -- applies network `Set-Cookie` batches into the in-memory session snapshot.
- `rust/crates/fire-core/src/core/network.rs::LoginInvalidationSignal` -- carries per-response login invalidation evidence.
- `rust/crates/fire-core/src/core/network.rs::response_login_invalidation_signal` -- extracts `discourse-logged-out` and auth-cookie deletion hints from response headers.
- `rust/crates/fire-core/src/core/network.rs::expect_success` -- converts successful responses into `LoginRequired` when the invalidation classifier says the response is authoritative.
- `rust/crates/fire-core/src/core/network.rs::response_login_invalidation_error` -- performs local logout while preserving `cf_clearance`.
- `rust/crates/fire-core/tests/network.rs` -- end-to-end coverage for successful invalidation, `not_logged_in`, and stale-response session races.
- `native/ios-app/App/FireAppViewModel.swift` -- owns `LoginRequired` handling, login presentation, session application, and the host-side cookie mirroring path.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- owns background `cf_clearance` maintenance and the offscreen WebKit runtime that keeps Cloudflare clearance warm.
- `docs/architecture/ios-auth-alignment-plan.md` -- prior architecture plan that documents the stale-response guard and now needs a follow-up note for the current-response auth-cookie fix.

## Design

### Key design decisions

1. Treat network `_t` and `_forum_session` deletions as non-authoritative until a stronger invalidation signal arrives.
   Rejected alternative: continue applying the delete to the session snapshot immediately and rely on later recovery. That leaves a race where `expect_success` sees an already-cleared session and either produces a false `LoginRequired` or skips the intended `logout_local(true)` cleanup path.

2. Keep auth-cookie deletion detection as diagnostic metadata, but stop using it as a standalone logout trigger.
   Rejected alternative: delete the cleared-cookie fields entirely. Keeping them preserves traceability in warnings without letting them drive control flow.

3. Preserve `discourse-logged-out` and `not_logged_in` as the only strong invalidation signals for this fix.
   Rejected alternative: redesign Cloudflare refresh, WebView cookie probing, or host-side logout serialization in the same patch. Those are separate concerns and would dilute the P0 fix.

4. Leave the session epoch guard unchanged.
   Rejected alternative: repurpose the epoch guard to solve current-response auth-cookie deletion. The epoch guard only covers stale in-flight responses after the session epoch changes; it does not protect the active response being classified right now.

### Target behavior

- A `200` response that only sends `Set-Cookie: _t=; Max-Age=0` or `Set-Cookie: _forum_session=; Max-Age=0` does not clear local login state and does not become `LoginRequired` on its own.
- A response with `discourse-logged-out` still forces `logout_local(true)` and returns `LoginRequired`.
- A `401` or `403` response whose body parses as `error_type: "not_logged_in"` still forces `logout_local(true)` and returns `LoginRequired`.
- Multiple concurrent `LoginRequired` errors only clear/present the native login flow once on iOS.
- Background `cf_clearance` refresh on iOS actively solves Turnstile refreshes by replaying `/cdn-cgi/challenge-platform/.../rc/...` through native networking instead of passively reloading the forum homepage.
- A successful background Cloudflare refresh flows back through `FireAppViewModel.applySession`, so the refreshed cookie batch is mirrored back into `HTTPCookieStorage` and the shared `WKHTTPCookieStore`.
- `cf_clearance` preservation and stale-response epoch invalidation remain unchanged.

## Phased Implementation

## Phase 1: Ignore non-authoritative network auth-cookie deletions

**File: `rust/crates/fire-core/src/cookies.rs`**

- Add a small helper that identifies network `_t` and `_forum_session` deletes after `parse_set_cookie` normalizes them to an empty string.
- Skip writing those delete cookies into `CookieSnapshot` and `platform_cookies` inside `FireSessionCookieJar::set_cookies`.
- Keep normal auth-cookie updates and all `cf_clearance` mutations untouched.
- Rationale: the shared session snapshot should only lose auth cookies when the server also emits a strong invalidation signal or when the host supplies a full replacement cookie set.

## Phase 2: Downgrade cleared auth cookies to diagnostics in the invalidation classifier

**File: `rust/crates/fire-core/src/core/network.rs`**

- Keep parsing `Set-Cookie` deletes into `cleared_t_cookie` and `cleared_forum_session` so warning logs still show what happened on the wire.
- Change `LoginInvalidationSignal::any()` so only `discourse_logged_out` is authoritative for success-response invalidation.
- Leave `response_login_invalidation_error` unchanged aside from relying on the updated `any()` behavior, so `not_logged_in_message()` still forces logout on `401` and `403`.
- Rationale: this preserves observability while aligning behavior with Fluxdo's stronger business-layer logout criteria.

## Phase 3: Add focused regression coverage

**File: `rust/crates/fire-core/tests/network.rs`**

- Add an end-to-end regression test that logs in, receives a successful `200` response whose only auth-related effect is deleting `_t` and `_forum_session`, and asserts that:
  - the request succeeds,
  - auth cookies remain present,
  - `csrf_token`, `cf_clearance`, and bootstrap identity stay intact.
- Keep the existing successful `discourse-logged-out` test and `not_logged_in` test as the preserved strong-signal coverage.
- Rationale: the regression is only fixed when both the cookie write path and the invalidation classifier change together.

## Phase 4: Sync architecture documentation

**File: `docs/architecture/ios-auth-alignment-plan.md`**

- Amend the stale-response phase note so it no longer implies that auth-cookie deletes should never be special-cased.
- Point readers at this follow-up document for the current-response false-positive logout fix.

**File: `docs/architecture/ios-auth-cookie-invalidation-fix.md`**

- Record the verified root cause, the narrowed implementation scope, and the validation plan for future readers.

## Phase 5: Verification

**File: `rust/crates/fire-core/tests/network.rs`**

- Run `cargo test -p fire-core fetch_topic_list_keeps_local_login_when_success_response_only_clears_auth_cookies -- --nocapture`.
- Run `cargo test -p fire-core fetch_topic_list_surfaces_login_required -- --nocapture`.
- Keep stale-response tests unchanged because this patch must not alter epoch behavior.

## Follow-up Host Fixes On The Same Worktree

## Phase 6: Deduplicate native login reset presentation

**File: `native/ios-app/App/FireAppViewModel.swift`**

- Add an `isResettingSession` guard around `resetSessionAndPresentLogin(message:)`.
- Keep the implementation on `@MainActor` so concurrent `LoginRequired` surfaces serialize naturally without extra locks.
- Rationale: Rust already avoids duplicate `logout_local(true)` side effects once the first logout clears auth cookies; the remaining duplicate behavior lives in Swift UI reset/presentation.

## Phase 7: Replace passive Cloudflare refresh with Turnstile rc replay

**File: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`**

- Replace the timer-driven homepage reload loop with a long-lived offscreen `WKWebView` that hosts a Turnstile widget configured with `refresh-expired: 'auto'`.
- Inject a `fetch` interceptor before `api.js` loads, capture `/cdn-cgi/challenge-platform/.../rc/...` calls, replay them through native `URLSession`, and return the real response to JavaScript through `window._resolveRc(...)`.
- Keep the existing scene-active and interactive-recovery gating, and add runtime generation tokens, first-intercept timeout handling, and bounded retry/failure tracking so stale callbacks and repeated failures self-quiesce.

## Phase 8: Push refreshed sessions back through the host cookie mirror

**Files: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`, `native/ios-app/App/FireAppViewModel.swift`**

- After a successful rc replay, call `loginCoordinator.refreshPlatformCookies()` to pull the refreshed cookie batch into Rust.
- Feed that refreshed `SessionState` back into `FireAppViewModel.applySession` through a service callback.
- Rationale: the WebKit cookie store is only fully reconciled when `applySession` runs and re-mirrors the updated platform cookie batch into host-owned storage.

## Architectural Notes

- Semver impact: none; all changes are internal to `fire-core` behavior.
- Cross-crate dependencies: none added or removed.
- Side effects: auth-cookie delete headers are still visible in diagnostics, but they no longer clear local state or trigger `LoginRequired` by themselves.
- Host follow-ups now implemented on the same worktree: iOS `LoginRequired` presentation deduplication, Turnstile-driven `cf_clearance` auto-refresh, and host-side reapplication of refreshed cookie batches.
- Explicitly still not changed: `WKHTTPCookieStoreObserver` debounce timing and stale-response epoch invalidation.
- The host can still clear auth state by supplying a full replacement platform-cookie batch through `apply_platform_cookies`; this fix only changes network `Set-Cookie` handling.

## File Change Summary

- `docs/architecture/ios-auth-alignment-plan.md` -- annotate the earlier auth-alignment plan with the current-response auth-cookie invalidation follow-up.
- `docs/architecture/ios-auth-cookie-invalidation-fix.md` -- capture the verified design, the Rust-side fix, and the follow-up iOS host remediation that landed on the same worktree.
- `docs/backend-api/03-bootstrap-and-site.md` -- document that Fire iOS now replays Cloudflare's internal `rc` refresh flow from an offscreen WebView runtime.
- `native/ios-app/README.md` -- document the Turnstile-based offscreen refresh runtime and the apply-session callback used to mirror refreshed cookies back into native storage.
- `native/ios-app/App/FireAppViewModel.swift` -- deduplicate concurrent login reset presentation and reapply refreshed Cloudflare sessions through the existing session mirror path.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- replace the passive homepage reload loop with the Turnstile rc interception runtime.
- `rust/crates/fire-core/src/core/network.rs` -- keep auth-cookie deletion signals for diagnostics while limiting strong invalidation to explicit server logout evidence.
- `rust/crates/fire-core/src/cookies.rs` -- ignore network `_t` and `_forum_session` delete directives until a stronger invalidation path clears local auth state.
- `rust/crates/fire-core/tests/network.rs` -- add an end-to-end regression test for successful responses that only clear auth cookies.
