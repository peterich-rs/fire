# Fix iOS Auth Cookie Invalidation

## Feasibility Assessment

This change is fully achievable inside the current Fire architecture. The false-positive logout behavior is controlled by a small shared Rust surface: `rust/crates/fire-core/src/cookies.rs` decides whether network `Set-Cookie` headers mutate the session snapshot, and `rust/crates/fire-core/src/core/network.rs` decides whether a response should become `LoginRequired`. The existing strong signals (`discourse-logged-out` and `error_type: "not_logged_in"`) already exist and remain valid, while the stale-response epoch guard already protects the separate in-flight race. No platform API changes or new dependencies are required. Fully feasible.

## Current Surface Inventory

- `rust/crates/fire-core/src/cookies.rs::FireSessionCookieJar::set_cookies` -- applies network `Set-Cookie` batches into the in-memory session snapshot.
- `rust/crates/fire-core/src/core/network.rs::LoginInvalidationSignal` -- carries per-response login invalidation evidence.
- `rust/crates/fire-core/src/core/network.rs::response_login_invalidation_signal` -- extracts `discourse-logged-out` and auth-cookie deletion hints from response headers.
- `rust/crates/fire-core/src/core/network.rs::expect_success` -- converts successful responses into `LoginRequired` when the invalidation classifier says the response is authoritative.
- `rust/crates/fire-core/src/core/network.rs::response_login_invalidation_error` -- performs local logout while preserving `cf_clearance`.
- `rust/crates/fire-core/tests/network.rs` -- end-to-end coverage for successful invalidation, `not_logged_in`, and stale-response session races.
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

## Architectural Notes

- Semver impact: none; all changes are internal to `fire-core` behavior.
- Cross-crate dependencies: none added or removed.
- Side effects: auth-cookie delete headers are still visible in diagnostics, but they no longer clear local state or trigger `LoginRequired` by themselves.
- Explicitly not changed: iOS `cf_clearance` auto-refresh, `WKHTTPCookieStoreObserver` debounce timing, platform-side logout de-duplication, and stale-response epoch invalidation.
- The host can still clear auth state by supplying a full replacement platform-cookie batch through `apply_platform_cookies`; this fix only changes network `Set-Cookie` handling.

## File Change Summary

- `docs/architecture/ios-auth-alignment-plan.md` -- annotate the earlier auth-alignment plan with the current-response auth-cookie invalidation follow-up.
- `docs/architecture/ios-auth-cookie-invalidation-fix.md` -- capture the verified design and phased implementation for the false-positive login invalidation fix.
- `rust/crates/fire-core/src/core/network.rs` -- keep auth-cookie deletion signals for diagnostics while limiting strong invalidation to explicit server logout evidence.
- `rust/crates/fire-core/src/cookies.rs` -- ignore network `_t` and `_forum_session` delete directives until a stronger invalidation path clears local auth state.
- `rust/crates/fire-core/tests/network.rs` -- add an end-to-end regression test for successful responses that only clear auth cookies.
