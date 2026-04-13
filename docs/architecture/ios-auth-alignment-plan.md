# Align iOS Auth Session Recovery With Fluxdo

## Feasibility Assessment

This change is fully achievable inside the current Fire architecture. `fire-core` already owns session state, epoch tracking, cookie transport, login invalidation classification, and shared request execution. The iOS host already owns `WKWebView` login, platform cookie extraction, local cookie mirroring, and Cloudflare WebView surfaces. The remaining work is to close three concrete gaps: full same-site cookie mirroring on iOS, stale-response invalidation in the shared Rust network boundary, and interactive Cloudflare recovery with automatic retry. Fully feasible.

## Current Surface Inventory

- `docs/architecture/fire-native-workspace.md` -- shared architecture contract for auth and session ownership.
- `native/ios-app/App/SessionState+Helpers.swift` -- mirrors Rust session cookies into `HTTPCookieStorage` and `WKHTTPCookieStore`.
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- persists/restores iOS session state and wraps `fire-core`.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` -- extracts username, CSRF, HTML, and cookies from `WKWebView`.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- hidden WebView loop for `cf_clearance` refresh.
- `native/ios-app/App/FireAppViewModel.swift` -- session application, login presentation, and recoverable error routing.
- `native/ios-app/App/FireLoginWebView.swift` -- login-only auth WebView surface.
- `native/ios-app/App/FireTabRoot.swift` -- authenticated vs onboarding root presentation.
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` -- authenticated home topic-list reads.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` -- authenticated topic-detail reads and refreshes.
- `native/ios-app/App/Stores/FireNotificationStore.swift` -- authenticated notification state refreshes.
- `rust/crates/fire-core/src/core/network.rs` -- shared HTTP request execution, status classification, and CSRF retry behavior.
- `rust/crates/fire-core/src/cookies.rs` -- session cookie jar ingress/egress and stale-cookie protection.
- `rust/crates/fire-core/src/error.rs` -- shared Rust error taxonomy.
- `rust/crates/fire-core/src/core/messagebus.rs` -- shared MessageBus request construction.
- `rust/crates/fire-uniffi/src/lib.rs` -- Rust-to-Swift/Kotlin error mapping and exported API surface.

## Design

### Key Design Decisions

1. Use full same-site platform cookie mirroring on iOS rather than mirroring only `_t`, `_forum_session`, and `cf_clearance`.
   Rejected alternative: continue mirroring only critical auth cookies.
   Reason: restored WebView state must match Rust request state, including browser-context cookies such as `__cf_bm`.

2. Invalidate stale responses at the shared Rust network boundary rather than adding ad hoc request-generation checks in Swift stores.
   Rejected alternative: let old successful responses complete and only block stale `Set-Cookie`.
   Reason: stale payloads can still mutate UI state even if stale cookies are blocked.

3. Keep Cloudflare challenge detection in Rust and interactive challenge completion in the iOS host.
   Rejected alternative: move challenge UI policy into Rust.
   Reason: challenge completion depends on `WKWebView`, cookie stores, scene presentation, and host-owned UX state.

4. Reuse one auth WebView shell for both login sync and Cloudflare recovery, but distinguish them via explicit flow state.
   Rejected alternative: maintain a separate challenge-only screen and coordinator tree.
   Reason: the login WebView already owns the necessary cookie observation and completion hooks.

5. Update `origin/main` first, then land the work as two commits on a dedicated feature branch.
   Rejected alternative: stack phase work in the old local baseline.
   Reason: the auth work should sit on the latest reviewed mainline before PR creation.

### Concrete Type / Interface Definitions

`native/ios-app/App/FireAppViewModel.swift`

```swift
enum FireAuthPresentationState: Identifiable, Equatable {
    case login
    case cloudflareRecovery(FireCloudflareChallengeContext)

    var id: String {
        switch self {
        case .login:
            return "login"
        case let .cloudflareRecovery(context):
            return "cloudflare-\(context.id.uuidString)"
        }
    }
}

struct FireCloudflareChallengeContext: Equatable {
    let id: UUID
    let operation: String
    let preferredURL: URL
    let message: String
}
```

`rust/crates/fire-core/src/error.rs`

```rust
pub enum FireCoreError {
    // ...
    StaleSessionResponse { operation: &'static str },
}
```

`native/ios-app/App/FireAppViewModel.swift`

```swift
@MainActor
func performWithCloudflareRecovery<T>(
    operation: String,
    work: @escaping () async throws -> T
) async throws -> T
```

### Usage Examples

```swift
let topics = try await appViewModel.performWithCloudflareRecovery(
    operation: "fetch topic list"
) {
    try await sessionStore.fetchTopicList(query: query)
}
```

```rust
if current_epoch != request_epoch.0 {
    return Err(FireCoreError::StaleSessionResponse { operation });
}
```

## Phased Implementation

## Phase 0: Branch Bootstrap

**File: `docs/architecture/ios-auth-alignment-plan.md`**

- Add this implementation plan as the baseline for the feature branch.
- Record the intended branch, commit split, and verification targets.
- Reason: future code-review discussion needs a stable written target before the code commits land.

**Branch / workstream**

- Branch: `feature/ios-auth-alignment`
- Base branch: latest `origin/main`
- Delivery model: one feature branch, one PR, two initial commits before Phase 2 begins.

**Planned commit split**

- `docs(auth): add ios auth alignment implementation plan`
- `feat(core): invalidate stale responses by session epoch`
- Follow-up commits for later phases stay separate from the Phase 1 core diff.

## Phase 1: Stale Response Guard In Shared Rust Core

**File: `rust/crates/fire-core/src/error.rs`**

- Add `StaleSessionResponse { operation }`.

**File: `rust/crates/fire-core/src/core/network.rs`**

- Extend `TracedRequest` with operation metadata.
- Carry request epoch into the response path.
- Compare response epoch with the current session epoch before the response is returned to callers.
- Treat mismatches as a cancellation-style shared error.

**File: `rust/crates/fire-core/src/cookies.rs`**

- Drop the entire `Set-Cookie` batch when the request epoch is stale.
- Do not special-case only auth cookies anymore.

**File: `rust/crates/fire-core/src/core/messagebus.rs`**

- Keep MessageBus requests compatible with the new `TracedRequest` structure.

**File: `rust/crates/fire-core/tests/network.rs`**

- Cover stale response after local logout.
- Cover stale response after auth-cookie rotation.
- Assert that stale payloads do not surface and stale browser-context cookies do not persist.

**File: `rust/crates/fire-uniffi/src/lib.rs`**

- Map `FireCoreError::StaleSessionResponse` to a dedicated UniFFI error variant for host-side handling.

**Verification**

- `cargo test -p fire-core stale_response -- --nocapture`
- `cargo test -p fire-uniffi maps_ -- --nocapture`
- `cargo test -p fire-core -p fire-uniffi --quiet`
- `bash native/ios-app/scripts/sync_uniffi_bindings.sh`

## Phase 2: Full Same-Site Cookie Mirroring On iOS

**File: `native/ios-app/App/SessionState+Helpers.swift`**

- Mirror the full same-site platform cookie batch into `HTTPCookieStorage.shared` and `WKHTTPCookieStore`.
- Keep scalar fallback only when a platform-cookie variant is unavailable.

**File: `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift`**

- Split platform cookie clearing into:
  - full same-site clear with optional preservation list
  - targeted cookie clear for challenge recovery

## Phase 3: Interactive Cloudflare Recovery Flow

**File: `native/ios-app/App/FireAppViewModel.swift`**

- Introduce an auth presentation enum instead of one login-only boolean.
- Add a shared `performWithCloudflareRecovery(...)` wrapper usable by both reads and writes.

**File: `native/ios-app/App/FireLoginWebView.swift`**

- Generalize the current login screen into a reusable auth flow shell with `login` and `cloudflareRecovery` modes.

**File: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift`**

- Pause automatic refresh during interactive challenge recovery and resume it after success.

## Phase 4: Apply Recovery To Authenticated Read Surfaces

**File: `native/ios-app/App/Stores/FireHomeFeedStore.swift`**

- Wrap topic-list reads in the shared Cloudflare recovery flow.

**File: `native/ios-app/App/Stores/FireTopicDetailStore.swift`**

- Wrap topic-detail loads and mutation-triggered refreshes in the shared recovery flow.

**File: `native/ios-app/App/Stores/FireNotificationStore.swift`**

- Wrap notification-state refreshes in the shared recovery flow.

## Phase 5: Final Verification And Cleanup

**File: `docs/architecture/fire-native-workspace.md`**

- Confirm the Rust-owned stale-response responsibility and iOS-owned challenge completion flow remain documented correctly.

**File: `docs/backend-api*.md`**

- Audited unchanged.
- Reason: this feature changes host/runtime behavior, not backend protocol semantics.

## Architectural Notes

- Semver impact: no public backend/API contract change, but UniFFI error variants grow and require regenerated bindings on native hosts.
- Side effects: stale responses will be cancelled rather than delivered; stale cookie batches will be ignored wholesale.
- Explicitly not changed: anonymous browsing strategy, onboarding root policy, and backend API documentation.
- Dependencies: no new third-party dependencies; the feature stays within existing `openwire`, UniFFI, and `WKWebView` ownership boundaries.

## File Change Summary

- `docs/architecture/fire-native-workspace.md` -- document Rust-owned stale-response invalidation.
- `docs/architecture/ios-auth-alignment-plan.md` -- add the auth-alignment implementation baseline and commit plan.
- `native/ios-app/App/FireAppViewModel.swift` -- planned host-side auth presentation and challenge-recovery coordinator entrypoint.
- `native/ios-app/App/FireLoginWebView.swift` -- planned shared login/challenge auth WebView shell.
- `native/ios-app/App/SessionState+Helpers.swift` -- planned full same-site cookie mirroring.
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` -- planned read-path challenge retry adoption.
- `native/ios-app/App/Stores/FireNotificationStore.swift` -- planned notification refresh challenge retry adoption.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` -- planned detail-read challenge retry adoption.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- planned coordination with interactive challenge recovery.
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- planned host-side stale-response mapping and persistence audit.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` -- planned full-cookie clear and recovery-cookie extraction updates.
- `rust/crates/fire-core/src/cookies.rs` -- drop stale cookie batches wholesale.
- `rust/crates/fire-core/src/core/messagebus.rs` -- keep MessageBus requests aligned with traced-operation metadata.
- `rust/crates/fire-core/src/core/mod.rs` -- expose current session epoch to the shared network layer.
- `rust/crates/fire-core/src/core/network.rs` -- discard stale responses by session epoch before surfacing payloads.
- `rust/crates/fire-core/src/diagnostics.rs` -- allow explicit cancellation of in-progress trace guards.
- `rust/crates/fire-core/src/error.rs` -- add `StaleSessionResponse`.
- `rust/crates/fire-core/tests/network.rs` -- verify stale responses do not mutate session state or surface payloads.
- `rust/crates/fire-uniffi/src/lib.rs` -- map stale-session errors into UniFFI.
