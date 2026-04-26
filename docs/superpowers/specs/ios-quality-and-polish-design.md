# iOS Quality & Polish Pass — Design

## Background

Three independent improvements bundled into one design doc, each shipping under its own implementation plan and PR cycle:

- **Track A — Test layer slimming**: drop the iOS-only "integration" test split, keep pure-logic unit tests. Restore two miscategorised pure-logic cases to the unit suite before deletion.
- **Track B — Tab startup preload**: eliminate the perceptible empty state when users switch from the default Home tab to Notifications or Profile shortly after cold launch.
- **Track C — App-wide animation polish**: add motion polish to interaction feedback, numeric/badge transitions, and navigation/list transitions through a centralised `FireMotion` module built on iOS 17+ native SwiftUI APIs.

The tracks are independent in implementation but share intent: tighten the iOS app's quality story (cleaner tests), startup feel (no empty tabs), and tactile experience (smooth motion). Implementation order is A → B → C — A first to give later tracks a clean CI baseline.

The design doc is unified for navigation; plans are split per track because the implementation grain differs sharply (A is a few yml/markdown edits; C introduces a new module and touches many views).

## Track A — Test Layer Slimming

### Goal

Remove `native/ios-app/Tests/Integration/` and its supporting target/scheme. Migrate two pure-logic cases that were filed there by mistake into the unit suite, so no logic coverage is lost.

### Changes

1. **New** `native/ios-app/Tests/Unit/FireAvatarURLTests.swift` containing two cases lifted verbatim from `FireAvatarImagePipelineTests`:
   - `testAvatarURLReplacesTemplateSizeAndResolvesRelativePath`
   - `testAvatarURLSupportsProtocolRelativePath`

   Both exercise `fireAvatarURL(...)` URL construction with no UIKit/SwiftUI dependency.
2. **Delete** `native/ios-app/Tests/Integration/` (all three files: `FireAPMEventStoreTests`, `FireAvatarImagePipelineTests`, `FireSessionSecurityTests`).
3. **`native/ios-app/project.yml`**:
   - Remove `FireIntegrationTests` target definition.
   - Remove `FireIntegrationTests` scheme.
   - Remove `FireUnitTests` scheme (kept the equivalent `Fire` scheme as the single ⌘U / CI entry point).
   - Keep `FireTests` target name unchanged. (Renaming to `FireUnitTests` was discussed and deferred — minimal benefit, larger diff surface.)
4. **`.github/workflows/ci.yml`** (`native-ios-test` job):
   - Replace `run_xcodebuild FireUnitTests test` with `run_xcodebuild Fire test`.
   - Remove the comment block beginning "Required CI stays on the pure logic lane…" — it references the now-deleted integration target and would mislead readers.
5. **`native/ios-app/README.md`**:
   - Line 184: drop the `FireIntegrationTests` bullet describing the optional hosted suite.
   - Line 196: trim the shared-schemes list to `Fire` only.
   - Line 281: replace the contrast between `FireUnitTests` and `Tests/Integration` with a one-liner stating that `FireTests` contains pure-logic cases.

Doc/code scanning (`grep -rn "FireIntegrationTests\|Tests/Integration" --include="*.md" --include="*.sh" --include="*.yml"`) confirmed no other references inside the repo (excluding `third_party/` and `references/`).

### Verification

- `xcodegen generate --spec native/ios-app/project.yml` succeeds.
- Local: open `Fire.xcodeproj`, ⌘U on `Fire` scheme — all unit tests pass; `FireUnitTests` scheme no longer present in the chooser.
- CI green on push.

### Risk

Low. The integration target is currently not in CI, so removing it cannot mask a regression that CI was previously catching. The two migrated cases preserve their assertions; the rest of the integration coverage is intentional collateral (UI/WebKit/filesystem coverage explicitly out of scope per the user's "logic only" rule).

## Track B — Tab Startup Preload

### Goal

After cold launch (or re-login), once the session is authenticated, preload the data needed by the two off-screen tabs (Notifications and Profile) at background priority so that switching to either feels populated. Home is the default selection and already loads via its own view `.task`; it is not preloaded.

### Architecture

Trigger inside the existing `.task(id: isAuthenticated)` block in `FireTabRoot.swift`. When `isAuthenticated` flips to `true`, after `ensurePushRegistration()` and the pending-route handling, kick off a background `Task` that calls the existing public load methods on the two off-screen stores.

Indicative shape (final wiring decided in plan):

```swift
.task(id: isAuthenticated) {
    if isAuthenticated {
        await FirePushRegistrationCoordinator.shared.ensurePushRegistration()
        selectTabForPendingRouteIfReady(navigationState.pendingRoute)

        Task(priority: .background) {
            // Profile: existing guard inside loadProfile makes this idempotent.
            profileViewModel.loadProfile()

            // Notifications: gate on hasLoadedRecentOnce to avoid redundant
            // fetch when the user lands on the tab right after preload.
            if !notificationStore.hasLoadedRecentOnce {
                await notificationStore.loadRecent(force: false)
            }
        }
    } else {
        FireBackgroundNotificationAlertScheduler.cancelRefresh()
    }
    // existing APM route reporting unchanged
}
```

The implementation extracts this trigger into a small `FireStartupPreloadCoordinator` taking protocol-shaped collaborators (a profile-loader and a notifications-loader). `FireTabRoot.swift` calls the coordinator from inside the `.task(id:)` closure; this keeps `FireTabRoot` lean and the logic unit-testable. (Exact file/protocol names finalised in the plan.)

### Key decisions

- **Trigger**: `isAuthenticated` flips to `true`. Covers both cold launch and re-login. Background → foreground transitions do **not** re-trigger preload — each tab's view `.task` handles refresh on appear naturally.
- **Priority**: `Task(priority: .background)`. Swift Concurrency's background priority lets the OS scheduler yield to the foreground Home rendering and network. No explicit "home loaded" handshake is needed; if testing later shows Home is starved, a handshake can be added without restructuring.
- **Idempotency**:
  - `profileViewModel.loadProfile(force: false)` is already guarded by `guard force || loadedUsername != username || profile == nil || summary == nil else { return }`. Calling it twice is safe.
  - `notificationStore.loadRecent(force: false)` only guards in-flight, not already-loaded-once. The new code reads `notificationStore.hasLoadedRecentOnce` and skips if already loaded, eliminating duplicate fetch when Notifications view appears soon after preload.
- **Failure handling**: silent. Both calls swallow errors via the stores' existing pathways (notifications already routes to `recordRecentLoadFailure`; profile sets `errorMessage`). If preload fails, the destination view's own `.task` retries on appear, so the user-visible behavior is identical to today on the first failure.
- **No store internals modified**. All calls go through existing public methods.

### Testing

Logic-only tests for the preload trigger. To keep the test path independent of `FireTabRoot` (a SwiftUI `View`), extract the trigger into a `FireStartupPreloadCoordinator`-style type that takes protocol-shaped collaborators. The coordinator is then exercised in `FireStartupPreloadCoordinatorTests` covering:

1. When session becomes ready, both store methods are invoked once.
2. When `hasLoadedRecentOnce == true`, `loadRecent` is **not** invoked but `loadProfile` still is.
3. Successive ready→not-ready→ready transitions invoke the methods once per ready transition.
4. Preload failures are not surfaced to callers (no exceptions, no published error state on the coordinator itself).

The internal idempotency of `loadProfile` (already-loaded becomes a no-op) is covered by the existing `FireProfileViewModelTests` and is not re-asserted here.

### Risk

Low. Worst case is a duplicate notifications fetch in a brief race, mitigated by the `hasLoadedRecentOnce` guard. The change is purely additive — failure of preload reduces to today's behavior.

## Track C — App-Wide Animation Polish

### Goal

Add motion polish in three layers chosen by the user — interaction feedback (T1), numeric/badge transitions (T2), and navigation/list transitions (T3) — using iOS 17+ native SwiftUI APIs centralised in a new `FireMotion` module. Tab switching is intentionally left on system `TabView` defaults. Loading skeletons and onboarding/launch animations (T4/T5) are deferred to a future spec.

### Architecture: `FireMotion` module

New folder `native/ios-app/App/FireMotion/`:

| File | Purpose |
|---|---|
| `FireMotionTokens.swift` | Constants: durations, spring response/damping pairs, haptic intensities. Centralises timing so global tuning is a single edit. Reads `accessibilityReduceMotion` to zero out durations when on. |
| `FireMotionTransitions.swift` | Custom `Transition` types: `firePush` (NavigationStack iOS 17 fallback: slide + fade + mild scale), `fireListItem` (insert/delete: slide-from-leading + opacity), `fireSheet` helper for sheet spring tuning. |
| `FireMotionEffects.swift` | `ViewModifier`s exposed as semantic API: `.fireLikeEffect(active:)`, `.fireBookmarkEffect(active:)`, `.fireFollowEffect(active:)`, `.fireSuccessFeedback(trigger:)`, `.fireBadgePulse(value:)`, `.fireNumericChange(value:)`, `.fireCTAPress()`. Internally calls `symbolEffect`, `contentTransition`, `sensoryFeedback`, etc. |
| `FireMotionReduceMotion.swift` | Helper environment-aware modifiers and a guard utility (`fireRespectingReduceMotion(_:)`) used by the other files. ConfettiSwiftUI invocations are gated through this guard so they suppress when the user prefers reduced motion. |

**Rule**: business views call `FireMotion` semantic modifiers, not raw SwiftUI animation APIs, for any motion that falls inside the T1–T3 surfaces below. Layout-driven `.animation(value:)` on geometry properties remains free-form. This rule keeps motion auditable in one location.

### T1 — interaction micro-feedback

Conceptual surfaces (concrete file list enumerated in the plan):

- **Like / unlike**: heart icon — `symbolEffect(.bounce, value:)` + `.sensoryFeedback(.success)` on success.
- **Bookmark / unbookmark**: `contentTransition(.symbolEffect(.replace))` + success haptic.
- **Follow / unfollow**: `symbolEffect(.bounce)` + success haptic.
- **Mark-read / mark-all-read**: list rows fade out via `.transition(.fireListItem)`.
- **Notification badge appear/disappear**: `symbolEffect(.pulse, options: .nonRepeating)`, ReduceMotion-aware.
- **Primary CTAs** (compose, submit, large follow button): `.fireCTAPress()` — scale to ~0.97 on press + `.selection` haptic.
- **Celebration moments only** — first follow milestone, badge unlock — trigger ConfettiSwiftUI through `.fireRespectingReduceMotion`. Not used on every like.

### T2 — numeric and badge changes

- `notificationStore.unreadCount` badge digits — `contentTransition(.numericText())` via `.fireNumericChange(value:)`.
- Like count, view count, post count, follower count — same modifier.
- Profile skeleton → loaded data — single `.transition(.opacity.combined(with: .scale(scale: 0.98)))` swap.

### T3 — navigation and list transitions

- **NavigationStack** push to topic detail / public profile / category list / search results:
  - iOS 18+: `.navigationTransition(.zoom(sourceID:in:))` where source and target geometry can be matched.
  - iOS 17 fallback: route through `.firePush` (slide + fade with mild entrance scale) inside an `if #available(iOS 18, *)` branch.
- **Sheet presentations** (composer, bookmark editor, tag picker, recipient picker): centralise spring config via `.fireSheet()`. Slightly softer damping than system default.
- **List insert/delete/reorder** (topic list, notification list, profile activity timeline): `.transition(.fireListItem)`.

### Third-party

Add to `native/ios-app/project.yml` `packages:` block, mirroring the `CrashReporter` pin style:

- [`ConfettiSwiftUI`](https://github.com/simibac/ConfettiSwiftUI) — MIT, ~600 lines pure SwiftUI. Pinned with `exactVersion`. Used only in celebration spots; never on high-frequency interactions.

No other third-party motion libraries are introduced. Pow is explicitly **not** used (commercial license + derivative-work concerns from reading source). Lottie is explicitly **not** introduced (no designer JSON pipeline yet).

### Reduce Motion / Haptics

- All `FireMotion` modifiers read `@Environment(\.accessibilityReduceMotion)`. When the user prefers reduced motion:
  - Durations zero out (`FireMotionTokens.duration` returns 0).
  - Custom transitions degrade to `.identity` or simple opacity cross-fade.
  - ConfettiSwiftUI is suppressed at the call site.
  - Symbol effects fall back to plain state changes.
- Haptic policy:
  - `.success` on confirmed positive outcomes (like/bookmark/follow success, send success).
  - `.selection` on CTA button press.
  - No haptics on high-frequency interactions (scroll, tab tap, list scroll).
  - All haptics centralised inside `FireMotionEffects.swift`. Views never call `UIFeedbackGenerator` or `.sensoryFeedback` directly.

### Testing

- Pure-logic unit tests for `FireMotionTokens`: when `reduceMotion == true`, returned durations are zero, returned transitions are `.identity`-equivalent.
- Pure-logic unit tests for any custom `Transition` math (progress 0 → identity-like, progress 1 → terminal state).
- No view-layer animation snapshot or UI tests (those are integration territory and out of scope per the test policy in Track A).

### Risk

- **iOS 18 vs 17 API split**: `navigationTransition(.zoom)` is iOS 18+. Project deployment target is iOS 17.0, so the iOS 17 fallback through `.firePush` must remain functional. Both paths sit at the same call site behind `if #available(iOS 18, *)`.
- **ReduceMotion gaps**: easy to forget on a one-off site. Concentrating motion in `FireMotion` reduces audit surface. PR review checks every new motion modifier flows through `FireMotion`.
- **ConfettiSwiftUI maintenance**: low-frequency dependency on a single-author MIT package. If abandoned, ~50 lines of in-repo SwiftUI confetti can replace it; not a current blocker.
- **Performance**: `phaseAnimator` and `keyframeAnimator` can be expensive in long lists. Tokens stay conservative (≤ 250 ms). T1 effects target individual rows, not whole lists.

## Cross-cutting

### Implementation order

A → B → C, each as its own plan and PR cycle:

1. **A** lands first. Ships a clean CI baseline so B and C have unambiguous test signal.
2. **B** lands second. Small, surgical, no UI surface area.
3. **C** lands last. Largest. Itself may split into sub-PRs along T1 / T2 / T3 inside its plan.

### Out of scope

- Renaming the `FireTests` target.
- Tab switch animation (system `TabView` retained as-is).
- Pow library integration (license + derivative-work concerns).
- Lottie integration.
- T4 (loading skeletons) and T5 (onboarding/launch) animation tiers — separate future spec.
- Android side of any of the above (this is iOS-only; Android has its own animation/test stories).
- Any new view code beyond what is needed to apply `FireMotion` modifiers at the listed surfaces.
