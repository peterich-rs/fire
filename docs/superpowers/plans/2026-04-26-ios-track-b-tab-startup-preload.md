# iOS Track B — Tab Startup Preload Implementation Plan

> **For agentic workers:** Follow `docs/superpowers/plans/2026-04-28-ios-quality-and-polish-orchestration.md` for subagent roles, `manage_todo_list` tracking, artifact bundling, commit ownership, and the unified-PR rule. Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Treat the checkboxes here as execution notes only.

**Goal:** After the session becomes authenticated (cold launch or re-login), kick off a background-priority preload of the two off-screen tab stores — `FireProfileViewModel` and `FireNotificationStore` — so users tapping the Notifications or Profile tab shortly after Home loads do not see an empty state.

**Architecture:** Introduce a stateless `FireStartupPreloadCoordinator` that takes two protocol-shaped collaborators (`FireStartupPreloadProfileLoader`, `FireStartupPreloadNotificationsLoader`) and exposes `preloadOffScreenTabs()` (fire-and-forget) plus an `await runPreload()` body for tests. Wire the call from inside the existing `.task(id: isAuthenticated)` block in `FireTabRoot.swift`, after `ensurePushRegistration()` and pending-route handling. Idempotency is delegated to the underlying methods: `loadProfile(force: false)`'s built-in `loadedUsername`/`profile`/`summary` guard, and a `hasLoadedRecentOnce` check at the call site for `loadRecent`.

**Tech Stack:** Swift Concurrency (`Task(priority: .background)`), SwiftUI `.task(id:)`, XCTest.

---

## Spec reference

Track B in `docs/superpowers/specs/ios-quality-and-polish-design.md` (lines 54–114). See "Goal", "Architecture", "Key decisions", "Testing", and "Risk".

## Context (call out for the implementer)

- `FireTabRoot.swift:85-96` already owns the `.task(id: isAuthenticated)` closure. The coordinator gets called inside the `if isAuthenticated { ... }` branch, right after `selectTabForPendingRouteIfReady(...)` and before `viewModel.updateTopLevelAPMRoute(...)`.
- `FireProfileViewModel.loadProfile(force: false)` lives at `native/ios-app/App/FireProfileViewModel.swift:107-144`. Its idempotency guard is line 112: `guard force || loadedUsername != username || profile == nil || summary == nil else { return }`. Calling it twice with `force: false` after the first successful load is a cheap no-op.
- `FireNotificationStore.loadRecent(force: Bool = true)` lives at `native/ios-app/App/Stores/FireNotificationStore.swift:102-126`. Its in-flight guard is `guard !isLoadingRecent || force else { return }` (line 104), but it does **not** guard on already-loaded-once. The call-site check on `hasLoadedRecentOnce` (`Stores/FireNotificationStore.swift:8`) is what prevents the duplicate fetch the spec calls out.
- `FireAppViewModel.loadInitialState` already issues `await self.notificationStore?.loadRecent(force: false)` at line 372 as part of the cold-start restore. Track B does **not** remove that call. The new preload trigger is additive: in re-login flows or when restore proceeds without going through that branch, the `.task(id:)` trigger ensures both stores still get warmed.
- The new code path must compile against the existing `@MainActor` constraints on both stores (they are `@MainActor` types). The coordinator is `@MainActor` for the same reason.

## File map

- **Create**:
  - `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift` — the protocol declarations and the coordinator type.
  - `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift` — pure-logic tests using mock collaborators.
- **Modify**:
  - `native/ios-app/App/FireProfileViewModel.swift` — add explicit `FireStartupPreloadProfileLoader` conformance via an empty extension at the bottom of the file.
  - `native/ios-app/App/Stores/FireNotificationStore.swift` — add explicit `FireStartupPreloadNotificationsLoader` conformance via an empty extension at the bottom of the file.
  - `native/ios-app/App/FireTabRoot.swift` — invoke the coordinator from inside `.task(id: isAuthenticated)`.
- **Regenerate**:
  - `native/ios-app/Fire.xcodeproj/project.pbxproj` — `xcodegen generate --spec native/ios-app/project.yml` picks up the new source file under `App/Startup/` because `App` is already a recursive source root.

No `project.yml` edit is required because `App/` and `Tests/Unit/` are already configured as source roots for the `Fire` and `FireTests` targets respectively.

---

## Task 1: Define the protocol-shaped collaborators and coordinator stub

**Files:**
- Create: `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`

- [ ] **Step 1: Create the new file with protocols and an empty coordinator body**

Create `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`:

```swift
import Foundation

@MainActor
protocol FireStartupPreloadProfileLoader: AnyObject {
    /// Mirrors `FireProfileViewModel.loadProfile(force:)`: synchronous on
    /// MainActor, fires off internal work, idempotent for the current
    /// session when `force == false`.
    func loadProfile(force: Bool)
}

@MainActor
protocol FireStartupPreloadNotificationsLoader: AnyObject {
    /// Mirrors `FireNotificationStore.hasLoadedRecentOnce`. Used by the
    /// coordinator to skip a redundant recent-fetch when the user
    /// already landed on the Notifications tab in this session.
    var hasLoadedRecentOnce: Bool { get }

    /// Mirrors `FireNotificationStore.loadRecent(force:)`.
    func loadRecent(force: Bool) async
}

/// Preloads the two off-screen tab stores at background priority once the
/// session is authenticated, so switching to Notifications or Profile
/// shortly after cold launch shows populated content instead of an empty
/// state.
///
/// Stateless. The owner is responsible for deciding *when* to invoke
/// `preloadOffScreenTabs` (in this app: from `FireTabRoot.swift`'s
/// `.task(id: isAuthenticated)` block).
@MainActor
final class FireStartupPreloadCoordinator {
    private let profile: FireStartupPreloadProfileLoader
    private let notifications: FireStartupPreloadNotificationsLoader

    init(
        profile: FireStartupPreloadProfileLoader,
        notifications: FireStartupPreloadNotificationsLoader
    ) {
        self.profile = profile
        self.notifications = notifications
    }

    /// Schedules the preload on a background-priority `Task`. Returns
    /// immediately. The OS scheduler may yield to foreground rendering
    /// or higher-priority network calls before the body executes.
    func preloadOffScreenTabs() {
        Task(priority: .background) {
            await self.runPreload()
        }
    }

    /// The actual preload body. Exposed (rather than private) so unit
    /// tests can drive it deterministically without polling for the
    /// background `Task` to settle.
    func runPreload() async {
        // Body filled in Task 3.
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new source file is picked up**

Run:

```bash
xcodegen generate --spec native/ios-app/project.yml
```

Expected: success. `git status` shows `App/Startup/FireStartupPreloadCoordinator.swift` added and `Fire.xcodeproj/project.pbxproj` modified to include it under the `Fire` target.

- [ ] **Step 3: Build to confirm the new file compiles cleanly**

Run:

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-b \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. (No tests yet — that's Task 3.)

---

## Task 2: Make the existing stores conform to the new protocols

**Files:**
- Modify: `native/ios-app/App/FireProfileViewModel.swift` (append at end of file)
- Modify: `native/ios-app/App/Stores/FireNotificationStore.swift` (append at end of file)

- [ ] **Step 1: Add `FireStartupPreloadProfileLoader` conformance to `FireProfileViewModel`**

Append to the bottom of `native/ios-app/App/FireProfileViewModel.swift` (after the closing brace of the type, currently line 257):

```swift
extension FireProfileViewModel: FireStartupPreloadProfileLoader {}
```

`FireProfileViewModel.loadProfile(force:)` already matches the protocol's signature exactly, so no method body changes are required.

- [ ] **Step 2: Add `FireStartupPreloadNotificationsLoader` conformance to `FireNotificationStore`**

Append to the bottom of `native/ios-app/App/Stores/FireNotificationStore.swift`:

```swift
extension FireNotificationStore: FireStartupPreloadNotificationsLoader {}
```

`FireNotificationStore.hasLoadedRecentOnce` (already `@Published private(set) var`) and `loadRecent(force:)` (already `async`) match the protocol signatures.

- [ ] **Step 3: Build to verify both conformances compile**

Run:

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-b \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. If Swift complains about a signature mismatch (most commonly: missing `force:` default value or non-async loadRecent), re-check that you copied the protocols verbatim from Task 1 — defaults on protocol methods are not allowed but the conformance need not declare them.

---

## Task 3: Test that `runPreload` invokes both loaders on a fresh session

**Files:**
- Create: `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift`

- [ ] **Step 1: Write the failing test (test 1 of 4) plus shared mocks**

Create `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift`:

```swift
import XCTest
@testable import Fire

@MainActor
final class FireStartupPreloadCoordinatorTests: XCTestCase {
    func testRunPreloadInvokesProfileAndNotificationsOnFreshSession() async {
        let profile = MockProfileLoader()
        let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
        let coordinator = FireStartupPreloadCoordinator(
            profile: profile,
            notifications: notifications
        )

        await coordinator.runPreload()

        XCTAssertEqual(profile.loadProfileInvocations, [false])
        XCTAssertEqual(notifications.loadRecentInvocations, [false])
    }
}

@MainActor
private final class MockProfileLoader: FireStartupPreloadProfileLoader {
    private(set) var loadProfileInvocations: [Bool] = []

    func loadProfile(force: Bool) {
        loadProfileInvocations.append(force)
    }
}

@MainActor
private final class MockNotificationsLoader: FireStartupPreloadNotificationsLoader {
    var hasLoadedRecentOnce: Bool
    private(set) var loadRecentInvocations: [Bool] = []
    var loadRecentError: Error?

    init(hasLoadedRecentOnce: Bool) {
        self.hasLoadedRecentOnce = hasLoadedRecentOnce
    }

    func loadRecent(force: Bool) async {
        loadRecentInvocations.append(force)
        // Simulate the production store's "swallow errors via existing
        // pathways" contract: never throw out.
        _ = loadRecentError
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FireTests/FireStartupPreloadCoordinatorTests/testRunPreloadInvokesProfileAndNotificationsOnFreshSession \
  CODE_SIGNING_ALLOWED=NO
```

Expected: **FAIL**. The empty `runPreload` body never invokes either mock, so both arrays are `[]`, not `[false]`.

- [ ] **Step 3: Implement `runPreload` minimally to make the test pass**

In `native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift`, replace the body of `runPreload` with:

```swift
func runPreload() async {
    profile.loadProfile(force: false)
    if !notifications.hasLoadedRecentOnce {
        await notifications.loadRecent(force: false)
    }
}
```

- [ ] **Step 4: Re-run the test to verify it passes**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FireTests/FireStartupPreloadCoordinatorTests/testRunPreloadInvokesProfileAndNotificationsOnFreshSession \
  CODE_SIGNING_ALLOWED=NO
```

Expected: **PASS**.

---

## Task 4: Test that `runPreload` skips the notifications fetch when already loaded once

**Files:**
- Modify: `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift`

- [ ] **Step 1: Add the failing test as a new method on the test class**

Insert immediately below the existing test method (before the closing brace of the test class):

```swift
func testRunPreloadSkipsNotificationsFetchWhenAlreadyLoadedOnce() async {
    let profile = MockProfileLoader()
    let notifications = MockNotificationsLoader(hasLoadedRecentOnce: true)
    let coordinator = FireStartupPreloadCoordinator(
        profile: profile,
        notifications: notifications
    )

    await coordinator.runPreload()

    XCTAssertEqual(profile.loadProfileInvocations, [false])
    XCTAssertEqual(notifications.loadRecentInvocations, [])
}
```

- [ ] **Step 2: Run the test and confirm it passes immediately**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FireTests/FireStartupPreloadCoordinatorTests/testRunPreloadSkipsNotificationsFetchWhenAlreadyLoadedOnce \
  CODE_SIGNING_ALLOWED=NO
```

Expected: **PASS**. The Task 3 implementation already encodes the `if !hasLoadedRecentOnce` guard, so this test passes on first run. (If it fails, the `runPreload` body is missing the guard — fix `runPreload` to add it.)

The "TDD" framing is preserved: the test asserts a behavior we deliberately implemented in Task 3, and confirms it. If Task 3 had been done incorrectly, this test would have caught it.

---

## Task 5: Test that successive ready transitions invoke the methods once per call

**Files:**
- Modify: `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift`

- [ ] **Step 1: Add the failing test asserting per-invocation dispatch**

Insert below the previous test:

```swift
func testRunPreloadInvokesMethodsOnceEachCall() async {
    let profile = MockProfileLoader()
    let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
    let coordinator = FireStartupPreloadCoordinator(
        profile: profile,
        notifications: notifications
    )

    await coordinator.runPreload()
    notifications.hasLoadedRecentOnce = true
    await coordinator.runPreload()
    notifications.hasLoadedRecentOnce = false
    await coordinator.runPreload()

    // Profile is invoked every time (idempotency lives inside the
    // production loader, not the coordinator).
    XCTAssertEqual(profile.loadProfileInvocations, [false, false, false])

    // Notifications are invoked when hasLoadedRecentOnce is false at
    // dispatch time: call 1 (false), call 3 (false). Call 2 was skipped.
    XCTAssertEqual(notifications.loadRecentInvocations, [false, false])
}
```

- [ ] **Step 2: Run the test to verify it passes**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FireTests/FireStartupPreloadCoordinatorTests/testRunPreloadInvokesMethodsOnceEachCall \
  CODE_SIGNING_ALLOWED=NO
```

Expected: **PASS**. This exercises the spec's test case "Successive ready→not-ready→ready transitions invoke the methods once per ready transition" — represented at the coordinator boundary as "each call to `runPreload` dispatches one invocation". The ready/not-ready bookkeeping itself lives in `FireTabRoot.swift`'s `.task(id: isAuthenticated)` and is not in scope for coordinator tests.

---

## Task 6: Test that the coordinator does not surface preload failures

**Files:**
- Modify: `native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift`

- [ ] **Step 1: Add the failing test that simulates a notifications failure**

Insert below the previous test:

```swift
func testRunPreloadDoesNotSurfaceNotificationsLoadFailure() async {
    struct PreloadStubError: Error {}

    let profile = MockProfileLoader()
    let notifications = MockNotificationsLoader(hasLoadedRecentOnce: false)
    notifications.loadRecentError = PreloadStubError()
    let coordinator = FireStartupPreloadCoordinator(
        profile: profile,
        notifications: notifications
    )

    // Spec: "Failure handling: silent. Both calls swallow errors via the
    // stores' existing pathways". The coordinator must never throw out
    // and must never block subsequent calls.
    await coordinator.runPreload()
    await coordinator.runPreload()

    XCTAssertEqual(notifications.loadRecentInvocations, [false, false])
}
```

- [ ] **Step 2: Run the test and confirm it passes**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:FireTests/FireStartupPreloadCoordinatorTests/testRunPreloadDoesNotSurfaceNotificationsLoadFailure \
  CODE_SIGNING_ALLOWED=NO
```

Expected: **PASS**. `runPreload` is non-throwing and the mock loader records-then-discards the simulated error, mirroring the production stores' contract that errors flow through internal `recordRecentLoadFailure` / `errorMessage` published state instead of propagating out to callers.

---

## Task 7: Wire the coordinator into `FireTabRoot.swift`

**Files:**
- Modify: `native/ios-app/App/FireTabRoot.swift:85-96`

- [ ] **Step 1: Update the `.task(id: isAuthenticated)` block to schedule the preload**

In `native/ios-app/App/FireTabRoot.swift`, replace the existing block (currently lines 85–96):

```swift
        .task(id: isAuthenticated) {
            if isAuthenticated {
                await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                selectTabForPendingRouteIfReady(navigationState.pendingRoute)
            } else {
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: isAuthenticated
            )
        }
```

with:

```swift
        .task(id: isAuthenticated) {
            if isAuthenticated {
                await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
                selectTabForPendingRouteIfReady(navigationState.pendingRoute)
                FireStartupPreloadCoordinator(
                    profile: profileViewModel,
                    notifications: notificationStore
                ).preloadOffScreenTabs()
            } else {
                FireBackgroundNotificationAlertScheduler.cancelRefresh()
            }
            viewModel.updateTopLevelAPMRoute(
                selectedTab: navigationState.selectedTab,
                isAuthenticated: isAuthenticated
            )
        }
```

Why inline construction instead of a stored `@StateObject`: the coordinator is stateless. Inline keeps the view's `init` clean and avoids juggling another `StateObject` wrapper. The capture of `profileViewModel` and `notificationStore` is safe because both are `@StateObject`-backed and stable for the lifetime of the view; the background `Task` they get handed is short-lived (returns as soon as `runPreload` completes).

- [ ] **Step 2: Build the app target to confirm the wiring compiles**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-b \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 8: Run the full test suite, smoke-test in the simulator, commit, and hand off the slice

- [ ] **Step 1: Run the full unit suite to catch regressions**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-b \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`. All four `FireStartupPreloadCoordinatorTests` cases pass alongside the rest of `FireTests`.

- [ ] **Step 2: Manual smoke-test the preload behavior**

Note: this is a UI-feel verification, not a regression test. Type-checking and unit tests cannot prove the empty-state is gone; only running the app can.

In Simulator:

1. Boot a fresh install (`xcrun simctl uninstall booted com.fire.app.ios.<your-bundle-suffix>` or wipe the device) so neither tab has cached content.
2. Launch the app, log in.
3. Wait until Home renders its first feed page.
4. Tap the Notifications tab — it should show notifications immediately, not the empty/loading state.
5. Tap the Profile tab — it should show the avatar/summary immediately, not the loading skeleton.
6. Force-quit, relaunch (cold start). Without tapping anything else after Home appears, switch to Notifications → expect populated. Switch to Profile → expect populated.
7. Trigger logout from the Profile tab, then log back in. Same expectation: switching to off-screen tabs after Home loads shows populated content.

If either tab still shows empty after Home has loaded, dump APM logs (`Application Support/Fire/diagnostics/fire-readable.log`) and confirm `notificationStore.loadRecent` and `profileViewModel.loadProfile` were both called within ~1s of the Home feed completing. If they were not, recheck Step 1 of Task 7 — the most common slip is forgetting `.preloadOffScreenTabs()` and only constructing the coordinator.

- [ ] **Step 3: Confirm no XcodeGen drift**

```bash
xcodegen generate --spec native/ios-app/project.yml
git diff --exit-code -- native/ios-app/Fire.xcodeproj
```

Expected: exit code `0`. Otherwise commit the regenerated project alongside.

- [ ] **Step 4: Stage and commit if the active orchestration flow assigned VCS ownership**

```bash
git add native/ios-app/App/Startup/FireStartupPreloadCoordinator.swift \
        native/ios-app/App/FireProfileViewModel.swift \
        native/ios-app/App/Stores/FireNotificationStore.swift \
        native/ios-app/App/FireTabRoot.swift \
        native/ios-app/Tests/Unit/FireStartupPreloadCoordinatorTests.swift \
        native/ios-app/Fire.xcodeproj

git commit -m "$(cat <<'EOF'
feat(ios): preload off-screen tabs once session is authenticated

Adds FireStartupPreloadCoordinator, a stateless type that warms the
profile and notifications stores at background priority right after
the .task(id: isAuthenticated) closure in FireTabRoot fires. Profile
loading reuses the existing loadedUsername guard for idempotency; the
notifications call is gated on hasLoadedRecentOnce so it does not
race with an in-flight per-tab refresh.
EOF
)"
```

Expected: commit lands; pre-commit hooks pass. If this slice does not own VCS operations, keep the commit message for the handoff bundle instead of executing it.

- [ ] **Step 5: Return the Track B artifact bundle to the main agent**

Record the following in the handoff bundle:

- touched files and expected diff shape
- commands run plus success/failure status
- validation results (`xcodebuild test`, smoke-test outcomes, `xcodegen` drift check)
- docs updated or explicitly checked
- residual risks or follow-ups
- commit SHA, or the proposed commit message from Step 4 if this slice did not own VCS actions

Include the manual preload smoke-test observations explicitly. Stop after handoff. The unified PR is opened only after Tracks A, B, and C are complete.
