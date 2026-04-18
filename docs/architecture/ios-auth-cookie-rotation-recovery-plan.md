# Repair Partial Auth Rotation Before Timings Writes

## Feasibility Assessment

This follow-up is fully achievable inside the current Fire architecture. The required changes stay inside the shared Rust session boundary plus an optional iOS cookie resync hook that already exists. No backend contract change is required, and the existing strong invalidation behavior for `discourse-logged-out` and `error_type: "not_logged_in"` should remain intact.

This document is a follow-up to `docs/architecture/ios-auth-cookie-invalidation-fix.md`. That earlier fix narrowed false-positive logout on explicit auth-cookie deletion. The incident analyzed here is different: a successful authenticated read rotated part of the auth context, and the shared layer continued using stale write credentials afterward.

## Incident Summary

- Support snapshot evidence shows `call 231` (`GET /t/1992131.json?track_visit=true`) succeeding with the old `_forum_session` and old `_t`.
- The same response returns `Set-Cookie: _forum_session=...` without a new `_t` and without a new CSRF token.
- `FireSessionCookieJar::set_cookies` merges that `_forum_session` change directly into the in-memory session snapshot.
- `CookieSnapshot::merge_patch` preserves the old `_t` and existing `csrf_token` because the response did not replace them.
- `call 236` (`POST /topics/timings`) is then sent with the rotated `_forum_session`, the old `_t`, and the old `X-CSRF-Token`.
- The server answers `403 invalid_access`, returns `Discourse-Logged-Out: 1`, clears `_t`, and Fire performs a strong local logout.
- The topic detail page reset is downstream of that logout path. It is not the primary defect.

## Current Verified Gap

### What already works

- Explicit platform cookie application already advances the shared session epoch when `_t` or `_forum_session` changes.
- Strong invalidation still only comes from explicit server evidence such as `discourse-logged-out` or `error_type: "not_logged_in"`.
- Write requests already refresh CSRF when no token exists, and retry once when the server returns `BAD CSRF`.

### What is still missing

1. Network `Set-Cookie` auth changes do not advance the shared session epoch.
   `FireSessionCookieJar::set_cookies` writes directly into the session snapshot instead of using the epoch-aware auth-change path used by `apply_platform_cookies` and `merge_platform_cookies`.

2. Auth cookie rotation does not invalidate CSRF.
   If `_forum_session` or `_t` changes, the existing `csrf_token` stays in memory unless the host explicitly replaces it or the server later returns `BAD CSRF`.

3. Session readiness only checks presence, not auth-generation consistency.
   `SessionSnapshot::readiness()` treats the session as readable when both auth cookies exist, and writable when CSRF also exists. It does not know whether those values still belong to the same auth generation.

4. Partial auth rotation is treated as a normal steady state.
   A response that rotates only `_forum_session` is accepted as an ordinary incremental cookie update, even though the next write may require a refreshed CSRF token or a fuller cookie resync.

5. The host has no bounded recovery hook for the remaining cross-runtime divergence.
   `FireWebViewLoginCoordinator.refreshPlatformCookies()` already exists, but there is no `FireSessionStore`-owned write preflight that can use it once per auth generation without introducing loops.

## Design Goals

1. Treat `_t` and `_forum_session` changes as an auth-context rotation, not as a normal cookie patch.
2. Never reuse a CSRF token across auth rotation unless the same mutation also provided a fresh replacement token.
3. Keep strong logout driven only by explicit server invalidation, not by the rotation itself.
4. Prevent the first authenticated write after rotation from reusing a stale write context.
5. Keep the first repair phase inside `fire-core` unless runtime evidence proves iOS platform-cookie resync must be pulled earlier.

## Non-Goals

- Reworking topic detail store ownership or view fallback behavior.
- Broadening login invalidation semantics beyond the current strong signals.
- Assuming the backend is wrong before client-side auth rotation handling is made coherent.
- Adding new platform services or dependencies.

## Design

### Key design decisions

1. Centralize auth-rotation handling instead of patching individual call sites.
   Rejected alternative: add one-off `clear_csrf_token()` calls around `/topics/timings` or other write APIs.
   Reason: the defect is caused by shared auth state becoming internally inconsistent. The fix belongs where auth cookies mutate.

2. Clear CSRF when auth changed and the mutation did not also install a fresh CSRF token.
   Rejected alternative: always clear CSRF on any cookie mutation.
   Reason: browser-context cookie churn should not force unnecessary CSRF refresh, and login sync may already provide a fresh token in the same transaction.

3. Advance the session epoch on network auth rotation just like host-driven auth rotation.
   Rejected alternative: keep epoch advancement exclusive to explicit host sync.
   Reason: once auth cookies change, stale in-flight responses should no longer be allowed to update the current auth generation.

4. Treat partial network auth rotation as suspicious but not immediately fatal.
   Rejected alternative: force logout whenever only one auth cookie changes.
   Reason: the current evidence proves the shared state is not safe for writes, but it does not yet prove that the server always considers the session irrecoverable at that moment.

5. Keep host resync as a delayed write-preflight fallback owned by `FireSessionStore`.
   Rejected alternative: trigger `refreshPlatformCookies()` immediately from the read response that observed partial rotation, or drive the flow from `FireAppViewModel`.
   Reason: read traffic should not be coupled to WebKit cookie reads, and the owner of session persistence and authenticated write orchestration already lives in `FireSessionStore`.

### Target behavior

- If `_t` or `_forum_session` changes through any session mutation path, the shared session epoch advances.
- If auth changed and the same mutation did not also provide a different CSRF token, the stored CSRF token is cleared.
- The successful response that triggered the auth rotation still completes with its payload; only other responses that are now behind the newer auth epoch are discarded as stale.
- The next authenticated write re-establishes CSRF before sending the write request body.
- If that CSRF refresh or subsequent write returns `discourse-logged-out` or `not_logged_in`, Fire preserves the current strong logout behavior.
- Partial auth rotation produces dedicated diagnostics so support snapshots can distinguish it from cookie-deletion invalidation and ordinary login expiry.

### Host resync strategy

- Rust should record a runtime-only auth recovery hint when a network cookie batch changes only one side of the auth key. This hint belongs in `FireSessionRuntimeState`, not in persisted `SessionSnapshot`.
- The hint should include at least the observed auth epoch and a small reason enum such as `forum_session_only_rotation` or `t_only_rotation`.
- `FireSessionStore` should own one authenticated-write preflight helper instead of special-casing `/topics/timings`.
- The preflight order should be:
   1. read the current auth recovery hint,
   2. call shared `refreshCsrfTokenIfNeeded()`,
   3. if the hint cleared or the auth epoch changed, continue normally,
   4. if the same epoch still carries the hint and a host cookie-source provider is available, read one platform-cookie batch for that epoch,
   5. apply that cookie batch through `sessionStore.applyPlatformCookies(...)`,
   6. rerun `refreshCsrfTokenIfNeeded()`, then continue the original write.
- SessionStore should swallow host resync provider failures for that epoch and continue the original write so explicit `LoginRequired` / strong invalidation still comes from the shared request path instead of from WebKit sync errors.
- Host cookie reads should never be triggered from read paths and should never run after a strong invalidation signal has already been produced.
- `FireWebViewLoginCoordinator` should remain a provider of platform cookies, not the policy owner of when auth recovery happens.
- `FireAppViewModel` should only wire the provider and continue handling final `LoginRequired` outcomes.
- The host fallback should be protected by two gates:
   - one resync attempt per auth epoch,
   - a single-flight task inside `FireSessionStore` so concurrent writes await the same resync instead of starting parallel WebKit reads.
- If a resync task completes after the auth epoch has already advanced again, its result should be dropped.
- If a resync task fails or produces no state change, mark that epoch as already attempted and fall back to the current shared error path instead of retrying in a loop.

## Phased Implementation

## Phase 1: Add regression coverage for the observed chain

**Files:** `rust/crates/fire-core/tests/network.rs`, `rust/crates/fire-core/tests/interactions.rs`

- Add a regression that models a successful authenticated response which rotates `_forum_session` without replacing `_t`.
- Assert that the session no longer retains the previous CSRF token after the auth rotation.
- Assert that the next authenticated write reacquires CSRF before sending `/topics/timings`.
- Preserve the existing strong invalidation tests for `discourse-logged-out` and `not_logged_in`.

Rationale: this locks the incident into executable coverage before the shared auth mutation path is refactored.

## Phase 2: Introduce one epoch-aware auth-change helper

**Files:** `rust/crates/fire-core/src/core/mod.rs`, `rust/crates/fire-core/src/core/session.rs`

- Introduce a shared helper for cookie/session mutations that compares the auth key before and after mutation.
- Define the auth key as the pair `(_t, _forum_session)`.
- If the auth key changes:
  - advance the shared session epoch,
  - clear `csrf_token` if the post-mutation CSRF token is identical to the pre-mutation token,
   - emit a reason-specific diagnostic,
   - update a runtime-only auth recovery hint when the change is partial rather than symmetric.
- Expose the current auth epoch and runtime-only auth recovery hint through the shared session handle so later host resync work can query them without persisting them.
- Clear that runtime-only hint after a successful CSRF refresh, after a host-driven cookie apply stabilizes the auth key, or after logout completes.
- Reuse this helper from platform-cookie merge/apply paths so host-driven and network-driven auth changes share one rule.

Rationale: the current split behavior is the root structural problem. Auth rotation must be interpreted the same way regardless of where the cookie update originated.

## Phase 3: Route network cookie ingress through the auth-change helper

**File:** `rust/crates/fire-core/src/cookies.rs`

- Stop mutating `session.snapshot.cookies` directly from `FireSessionCookieJar::set_cookies`.
- Build the same cookie patch as today, but apply it through the epoch-aware auth-change helper.
- Keep the existing guard that ignores non-authoritative network auth-cookie deletion.
- Add a dedicated diagnostic when only one auth cookie changed in the current batch, and set the runtime-only auth recovery hint for the current epoch.

Rationale: this is the point where the successful topic-detail response currently rotates auth state without informing the rest of the runtime.

## Phase 4: Keep write-path recovery minimal in the first patch

**Files:** `rust/crates/fire-core/src/core/network.rs`, `rust/crates/fire-core/src/core/auth.rs`

- Preserve the current write-path contract: if no CSRF token exists, refresh it before the write.
- Do not special-case `/topics/timings`; the repair should apply uniformly to all authenticated writes.
- Preserve the existing `BAD CSRF` one-time retry behavior.

Rationale: once auth rotation clears stale CSRF centrally, the current write path already has the right place to reacquire it.

## Phase 5: Add an optional host resync follow-up only if needed

**Files:** `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift`, `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`

- Add a `FireSessionStore`-owned authenticated write preflight instead of patching `/topics/timings` directly.
- Inject a platform-cookie source into `FireSessionStore`; its first implementation can delegate to `FireWebViewLoginCoordinator.platformCookiesForSessionResync()` and let `FireSessionStore` own `applyPlatformCookies(...)`.
- Use the runtime-only auth recovery hint plus the current auth epoch to decide whether host resync is still eligible.
- Preflight order for eligible writes:
   1. run `refreshCsrfTokenIfNeeded()`,
   2. if the same epoch still carries a pending auth recovery hint, run one host resync for that epoch,
   3. rerun `refreshCsrfTokenIfNeeded()`,
   4. execute the original write.
- Keep a single-flight task per epoch inside `FireSessionStore` so concurrent writes share one host resync attempt.
- Drop late host resync results whose epoch no longer matches the current auth epoch.
- Add a short failure cooldown or attempted-epoch set so a failed or no-op resync cannot loop forever.
- Do not trigger host resync from read paths and do not override explicit `LoginRequired` outcomes.
- Keep this as a second-phase host follow-up rather than mixing it into the first Rust fix.

Rationale: current evidence proves the stale write context bug in `fire-core`, but it does not yet prove that early host resync is mandatory for the first repair.

## Detailed Test Plan

### First-patch required tests

- `rust/crates/fire-core/tests/network.rs`
   Add a regression where a successful authenticated response rotates only `_forum_session`; assert that the auth epoch advances and the previous CSRF token is cleared immediately.
- `rust/crates/fire-core/tests/interactions.rs`
   Reproduce the `call 231 -> call 236` chain and assert that the next `/topics/timings` write reacquires CSRF before posting.
- `rust/crates/fire-core/tests/session_flow.rs`
   Add host-driven session mutation coverage so `apply_platform_cookies(...)` and `sync_login_context(...)` follow the same auth-rotation and CSRF rules as network cookie ingress.

### Tests to add if Phase 5 lands in the same batch

- `native/ios-app/Tests/Unit/FireSessionSecurityTests.swift`
   Verify that one pending auth recovery hint triggers at most one `refreshPlatformCookies()` call per auth epoch.
- `native/ios-app/Tests/Unit/FireSessionSecurityTests.swift`
   Verify single-flight behavior for concurrent authenticated writes that enter the same host resync path.
- `native/ios-app/Tests/Unit/FireSessionSecurityTests.swift`
   Verify that a late host resync result from an older epoch is ignored.
- `native/ios-app/Tests/Unit/FireSessionSecurityTests.swift`
   Verify that explicit `LoginRequired` signals still bypass host resync and continue to the existing logout/reset flow.

### Second-phase tests

- `rust/crates/fire-core/tests/presence.rs`
   Repeat the auth-rotation recovery path on another authenticated write so the fix is not accidentally specific to `/topics/timings`.
- `native/ios-app/Tests/Unit/FireSessionSecurityTests.swift`
   Add a thin AppViewModel-level regression after the SessionStore seam is in place, confirming that retryable auth recovery does not collapse the topic detail view while explicit `LoginRequired` still does.
- `rust/crates/fire-core/tests/network.rs`
   Cover any new auth-rotation diagnostics or support-bundle fields once their shape is stable.

### Tests to avoid initially

- Do not start with real `WKWebsiteDataStore` timing tests; prefer a fake platform-cookie provider seam.
- Do not lock the full support-bundle trace into a large golden file; assert the key behaviors and a small number of diagnostic fields instead.

## Verification

1. Reproduce the `call 231 -> call 236` sequence in automated tests and verify that the stale CSRF token is cleared as soon as auth rotates.
2. Verify that the next write performs CSRF refresh before sending `/topics/timings`.
3. Verify that existing `discourse-logged-out` and `not_logged_in` regression tests still pass unchanged.
4. Validate on device that the topic detail page no longer resets through this specific mixed auth-context chain.
5. If Phase 5 is implemented, verify that a platform-cookie resync can restore a matching `_t` without regressing normal login state persistence.

## Open Questions

1. Does Discourse expect the previous `_t` to remain valid across this `_forum_session` rotation, or is the decisive failure actually the stale CSRF token tied to the old auth session?
2. Does `refresh_csrf_token` succeed under `new _forum_session + old _t`, or does it immediately surface the same logout signal?
3. Should support bundles expose the session epoch and an `auth_rotation_reason` field to make this class of incident easier to diagnose?

## Documentation Follow-Up

- Keep `docs/architecture/ios-auth-cookie-invalidation-fix.md` scoped to non-authoritative cookie deletion behavior.
- Use this document for the current-response auth rotation follow-up until the implementation lands and the final behavior is verified.