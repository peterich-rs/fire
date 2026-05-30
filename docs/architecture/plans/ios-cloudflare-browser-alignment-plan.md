# Align iOS Cloudflare Recovery With Browser Behavior

## Feasibility Assessment

Status update (2026-05-30): the topic-detail origin-threading slice has landed. `FireTopicDetailView` now passes the best known slug into `FireTopicDetailStore`, the store caches the recovery slug per topic, and topic-rooted reads/writes pass a canonical topic HTML URL into `performWithCloudflareRecovery`. Remaining items in this plan, such as splitting recovery into a separate sheet and adding cooldown suppression, are still future work.

The iOS host already centralizes Cloudflare recovery state, auth presentation, and startup sequencing inside `native/ios-app/App/FireAppViewModel.swift`. The recovery UI already sits on a reusable `FireLoginWebView` / `FireWebViewBox` / probe bridge stack in `native/ios-app/App/FireLoginWebView.swift`, and the shared Rust client already injects browser-style `User-Agent`, `Origin`, and `Referer` for JSON API and MessageBus requests in `rust/crates/fire-core/src/core/network.rs`.

## Current Surface Inventory

- `native/ios-app/App/FireAppViewModel.swift` `FireCloudflareChallengeContext` -- Cloudflare context carries `operation`, `message`, and an optional browser HTML origin URL.
- `native/ios-app/App/FireAppViewModel.swift` `FireAuthPresentationState` -- current presentation state has only `.login`, so explicit login and interactive Cloudflare recovery share one surface contract.
- `native/ios-app/App/FireAppViewModel.swift` `loadInitialState()` -- restores session, refreshes home feed, and refreshes notifications back-to-back with no browser-like gaps.
- `native/ios-app/App/FireAppViewModel.swift` `applySession(_:)` / `startMessageBus()` -- starts MessageBus immediately once readiness flips to `canOpenMessageBus`.
- `native/ios-app/App/FireAppViewModel.swift` `performWithCloudflareRecovery(operation:originURL:work:)` -- retries once after cookie sync, then escalates to interactive recovery with a browser HTML origin URL.
- `native/ios-app/App/FireAppViewModel.swift` `beginCloudflareRecoveryAndWait(operation:originURL:)` -- coalesces waiters, deletes stale `cf_clearance`, records the origin URL, and currently presents `.login`.
- `native/ios-app/App/FireAppViewModel.swift` `handleCloudflareChallengeIfNeeded(_:message:originURL:)` -- generic Cloudflare handler that records an origin URL and also presents `.login`.
- `native/ios-app/App/FireAppViewModel.swift` `completeLogin(from:)` / `dismissAuthPresentation()` -- current completion and cancellation path for both login and recovery.
- `native/ios-app/App/FireLoginWebView.swift` `FireAuthScreen` -- full-screen login/recovery container that already owns address bar, banners, embedded WebView, and bottom action area.
- `native/ios-app/App/FireLoginWebView.swift` `FireAuthBottomBar` -- current action bar already supports the automatic post-recovery sync copy.
- `native/ios-app/App/FireTabRoot.swift` `.fullScreenCover(item: $viewModel.authPresentationState)` -- current root presentation entry point for all auth-related flows.
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` `loadTopics(...)` -- homepage/list read path already wraps fetches in `performWithCloudflareRecovery(...)`.
- `native/ios-app/App/Stores/FireNotificationStore.swift` `loadRecent(...)` / `loadFullPage(...)` -- notification read paths still rely on `handleRecoverableSessionErrorIfNeeded(...)` after failures.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `loadTopicDetail(...)` -- initial topic detail read path uses `performWithCloudflareRecovery(...)`, but only knows `topicId` / `targetPostNumber`.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `loadNextTopicResponsePage(...)` and reply-context loaders -- additional topic-detail reads can reuse the same recovery origin once the topic screen is cached.
- `native/ios-app/App/FireTopicDetailView.swift` `topicShareURL` -- existing canonical HTML topic URL builder uses the live slug when available.
- `native/ios-app/App/Routing/FireAppRoute.swift` `topic(action:)` -- current route fallback already normalizes missing slugs to a synthetic topic label for in-app routing.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` `fetchHomeHTML(in:)` -- existing browser-context HTML fetch already behaves like a same-site page fetch.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` `performRcRequest(...)` -- existing rc POST already sets `Origin` and `Referer` explicitly.
- `rust/crates/fire-core/src/core/network.rs` `FireCommonHeaderInterceptor` -- shared Rust request pipeline already owns browser-style headers for JSON API and MessageBus calls.
- `docs/architecture/fire-native-workspace.md` step 10 -- current long-lived architecture doc still describes Cloudflare recovery as opening the login URL.

## Design

This change keeps the platform/Rust ownership split intact: Rust still classifies `CloudflareChallenge`, owns session state, and sends browser-style API headers; iOS still owns WebView presentation, interactive challenge completion, and startup pacing. The implementation goal is to make host recovery look more like a real browser session without re-architecting the existing login/WebView stack.

### Key design decisions

1. Split explicit login from interactive Cloudflare recovery in `FireAuthPresentationState`.
Alternative rejected: keep a single `.login` case plus boolean flags. That keeps the state enum smaller, but it still leaves `FireTabRoot` unable to express two distinct presenters (`fullScreenCover` vs `sheet`) cleanly.

2. Keep explicit login full-screen and move Cloudflare recovery to a medium/large bottom sheet.
Alternative rejected: keep `fullScreenCover` for both flows. The current recovery is transient and often self-completes; a sheet preserves more task context and better matches the mental model of “complete a verification, then continue”.

3. Recovery WebViews must load browser HTML URLs, never `/login` by default and never JSON API endpoints.
Alternative rejected: always open `/login` or the original `.json` request URL. `/login` discards the page context that triggered the challenge, and `/t/{id}.json?...` remains an API-shaped surface that does not resemble a browser navigation. Topic-detail-triggered recovery should open the topic HTML page; all other flows should use the site root.

4. Topic-detail recovery should use the canonical topic page without encoding `postNumber` into the recovery URL.
Alternative rejected: open `https://linux.do/t/{slug}/{topicId}/{postNumber}` or replay the full read query. The recovery sheet exists only to obtain a valid browser clearance; the blocked native topic read already knows how to restore target post state after retry.

5. Rate-limit interactive recovery at the point where the sheet would open, and make the generic Cloudflare handler respect the same cooldown.
Alternative rejected: throttle only `performWithCloudflareRecovery(...)`. That still leaves `handleCloudflareChallengeIfNeeded(...)` free to reopen a sheet immediately from notification sync, MessageBus start, or other read paths.

6. Treat request-header work as an audit, not a rewrite.
Alternative rejected: move browser header policy into new host-side helpers. `rust/crates/fire-core/src/core/network.rs` already injects browser-like `User-Agent`, `Origin`, `Referer`, and login markers for JSON API and MessageBus requests, while `FireCfClearanceRefreshService` already sets `Origin`/`Referer` for the rc endpoint. The only host request worth aligning here is the lightweight login warmup request.

7. Keep startup pacing in `FireAppViewModel` instead of moving sequencing into stores or Rust.
Alternative rejected: push delays into `FireHomeFeedStore`, `FireNotificationStore`, or shared networking. The current burst is created by host orchestration order after `restoreColdStartSession()` and by immediate MessageBus activation in `applySession(_:)`.

### Concrete interface changes

```swift
struct FireCloudflareChallengeContext: Equatable {
    let id: UUID
    let operation: String
    let message: String
    let originURL: URL?
}

enum FireAuthPresentationState: Identifiable, Equatable {
    case login
    case cloudflareRecovery(originURL: URL?)

    var id: String {
        switch self {
        case .login:
            return "login"
        case .cloudflareRecovery:
            return "cloudflare_recovery"
        }
    }
}
```

```swift
func performWithCloudflareRecovery<T>(
    operation: String,
    originURL: URL? = nil,
    work: @escaping () async throws -> T
) async throws -> T

private func beginCloudflareRecoveryAndWait(
    operation: String,
    originURL: URL?
) async throws

func handleCloudflareChallengeIfNeeded(
    _ error: Error,
    message: String? = FireTopicInteractionError.requiresCloudflareVerification.errorDescription,
    originURL: URL? = nil
) async -> Bool
```

```swift
private func cloudflareRecoveryTopicURL(
    topicId: UInt64,
    topicSlug: String?
) -> URL? {
    let base = session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedBase = base.isEmpty ? "https://linux.do" : base
    let trimmedSlug = topicSlug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    if trimmedSlug.isEmpty {
        return URL(string: "\(normalizedBase)/t/\(topicId)")
    }

    return URL(string: "\(normalizedBase)/t/\(trimmedSlug)/\(topicId)")
}
```

### Usage examples

```swift
// Homepage / notifications / generic writes
try await appViewModel.performWithCloudflareRecovery(
    operation: "刷新首页话题列表",
    originURL: appViewModel.siteRootRecoveryURL
) {
    try await sessionStore.fetchTopicList(query: query)
}
```

```swift
// Topic detail initial load
await topicDetailStore.loadTopicDetail(
    topicId: topic.id,
    topicSlug: topic.slug,
    targetPostNumber: scrollToPostNumber
)

// Inside the store
try await appViewModel.performWithCloudflareRecovery(
    operation: "加载话题详情",
    originURL: appViewModel.cloudflareRecoveryTopicURL(topicId: topicId, topicSlug: topicSlug)
) {
    try await sessionStore.fetchTopicScreen(query: query)
}
```

The topic-detail helper should prefer `https://linux.do/t/{slug}/{topicId}` when a slug is available, and fall back to `https://linux.do/t/{topicId}` when it is not. This is intentionally different from the current `topicShareURL` fallback of `topic-{id}`: recovery needs a guaranteed browser route even before detail payloads are loaded, while share links can tolerate redirects.

## Phased Implementation

## Phase 1: Split Login And Recovery Presentation

**File: `native/ios-app/App/FireAppViewModel.swift` (lines 49-55, 224, 377-445, 1617-1917, 2148-2159)**

- Expand `FireAuthPresentationState` to `.login` and `.cloudflareRecovery(originURL:)`.
- Expand `FireCloudflareChallengeContext` to persist the recovery origin selected by the triggering code path.
- Update `openLogin()` / `presentLoginAuthFlow()` / `resetSessionAndPresentLogin(...)` to continue presenting `.login` only.
- Update `beginCloudflareRecoveryAndWait(...)` and `handleCloudflareChallengeIfNeeded(...)` to present `.cloudflareRecovery(originURL:)` instead of `.login`.
- Keep `completeLogin(from:)`, `dismissAuthPresentation()`, and waiter resolution as the single exit path for both surfaces.

```swift
let context = FireCloudflareChallengeContext(
    id: UUID(),
    operation: operation,
    message: "\(operation) 需要先完成 Cloudflare 验证。完成后会自动重试。",
    originURL: originURL
)
pendingCloudflareRecovery = PendingCloudflareRecovery(
    context: context,
    initialCookieSnapshot: initialCookieSnapshot
)
setAuthPresentationState(.cloudflareRecovery(originURL: originURL))
```

Rationale: the state change is the smallest way to decouple presentation policy from login/recovery completion semantics.

**File: `native/ios-app/App/FireLoginWebView.swift` (lines 257-425)**

- Keep `FireAuthScreen` as the dedicated explicit-login full-screen surface.
- Add `FireCloudflareRecoverySheet` that reuses `FireLoginWebView`, `FireLoginAddressBar`, error/info banners, readiness probing, and the auto-sync section of the current bottom bar.
- Configure the recovery sheet with `presentationDetents([.medium, .large])` and a compact header string such as “需要完成安全验证”.
- Keep the recovery sheet dismiss action wired to `viewModel.dismissAuthPresentation()` so manual close still cancels the blocked operation.

```swift
struct FireCloudflareRecoverySheet: View {
    @ObservedObject var viewModel: FireAppViewModel
    let presentationState: FireAuthPresentationState
    @StateObject private var webViewBox = FireWebViewBox()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FireLoginAddressBar(currentURL: webViewBox.currentURL)
                FireAuthInfoBanner(message: viewModel.authPresentationMessage)
                FireLoginWebView(...)
            }
            .safeAreaInset(edge: .bottom) {
                FireAuthBottomBar(...)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

Rationale: the sheet must share the same WebView/profile/probe bridge so recovery semantics stay unchanged.

**File: `native/ios-app/App/FireTabRoot.swift` (line 80)**

- Replace the single `fullScreenCover` binding with two computed bindings: one for `.login`, one for `.cloudflareRecovery(...)`.
- Present `FireAuthScreen` through `.fullScreenCover` and `FireCloudflareRecoverySheet` through `.sheet`.
- Keep all other startup tasks and tab wiring unchanged in this phase.

```swift
.fullScreenCover(item: loginBinding) { presentationState in
    FireAuthScreen(viewModel: viewModel, presentationState: presentationState)
}
.sheet(item: recoveryBinding) { presentationState in
    FireCloudflareRecoverySheet(viewModel: viewModel, presentationState: presentationState)
}
```

Rationale: presenter selection belongs at the root, not inside the sheet/full-screen content views.

## Phase 2: Thread Browser-Origin Recovery URLs

**File: `native/ios-app/App/FireAppViewModel.swift` (lines 1590-1917)**

- Add an optional `originURL` parameter to `performWithCloudflareRecovery(...)`, `beginCloudflareRecoveryAndWait(...)`, and `handleCloudflareChallengeIfNeeded(...)`.
- Add small helpers for `siteRootRecoveryURL` and `cloudflareRecoveryTopicURL(topicId:topicSlug:)`.
- Default all non-topic flows to the site root instead of `/login`.

```swift
private var siteRootRecoveryURL: URL? {
    let trimmed = session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    return URL(string: trimmed.isEmpty ? "https://linux.do/" : trimmed)
}
```

Rationale: the UI needs a concrete URL, and centralizing that normalization avoids scattering base-URL fallbacks.

**File: `native/ios-app/App/FireTopicDetailView.swift` (lines 585-596, 1108-1112)**

- Pass the route-preview slug into `loadTopicDetail(...)` on the initial screen task.
- Keep the existing share-link logic, but do not reuse its synthetic `topic-{id}` fallback for recovery.

```swift
await topicDetailStore.loadTopicDetail(
    topicId: topic.id,
    topicSlug: topic.slug,
    targetPostNumber: scrollToPostNumber
)
```

Rationale: the first topic-detail-triggered recovery happens before `TopicScreenState` has been cached, so the originating view must supply the slug if it has one.

**File: `native/ios-app/App/Stores/FireTopicDetailStore.swift` (lines 227-303, 396-435, 878-946, 1119-1160, 1732-1808, 2021-2041)**

- Extend `loadTopicDetail(...)` to accept `topicSlug: String? = nil`.
- Store the most recent recovery slug per topic, or derive it from cached `topicScreens[topicId]?.topic.slug` / `topicDetails[topicId]?.slug` once available.
- Use the canonical topic HTML URL for initial detail load, pagination, reply-context fetches, AI summary loads, and incremental post hydration when those reads are rooted in a specific topic.
- Keep the native network call itself on `fetchTopicScreen` / `fetchTopicResponsePage` / other JSON APIs; only the recovery WebView URL becomes HTML.

```swift
let recoveryURL = appViewModel.cloudflareRecoveryTopicURL(
    topicId: topicId,
    topicSlug: resolvedTopicSlug
)
let page = try await appViewModel.performWithCloudflareRecovery(
    operation: "加载更多帖子",
    originURL: recoveryURL
) {
    try await sessionStore.fetchTopicResponsePage(query: TopicResponsePageQueryState(cursor: cursor))
}
```

Rationale: once a topic is known, every follow-on topic-detail read should recover in the same browser context instead of bouncing back to the site root.

**File: `native/ios-app/App/Stores/FireHomeFeedStore.swift` (lines 362-431)**

- Pass `siteRootRecoveryURL` into the existing homepage/list `performWithCloudflareRecovery(...)` calls.
- Keep `attemptReadPathLoginRecovery(...)` unchanged; it remains a login-cookie resync path, not a Cloudflare path.

Rationale: feed/list reads do not have a stronger browser-context target than the homepage.

**File: `native/ios-app/App/Stores/FireNotificationStore.swift` (lines 98-185)**

- Keep notification reads and state refreshes on the site-root recovery target.
- Continue surfacing notification errors normally when recovery is suppressed or cancelled.

Rationale: notification endpoints are API-only surfaces, so the browser-like fallback should stay on the site root.

**File: `native/ios-app/App/Routing/FireAppRoute.swift` (lines 160-177)**

- Audit only. No code change is required here.
- Reuse the same notion that topic URLs can exist with or without a slug, but do not tie recovery URL generation to app-route parsing.

Rationale: route parsing and recovery URL generation solve related but different problems.

## Phase 3: Add Cooldown And Loop Suppression

**File: `native/ios-app/App/FireAppViewModel.swift` (lines 224-244, 1590-1917, 2153-2159)**

- Add `lastChallengeRecoveryCompletionTime` and `challengeRecoveryCooldownDuration`.
- Add a small helper such as `isChallengeRecoveryCoolingDown(now:)`.
- In `performWithCloudflareRecovery(...)`, check the cooldown immediately before opening interactive recovery; if still cooling down, rethrow `FireUniFfiError.CloudflareChallenge` so callers fall back to normal UI error handling.
- In `handleCloudflareChallengeIfNeeded(...)`, return `false` instead of opening another sheet when no recovery is in flight and the cooldown is active.
- In `resolvePendingCloudflareRecovery(with:)`, record the completion timestamp on success before resuming waiters.

```swift
private func isChallengeRecoveryCoolingDown(now: Date = .init()) -> Bool {
    guard let lastChallengeRecoveryCompletionTime else {
        return false
    }
    return now.timeIntervalSince(lastChallengeRecoveryCompletionTime) < Self.challengeRecoveryCooldownDuration
}
```

Rationale: a recovery cooldown must suppress both proactive write-side escalation and generic read-side re-presentation.

**File: `native/ios-app/App/Stores/FireHomeFeedStore.swift` (lines 414-431)**

- No dedicated logic change beyond honoring the new `handleRecoverableSessionErrorIfNeeded(...) == false` result during cooldown.
- Let the existing `topicLoadErrorMessage = error.localizedDescription` path surface the failure instead of reopening the recovery UI.

Rationale: the store already has the correct fallback behavior once the ViewModel stops claiming the error.

**File: `native/ios-app/App/Stores/FireTopicDetailStore.swift` (lines 288-302, 435, 886, 946, 1160, 1758, 2041)**

- No new topic-detail-specific cooldown state.
- Reuse the existing error-message path when `handleRecoverableSessionErrorIfNeeded(...)` declines to present another recovery sheet.

Rationale: loop suppression belongs in the central recovery coordinator, not in every store.

## Phase 4: Pace Startup And Audit Header Parity

Status update (2026-05-30): startup pacing now favors lazy off-screen tabs instead of small fixed gaps. Cold-start session restore no longer native-refreshes bootstrap through `GET /`; it applies the restored session without starting MessageBus, loads the first home topic list, and only then starts MessageBus. Notifications and Profile are gated by the selected tab, so `GET /notifications` and profile summary/action requests do not run during cold launch.

**File: `native/ios-app/App/FireAppViewModel.swift` (lines 309-355, 1287-1458)**

- Do not preload off-screen Notifications/Profile data during cold launch.
- Restore persisted session/cookies without an eager native `GET /` bootstrap refresh.
- Apply the restored session without starting MessageBus, load the first home-feed page, then start MessageBus.
- Keep notification/profile fetches behind selected-tab checks.
- Align `prepareLoginNetworkAccess()` with browser-style navigation headers that are appropriate for a navigation warmup: explicit browser `User-Agent` and `Accept: text/html`; do not invent `Origin` for a plain GET navigation warmup.

```swift
await self.applySession(restoredSession, activateMessageBus: false)
await self.refreshHomeFeedIfPossible(force: true)
await self.ensureMessageBusActiveIfPossible()
```

Rationale: the risky burst was not just timing; off-screen tab requests added avoidable authenticated reads. Lazy loading removes those requests from launch entirely, while keeping MessageBus behind the first home list reduces the remaining startup burst.

**File: `native/ios-app/App/Stores/FireHomeFeedStore.swift`**

- `refreshTopicsIfPossible(force:)` returns whether a first-page refresh actually completed.
- Successful first-page refreshes opportunistically ensure MessageBus is active, so a manual retry after a failed launch can still bring realtime sync online.

Rationale: startup pacing is a caller concern, but the home store is the place that knows when a first-page refresh has actually succeeded.

**File: `native/ios-app/App/Stores/FireNotificationStore.swift`**

- No code change expected in this phase.
- Notification timing is controlled by selected-tab gating in `FireNotificationsView` plus explicit refresh actions.

Rationale: keeping timing outside the store avoids accidental duplication with manual refresh paths.

**File: `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` (lines 417-428)**

- Audit only. No code change expected.
- The existing browser-context `fetch("/")` call already uses `Accept: text/html`, cookies, and the embedded browser environment.

Rationale: this path already behaves like a page fetch and should remain browser-owned.

**File: `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` (lines 724-744)**

- Audit only. No code change expected.
- Keep the existing explicit `Origin` / `Referer` headers for the rc endpoint POST.

Rationale: the rc request is already the special-case host-owned request that needs explicit same-site POST headers.

**File: `rust/crates/fire-core/src/core/network.rs` (lines 111-156, 986-1024)**

- Audit only. No code change expected.
- Keep `FireCommonHeaderInterceptor` as the single source of truth for JSON API / MessageBus browser headers.

Rationale: this is already landed shared behavior and should not be duplicated in Swift.

## Phase 5: Verify Behavior And Sync Long-Lived Docs

**File: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`**

- Extend the existing Cloudflare-related coverage to assert that topic-detail-triggered recovery chooses a canonical topic HTML URL rather than a JSON endpoint.
- Cover the slug-known and slug-missing cases separately.

Rationale: topic-detail origin selection is the most browser-sensitive branch in this change.

**File: `native/ios-app/Tests/Unit/FireAppViewModelCloudflareRecoveryTests.swift`**

- Add a focused unit-test file for:
  - login vs recovery presentation-state routing
  - cooldown suppression after successful interactive recovery
  - manual recovery-sheet dismissal cancelling waiters
  - delayed MessageBus start respecting readiness changes

Rationale: there is no existing dedicated `FireAppViewModel` recovery test surface, and these behaviors are easier to pin with isolated state tests than with store tests.

**File: `docs/architecture/fire-native-workspace.md` (line 141)**

- Update the long-lived integration rule after the code lands.
- Replace “present a host-owned auth WebView at the LinuxDo login URL” with origin-aware recovery wording that distinguishes explicit login from interactive Cloudflare recovery.

Rationale: the current architecture doc will otherwise continue to describe outdated recovery policy.

**Verification work**

- Run the iOS unit-test suite for `native/ios-app/Fire.xcodeproj` with the updated recovery tests.
- Verify explicit login still opens `FireAuthScreen` full-screen and behaves exactly as today.
- Verify Cloudflare recovery opens as a medium sheet, can expand to large, auto-syncs on readiness, and dismisses itself on success.
- Verify topic-detail-triggered recovery opens the topic HTML page, not `/login` and not `/t/{id}.json?...`.
- Verify a second Cloudflare challenge within 10 seconds surfaces a normal error instead of reopening the sheet.
- Verify cold start still completes, with APM traces showing home feed, notifications, and MessageBus no longer starting in the same burst.

## Architectural Notes

- Semver impact: none. This is an internal iOS host behavior and documentation change.
- Ownership split: unchanged. Rust still owns session state, challenge classification, and browser-style API headers; iOS still owns WebView-based recovery and presentation policy.
- Side effects: MessageBus availability may be delayed by up to 1 second after session restore, and a successful interactive recovery suppresses new recovery UI for 10 seconds.
- What is explicitly not changed: Rust Cloudflare detection, JSON API topic fetches, authenticated-write preflight, and explicit login semantics remain intact.
- Header policy: do not add fake `Origin` headers to plain navigation warmups; keep `Origin` / `Referer` on JSON API, MessageBus, and rc POST requests where they already exist.
- Topic-detail policy: recovery URLs must be browser HTML routes only; the native retry remains responsible for `track_visit`, reply filtering, and target-post restoration.
- Dependency impact: no new packages or frameworks are required.
- Documentation sync: `docs/architecture/fire-native-workspace.md`, `docs/backend-api.md`, and `docs/backend-api/0*-*.md` should describe origin-aware recovery; the topic-detail origin-threading slice updated those docs on 2026-05-30.

## File Change Summary

- `docs/architecture/fire-native-workspace.md` -- long-lived recovery rule now documents topic-detail HTML recovery URLs instead of login-URL-only recovery.
- `docs/architecture/plans/ios-cloudflare-browser-alignment-plan.md` -- record the phased implementation plan for browser-like Cloudflare recovery and startup pacing.
- `native/ios-app/App/FireAppViewModel.swift` -- split auth presentation modes, thread recovery origins, add cooldown gating, and pace startup/MessageBus activation.
- `native/ios-app/App/FireLoginWebView.swift` -- add the half-sheet Cloudflare recovery surface on top of the existing embedded WebView stack.
- `native/ios-app/App/FireTabRoot.swift` -- route login to `fullScreenCover` and Cloudflare recovery to `sheet`.
- `native/ios-app/App/FireTopicDetailView.swift` -- pass route-preview slug data into the initial topic-detail recovery context.
- `native/ios-app/App/Stores/FireHomeFeedStore.swift` -- keep homepage/list recoveries anchored to the site root.
- `native/ios-app/App/Stores/FireNotificationStore.swift` -- keep notification recoveries anchored to the site root and rely on normal error UI during cooldown.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` -- use canonical topic HTML URLs for topic-detail-triggered recovery and cache the best-known topic slug.
- `native/ios-app/Sources/FireAppSession/FireCfClearanceRefreshService.swift` -- audited only; existing rc POST header policy already matches the intended same-site behavior.
- `native/ios-app/Sources/FireAppSession/FireWebViewLoginCoordinator.swift` -- audited only; existing browser-context homepage HTML fetch remains the correct recovery companion path.
- `native/ios-app/Tests/Unit/FireAppViewModelCloudflareRecoveryTests.swift` -- add focused state-machine coverage for presentation routing, cooldown, and delayed MessageBus start.
- `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift` -- extend topic-detail recovery tests to cover canonical HTML recovery URLs.
- `rust/crates/fire-core/src/core/network.rs` -- audited only; existing shared browser-header injection remains the source of truth.
