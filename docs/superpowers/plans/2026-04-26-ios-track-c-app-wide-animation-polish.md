# iOS Track C — App-Wide Animation Polish Implementation Plan

> **For agentic workers:** Follow `docs/superpowers/plans/2026-04-28-ios-quality-and-polish-orchestration.md` for subagent roles, `manage_todo_list` tracking, artifact bundling, commit ownership, and the unified-PR rule. Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Treat the checkboxes here as execution notes only.

**Goal:** Add motion polish across three layers — interaction micro-feedback (T1), numeric/badge transitions (T2), navigation/list/sheet transitions (T3) — through a centralised `FireMotion` module built on iOS 17+ native SwiftUI APIs, with `accessibilityReduceMotion` honoured at every entry point.

**Architecture:** New `FireMotion/` folder under `App/` providing four files: `FireMotionTokens.swift` (timing constants, reduce-motion guard), `FireMotionTransitions.swift` (custom `Transition` types: `firePush`, `fireListItem`, plus `fireSheet` helper), `FireMotionEffects.swift` (semantic `ViewModifier`s: `.fireLikeEffect`, `.fireBookmarkEffect`, `.fireFollowEffect`, `.fireSuccessFeedback`, `.fireBadgePulse`, `.fireNumericChange`, `.fireCTAPress`, `.fireSwipeReplyFeedback`, plus `.fireRespectingReduceMotion` confetti gate), and `FireMotionReduceMotion.swift` (environment-aware helpers reused by the other files). Business views call `FireMotion` semantic modifiers, never raw SwiftUI animation APIs for the T1–T3 surfaces. ConfettiSwiftUI is added as a third-party dependency, used only at celebration moments.

**Tech Stack:** SwiftUI iOS 17+ APIs (`symbolEffect`, `contentTransition`, `sensoryFeedback`, `Transition` protocol, `phaseAnimator`); iOS 18+ (`navigationTransition(.zoom)`) gated behind `if #available(iOS 18, *)`; `ConfettiSwiftUI` (MIT, pinned); XCTest.

---

## Spec reference

Track C in `docs/superpowers/specs/ios-quality-and-polish-design.md` (lines 116–193). See "Goal", "Architecture", "T1 / T2 / T3", "Third-party", "Reduce Motion / Haptics", "Testing", "Risk", and "Cross-cutting".

## Execution slices

Track C is organised into **four phases**. Each phase ends with a working build, a passing test suite, and one phase-sized commit if VCS ownership is assigned to the slice. Phase PRs are intentionally out of scope for this execution; the main agent opens one unified PR only after Tracks A, B, and C are complete.

- **Phase 1 — Foundation** (Tasks 1–4): the `FireMotion` module, ConfettiSwiftUI dependency pin, reduce-motion-aware tokens, and tokens unit tests. **Ships nothing user-visible** but is required for Phases 2–4.
- **Phase 2 — T1 interaction micro-feedback** (Tasks 5–8): like, bookmark, follow, mark-read, badge, CTA, celebration.
- **Phase 3 — T2 numeric and badge transitions** (Tasks 9–10): unread count, like/view/post/follower counts, profile skeleton → loaded swap.
- **Phase 4 — T3 navigation, sheet, list transitions** (Tasks 11–13): NavigationStack zoom/push, sheet spring config, list insert/delete.

Always run Phase 1 first. After Phase 1 is available in the working branch, later phases remain separate review units even if they are executed back-to-back. If a later phase rebases over another active slice, re-run that phase's validation set before handoff.

## File map

- **Create**:
  - `native/ios-app/App/FireMotion/FireMotionTokens.swift`
  - `native/ios-app/App/FireMotion/FireMotionReduceMotion.swift`
  - `native/ios-app/App/FireMotion/FireMotionTransitions.swift`
  - `native/ios-app/App/FireMotion/FireMotionEffects.swift`
  - `native/ios-app/Tests/Unit/FireMotionTokensTests.swift`
- **Modify**:
  - `native/ios-app/project.yml` — add `ConfettiSwiftUI` to `packages:`, add `package: ConfettiSwiftUI` to the `Fire` target's `dependencies:`.
    - `native/ios-app/App/FireTopicDetailView.swift` — apply `.fireLikeEffect`, `.fireBookmarkEffect`, `.fireSuccessFeedback`, `.fireNumericChange` (post like/reaction count) and replace the raw `UIImpactFeedbackGenerator(style: .medium).impactOccurred()` at line 1932 with `.fireSwipeReplyFeedback(trigger:)` through the module.
  - `native/ios-app/App/FirePublicProfileView.swift` — `.fireFollowEffect`, `.fireSuccessFeedback`, follow milestone confetti.
  - `native/ios-app/App/FireNotificationsView.swift` — `.transition(.fireListItem)` on rows, `.fireBadgePulse` on the unread Text badge surface.
  - `native/ios-app/App/FireNotificationHistoryView.swift` — `.transition(.fireListItem)` on rows.
  - `native/ios-app/App/FireBookmarksView.swift` — `.fireSheet()` on the editor sheet at `:203`.
  - `native/ios-app/App/FireBookmarkEditorSheet.swift` — `.fireCTAPress()` on the primary save button (and align the existing `Toggle` `.animation(.easeInOut)` to `FireMotionTokens`).
  - `native/ios-app/App/FireTagPickerSheet.swift` — `.fireSheet()`.
  - `native/ios-app/App/FireComposerView.swift` — `.fireSheet()` on category sheet `:571`, `.fireCTAPress()` on the composer submit button.
  - `native/ios-app/App/FireHomeView.swift` — `.fireSheet()` on `:68`/`:71`, NavigationStack zoom transition wrapper for topic detail push.
  - `native/ios-app/App/FireFilteredTopicListView.swift` — same zoom-or-firePush wrapper at the navigationDestination call site.
  - `native/ios-app/App/FireProfileView.swift` — `.transition(.opacity.combined(with: .scale(scale: 0.98)))` on the skeleton → data swap; numeric counts via `.fireNumericChange`.
  - `native/ios-app/App/FireProfileStatsRow.swift` — replace the raw `.contentTransition(.numericText())` at `:19` with `.fireNumericChange(value:)` to centralise.
  - `native/ios-app/App/FireComponents.swift` — replace the raw `.contentTransition(.numericText())` at `:259` with `.fireNumericChange(value:)`.
  - `native/ios-app/App/FireTopicRow.swift` — `.fireNumericChange(value:)` for the like-count Text.
  - `native/ios-app/App/FireSearchView.swift` — `.fireNumericChange(value:)` for the like-count Text on `:404-405`.
  - `native/ios-app/App/FireTabRoot.swift` — (Phase 2) call `FireMotionCelebrationGate.reset()` inside the existing logout reset at `:132-146`. (Phase 4) replace the raw `.animation(.easeInOut(duration: 0.3), value: isAuthenticated)` at `:70` with the centralised `.fireRespectingReduceMotion(...)` modifier so the auth-gate cross-fade also honours the accessibility setting.
- **Regenerate**:
  - `native/ios-app/Fire.xcodeproj/project.pbxproj` — `xcodegen generate` after `project.yml` and after each new source file is added under `App/FireMotion/` and `Tests/Unit/`.

The `App/FireMotion/` folder is recursive under the existing `App/` source root in `project.yml`, so individual file additions inside it do not require a separate `project.yml` edit (only the package dep does).

---

# Phase 1 — Foundation

## Task 1: Add ConfettiSwiftUI as a pinned package dependency

**Files:**
- Modify: `native/ios-app/project.yml`

- [ ] **Step 1: Look up the current ConfettiSwiftUI exact version**

Open https://github.com/simibac/ConfettiSwiftUI/tags in a browser and note the highest stable tag (e.g. `2.0.4`, `2.0.5`, etc.). Use that exact tag string in Step 2 in place of `<exact-tag>`.

This step exists because the spec mandates `exactVersion` pinning (mirroring the `CrashReporter` style) and the version churns between when this plan was written and when it is executed; resolving it at execution time avoids landing a stale pin.

- [ ] **Step 2: Add the package and dependency to `project.yml`**

In `native/ios-app/project.yml`, in the `packages:` block (currently lines 4–6), add a second entry directly below `CrashReporter`:

```yaml
packages:
  CrashReporter:
    url: https://github.com/microsoft/plcrashreporter.git
    exactVersion: 1.12.2
  ConfettiSwiftUI:
    url: https://github.com/simibac/ConfettiSwiftUI.git
    exactVersion: <exact-tag>
```

In the `Fire` target's `dependencies:` list (currently lines 70–76), add the package consumption directly below the existing `package: CrashReporter` entry:

```yaml
    dependencies:
      - sdk: Security.framework
      - sdk: Foundation.framework
      - sdk: CoreFoundation.framework
      - sdk: libiconv.tbd
      - package: CrashReporter
        product: CrashReporter
      - package: ConfettiSwiftUI
        product: ConfettiSwiftUI
```

- [ ] **Step 3: Regenerate the Xcode project and resolve the new package**

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  -resolvePackageDependencies \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `Resolve Package Graph` step lists `ConfettiSwiftUI` resolved at the pinned version. `Fire.xcodeproj/project.pbxproj` gains the package reference.

- [ ] **Step 4: Confirm the app target still builds without referencing the package yet**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. We add the import in Task 4.

---

## Task 2: Create the reduce-motion guard helpers

**Files:**
- Create: `native/ios-app/App/FireMotion/FireMotionReduceMotion.swift`

- [ ] **Step 1: Write the file**

Create `native/ios-app/App/FireMotion/FireMotionReduceMotion.swift`:

```swift
import SwiftUI

/// Runs `body` only when the user has *not* opted into Reduce Motion. Use
/// at sites where suppression is the right behavior (confetti,
/// non-essential decorative motion). For sites where motion should
/// degrade rather than be skipped entirely, use the duration / transition
/// helpers in `FireMotionTokens` instead.
@MainActor
@discardableResult
func fireRespectingReduceMotion<Result>(
    _ reduceMotion: Bool,
    _ body: () -> Result
) -> Result? {
    guard !reduceMotion else {
        return nil
    }
    return body()
}

extension View {
    /// Reads the current Reduce Motion preference and feeds it to a
    /// caller-supplied builder. Lets call sites compose conditional motion
    /// without scattering `@Environment(\.accessibilityReduceMotion)`
    /// reads across every view.
    func fireRespectingReduceMotion<ModifiedContent: View>(
        @ViewBuilder transform: @escaping (Self, _ reduceMotion: Bool) -> ModifiedContent
    ) -> some View {
        FireMotionReduceMotionWrapper(content: self, transform: transform)
    }
}

private struct FireMotionReduceMotionWrapper<Content: View, ModifiedContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: Content
    let transform: (Content, Bool) -> ModifiedContent

    var body: some View {
        transform(content, reduceMotion)
    }
}
```

- [ ] **Step 2: Regenerate and build**

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 3: Create the motion tokens

**Files:**
- Create: `native/ios-app/App/FireMotion/FireMotionTokens.swift`

- [ ] **Step 1: Write the tokens file**

Create `native/ios-app/App/FireMotion/FireMotionTokens.swift`:

```swift
import SwiftUI

/// Centralised motion timing/spring/haptic constants. All durations and
/// spring configs flow through here so app-wide tuning is a single edit.
///
/// Every `duration(for:reduceMotion:)` accessor zeros out under Reduce
/// Motion. Spring response/damping pairs likewise collapse to a stiff,
/// near-instant config under Reduce Motion so motion-driven layout
/// changes still settle without animation.
@MainActor
enum FireMotionTokens {
    enum Duration {
        /// Tactile micro-feedback (button press, badge pulse).
        case tap
        /// Symbol replacement / number flip / standard list-row transition.
        case standard
        /// NavigationStack push fallback on iOS 17.
        case navPush
    }

    enum Spring {
        /// Sheet presentation tuning (slightly softer than system default).
        case sheet
        /// Generic interactive element spring (CTA press, list reorder).
        case interactive
    }

    static let tapDuration: Double = 0.18
    static let standardDuration: Double = 0.22
    static let navPushDuration: Double = 0.25

    static let sheetResponse: Double = 0.34
    static let sheetDamping: Double = 0.78
    static let interactiveResponse: Double = 0.30
    static let interactiveDamping: Double = 0.72

    static func duration(for kind: Duration, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        switch kind {
        case .tap: return tapDuration
        case .standard: return standardDuration
        case .navPush: return navPushDuration
        }
    }

    static func animation(for kind: Duration, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .easeInOut(duration: duration(for: kind, reduceMotion: false))
    }

    static func spring(for kind: Spring, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        switch kind {
        case .sheet:
            return .spring(response: sheetResponse, dampingFraction: sheetDamping)
        case .interactive:
            return .spring(response: interactiveResponse, dampingFraction: interactiveDamping)
        }
    }
}
```

- [ ] **Step 2: Build to confirm the tokens file compiles**

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 4: Create the transitions/effects modules and the foundation unit tests

**Files:**
- Create: `native/ios-app/App/FireMotion/FireMotionTransitions.swift`
- Create: `native/ios-app/App/FireMotion/FireMotionEffects.swift`
- Create: `native/ios-app/Tests/Unit/FireMotionTokensTests.swift`

- [ ] **Step 1: Create `FireMotionTransitions.swift`**

```swift
import SwiftUI

extension AnyTransition {
    /// NavigationStack push fallback for iOS 17 (when `.zoom` is not
    /// available). Slide from trailing + fade + mild scale at insertion;
    /// reverse on removal. Reduce Motion: degrades to opacity only.
    static func firePush(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion = AnyTransition.move(edge: .trailing)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.98))
        let removal = AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: removal)
    }

    /// Insert/delete transition for list rows. Slide from leading +
    /// opacity. Reduce Motion: opacity only.
    static func fireListItem(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition.move(edge: .leading)
            .combined(with: .opacity)
    }
}

extension View {
    /// Centralised sheet spring tuning. Apply to the sheet's *content*
    /// view so the implicit animation driving its presentation picks up
    /// the spring config. Sheet detents and drag indicators are left to
    /// the call site.
    func fireSheet() -> some View {
        modifier(FireSheetSpringModifier())
    }
}

private struct FireSheetSpringModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            transaction.animation = FireMotionTokens.spring(
                for: .sheet,
                reduceMotion: reduceMotion
            )
        }
    }
}
```

Keep `firePush` and `fireListItem` as direct `AnyTransition` compositions in this phase. Do not add standalone progress-interpolation math unless execution genuinely needs it; if a custom math helper becomes necessary, add its pure-logic tests in the same phase before handoff.

- [ ] **Step 2: Create `FireMotionEffects.swift`**

```swift
import SwiftUI
import ConfettiSwiftUI

extension View {
    /// Heart-icon bounce on the active edge of a like toggle, plus a
    /// `.success` haptic when `active` flips to `true`. The view that
    /// owns the icon should pass the bool that drives `heart.fill` vs
    /// `heart`.
    func fireLikeEffect(active: Bool) -> some View {
        modifier(FireSymbolBounceEffect(active: active, hapticOnActivate: .success))
    }

    /// `bookmark.fill` ↔ `bookmark` swap with `symbolEffect(.replace)`
    /// content transition + success haptic on activation.
    func fireBookmarkEffect(active: Bool) -> some View {
        modifier(FireSymbolReplaceEffect(active: active, hapticOnActivate: .success))
    }

    /// Follow button bounce + success haptic when `active` flips true.
    func fireFollowEffect(active: Bool) -> some View {
        modifier(FireSymbolBounceEffect(active: active, hapticOnActivate: .success))
    }

    /// Generic success haptic on the rising edge of `trigger`. Use at
    /// confirmed-positive moments (send success, save success). Skipped
    /// under Reduce Motion's haptics counterpart isn't a thing — Reduce
    /// Motion does not silence haptics — so this fires regardless.
    func fireSuccessFeedback(trigger: some Equatable) -> some View {
        sensoryFeedback(.success, trigger: trigger)
    }

    /// Non-repeating pulse on a notification badge symbol on every
    /// incoming `value` change. Suppressed under Reduce Motion.
    func fireBadgePulse(value: some Equatable) -> some View {
        modifier(FireBadgePulseEffect(value: AnyHashable(value)))
    }

    /// Numeric content transition for digit-flip on a `Text` view. Use
    /// for like/view/post/follower counts, unread badge counts, etc.
    func fireNumericChange(value: some Equatable) -> some View {
        modifier(FireNumericChangeEffect(value: AnyHashable(value)))
    }

    /// Primary CTA press: scale to ~0.97 on press + `.selection`
    /// haptic. Apply to the outermost button label.
    func fireCTAPress() -> some View {
        modifier(FireCTAPressEffect())
    }

    /// Centralised swipe-to-reply impact feedback. The gesture host owns
    /// the trigger pulse; FireMotion owns the haptic implementation.
    func fireSwipeReplyFeedback(trigger: some Equatable) -> some View {
        modifier(FireSwipeReplyFeedbackEffect(trigger: AnyHashable(trigger)))
    }

    /// Confetti burst gated by Reduce Motion. `trigger` is a
    /// monotonically incrementing `Int` (or any `BinaryInteger`) — bumping
    /// it once fires one celebration. Use for first-follow milestones,
    /// badge unlocks, etc. Never on per-tap interactions.
    func fireCelebrationConfetti(trigger: Binding<Int>) -> some View {
        modifier(FireCelebrationConfettiEffect(trigger: trigger))
    }
}

// MARK: - Concrete modifiers

private struct FireSymbolBounceEffect: ViewModifier {
    let active: Bool
    let hapticOnActivate: SensoryFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content
            } else {
                content.symbolEffect(.bounce, value: active)
            }
        }
        // Spec: ".sensoryFeedback(.success) on success" for like/bookmark/follow
        // toggles. The haptic must fire on both activation and deactivation
        // (every confirmed state flip), so trigger on the raw `active` value.
        .sensoryFeedback(hapticOnActivate, trigger: active)
    }
}

private struct FireSymbolReplaceEffect: ViewModifier {
    let active: Bool
    let hapticOnActivate: SensoryFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        Group {
            if reduceMotion {
                content
            } else {
                content.contentTransition(.symbolEffect(.replace))
            }
        }
        .sensoryFeedback(hapticOnActivate, trigger: active)
    }
}

private struct FireBadgePulseEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.pulse, options: .nonRepeating, value: value)
        }
    }
}

private struct FireNumericChangeEffect: ViewModifier {
    let value: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: value
            )
    }
}

private struct FireCTAPressEffect: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1.0)
            .animation(
                FireMotionTokens.animation(for: .tap, reduceMotion: reduceMotion),
                value: isPressed
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
            .sensoryFeedback(.selection, trigger: isPressed) { _, newValue in
                newValue
            }
    }
}

private struct FireCelebrationConfettiEffect: ViewModifier {
    @Binding var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.confettiCannon(trigger: $trigger, num: reduceMotion ? 0 : 36)
    }
}

private struct FireSwipeReplyFeedbackEffect: ViewModifier {
    let trigger: AnyHashable

    func body(content: Content) -> some View {
        content.sensoryFeedback(.impact(weight: .medium), trigger: trigger)
    }
}
```

- [ ] **Step 3: Create the tokens unit tests**

Create `native/ios-app/Tests/Unit/FireMotionTokensTests.swift`:

```swift
import XCTest
@testable import Fire

@MainActor
final class FireMotionTokensTests: XCTestCase {
    func testDurationsZeroOutUnderReduceMotion() {
        XCTAssertEqual(FireMotionTokens.duration(for: .tap, reduceMotion: true), 0)
        XCTAssertEqual(FireMotionTokens.duration(for: .standard, reduceMotion: true), 0)
        XCTAssertEqual(FireMotionTokens.duration(for: .navPush, reduceMotion: true), 0)
    }

    func testDurationsNonZeroAndConservativeWhenReduceMotionOff() {
        let tap = FireMotionTokens.duration(for: .tap, reduceMotion: false)
        let standard = FireMotionTokens.duration(for: .standard, reduceMotion: false)
        let navPush = FireMotionTokens.duration(for: .navPush, reduceMotion: false)

        XCTAssertGreaterThan(tap, 0)
        XCTAssertGreaterThan(standard, 0)
        XCTAssertGreaterThan(navPush, 0)
        // Spec: "Tokens stay conservative (≤ 250 ms)." Keep all three
        // durations at or under that ceiling.
        XCTAssertLessThanOrEqual(tap, 0.25)
        XCTAssertLessThanOrEqual(standard, 0.25)
        XCTAssertLessThanOrEqual(navPush, 0.25)
    }

    func testRespectingReduceMotionGuardSkipsBodyWhenSet() {
        var ran = false
        _ = fireRespectingReduceMotion(true) {
            ran = true
            return 1
        }
        XCTAssertFalse(ran, "body must not run when reduceMotion is true")
    }

    func testRespectingReduceMotionGuardRunsBodyWhenUnset() {
        var ran = false
        let result = fireRespectingReduceMotion(false) {
            ran = true
            return 42
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(result, 42)
    }
}
```

Because `firePush` and `fireListItem` remain direct `AnyTransition` compositions here, there is no separate transition-math helper to unit-test in Phase 1. If execution extracts custom interpolation logic later, add a matching `FireMotionTransitionsTests` file in the same slice.

- [ ] **Step 4: Regenerate the Xcode project, run the tests**

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  -only-testing:FireTests/FireMotionTokensTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`. Four cases pass.

- [ ] **Step 5: Commit Phase 1**

```bash
git add native/ios-app/App/FireMotion \
        native/ios-app/Tests/Unit/FireMotionTokensTests.swift \
        native/ios-app/project.yml \
        native/ios-app/Fire.xcodeproj

git commit -m "$(cat <<'EOF'
feat(ios/motion): add FireMotion module foundation (Track C / Phase 1)

Introduces App/FireMotion with tokens, transitions, effects, and a
reduce-motion guard. Adds ConfettiSwiftUI as a pinned dependency,
imported only inside FireMotionEffects so non-celebration views never
see the symbol. Tokens unit tests cover the reduce-motion zero-out
contract and confirm the conservative ≤ 250 ms ceiling holds.

No call sites use the new modifiers yet; subsequent phases (T1, T2, T3)
wire them into the topic detail, profile, notifications, list, sheet,
and navigation surfaces.
EOF
)"
```

---

# Phase 2 — T1 interaction micro-feedback

## Task 5: Wire `.fireLikeEffect` and `.fireSuccessFeedback` into post-row likes/reactions

**Files:**
- Modify: `native/ios-app/App/FireMotion/FireMotionEffects.swift` — add the semantic swipe-reply feedback modifier used by the topic-detail gesture container.
- Modify: `native/ios-app/App/FireTopicDetailView.swift` — `FirePostRow` reaction button area at `:1200-1233`, and the swipe-to-reply haptic at `:1932`.

- [ ] **Step 1: Replace the reaction-button heart styling**

Inside the `if !post.reactions.isEmpty` block (currently `:1200-1233`), find the inner `Button { ... } label: { HStack(spacing: 5) { Text(option.symbol); Text("\(reaction.count)") ... } }`. Apply `.fireLikeEffect` to the `Text(option.symbol)` only when `reaction.id == "heart"`, and apply `.fireNumericChange(value: reaction.count)` to the count Text:

```swift
ForEach(post.reactions, id: \.id) { reaction in
    let option = FireTopicPresentation.reactionOption(for: reaction.id)
    Button {
        if reaction.id == "heart" {
            onToggleLike(post)
        } else {
            onSelectReaction(post, reaction.id)
        }
    } label: {
        HStack(spacing: 5) {
            Text(option.symbol)
                .fireLikeEffect(
                    active: reaction.id == "heart"
                        && post.currentUserReaction?.id == "heart"
                )
            Text("\(reaction.count)")
                .font(.caption.monospacedDigit())
                .fireNumericChange(value: reaction.count)
        }
        .padding(.horizontal, 10)
        // ... existing background / capsule styling unchanged
```

The `active:` predicate passes `true` only when this is the heart reaction *and* the current user has it set, so the bounce only fires for the user's own like state. Non-heart reactions still pulse via the count `fireNumericChange`.

- [ ] **Step 2: Confirm no double haptic from the like path**

`.fireLikeEffect(active:)` already includes a `.success` haptic that fires on every flip of the `active` parameter (see `FireSymbolBounceEffect` in `FireMotionEffects.swift`). Do **not** chain an additional `.fireSuccessFeedback(trigger:)` to the same row — that would double-haptic on every like/unlike.

Use `.fireSuccessFeedback(trigger:)` only at sites that are NOT already covered by the `.fireLikeEffect` / `.fireBookmarkEffect` / `.fireFollowEffect` modifiers. The spec lists those three as the toggle haptic sources; everything else (e.g. composer-send-success in Task 8) uses `.fireSuccessFeedback` directly.

No code change in this step — this is a deliberate "do not add the extra modifier" check.

- [ ] **Step 3: Replace the raw swipe-to-reply haptic with the centralised module**

In `FireSwipeToReplyContainer.swipeGesture` (`:1907-1944`), the line `:1932` is:

```swift
UIImpactFeedbackGenerator(style: .medium).impactOccurred()
```

Replace it with a state-driven pulse and route the haptic through `FireMotionEffects.swift`. Concretely:

1. Add a `@State private var swipeReplyTriggerPulse = 0` to `FireSwipeToReplyContainer`.
2. In `.onChanged`, where the original code sets `replyTriggered = true` and calls `UIImpactFeedbackGenerator(...).impactOccurred()`, replace the latter with `swipeReplyTriggerPulse += 1`.
3. Add `fireSwipeReplyFeedback(trigger:)` to `FireMotionEffects.swift`; it owns the `.sensoryFeedback(.impact(weight: .medium), trigger:)` implementation so views still call a semantic FireMotion API.
4. On the outer container, add `.fireSwipeReplyFeedback(trigger: swipeReplyTriggerPulse)`.

Rationale: per the spec, "All haptics centralised inside `FireMotionEffects.swift`. Views never call `UIFeedbackGenerator` ... directly." The swipe-trigger is the only direct `UIImpactFeedbackGenerator` left in the codebase (verified via `grep -n "UIFeedbackGenerator\|UIImpactFeedback" native/ios-app/App/`).

- [ ] **Step 4: Build and confirm no regression**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Verify no `UIFeedbackGenerator` direct usage remains**

```bash
grep -rn "UIFeedbackGenerator\|UIImpactFeedback\|UISelectionFeedback\|UINotificationFeedback" native/ios-app/App/
```

Expected: no matches.

---

## Task 6: Wire `.fireBookmarkEffect` and `.fireFollowEffect`

**Files:**
- Modify: `native/ios-app/App/FireTopicDetailView.swift` — bookmark menu Label at `:341-345`.
- Modify: `native/ios-app/App/FirePublicProfileView.swift` — follow Button at `:283-302`.
- Modify: `native/ios-app/App/FireProfileView.swift` — `bookmark.fill` shortcut row Label at `:127`.

- [ ] **Step 1: Apply `.fireBookmarkEffect` to the topic-detail bookmark menu Label**

In `FireTopicDetailView.swift`, the bookmark menu item currently reads (`:341-345`):

```swift
Label(
    detail?.bookmarked == true ? "编辑书签" : "添加书签",
    systemImage: detail?.bookmarked == true ? "bookmark.fill" : "bookmark"
)
```

Wrap with `.fireBookmarkEffect`:

```swift
Label(
    detail?.bookmarked == true ? "编辑书签" : "添加书签",
    systemImage: detail?.bookmarked == true ? "bookmark.fill" : "bookmark"
)
.fireBookmarkEffect(active: detail?.bookmarked == true)
```

- [ ] **Step 2: Apply `.fireFollowEffect` to the public profile follow Button**

In `FirePublicProfileView.swift` `:282-303` (the follow Button), wrap the inner `HStack(spacing: 8) { ... }` label with `.fireFollowEffect(active:)`:

```swift
Button {
    Task { await toggleFollow() }
} label: {
    HStack(spacing: 8) {
        if isUpdatingFollow {
            ProgressView().controlSize(.small)
        }
        Text(profileViewModel.profile?.isFollowed == true ? "取消关注" : "关注")
            .font(.caption.weight(.semibold))
    }
    .foregroundStyle(profileViewModel.profile?.isFollowed == true ? FireTheme.subtleInk : .white)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(
        (profileViewModel.profile?.isFollowed == true ? FireTheme.softSurface : FireTheme.accent),
        in: Capsule()
    )
    .fireFollowEffect(active: profileViewModel.profile?.isFollowed == true)
}
.buttonStyle(.plain)
.disabled(isUpdatingFollow)
.fireCTAPress()
```

`.fireCTAPress()` on the outer Button delivers the press scale + selection haptic per spec ("Primary CTAs"); `.fireFollowEffect(active:)` on the label delivers the bounce + success haptic on follow-state change.

- [ ] **Step 3: Apply `.fireBookmarkEffect` to the profile shortcut bookmark icon**

In `FireProfileView.swift:122-132`, the bookmark shortcut row uses a static `bookmark.fill` icon. Since this surface does not toggle, no `active` state changes — apply `.fireBookmarkEffect(active: true)` only if a future toggle is added. **Skip for now**; this is a navigation entry point, not a toggle. Proceed to Step 4.

- [ ] **Step 4: Build to confirm wiring compiles**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 7: Wire mark-read row fade + badge pulse + CTA press

**Files:**
- Modify: `native/ios-app/App/FireNotificationsView.swift` — list row at `:273-278`, badge at `:217`, mark-all Button at `:218-224`.
- Modify: `native/ios-app/App/FireNotificationHistoryView.swift` — mirror the row fade for the full notifications list (look up the corresponding `ForEach` site).

- [ ] **Step 1: Apply `.transition(.fireListItem)` to notification rows**

In `FireNotificationsView.swift:273-278`, the notification `ForEach` row block reads:

```swift
ForEach(notificationStore.recentNotifications, id: \.id) { item in
    notificationRow(item)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
}
```

Wrap rows with the centralised list-item transition. Because `Transition` modifiers depend on the parent applying an `.animation(...)` on the same value, also add an `.animation(...)` to the `List` based on the row count. The cleanest approach using the module:

```swift
ForEach(notificationStore.recentNotifications, id: \.id) { item in
    notificationRow(item)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .fireRespectingReduceMotion { content, reduceMotion in
            content.transition(.fireListItem(reduceMotion: reduceMotion))
        }
}
```

And, on the `List` directly above (`:257`), add:

```swift
List {
    // ... existing children ...
}
.listStyle(.plain)
.animation(
    FireMotionTokens.animation(for: .standard, reduceMotion: false),
    value: notificationStore.recentNotifications.map(\.id)
)
```

Note: the `value: notificationStore.recentNotifications.map(\.id)` driver makes the animation key off identity changes, which is what triggers the row fade on mark-read.

- [ ] **Step 2: Mirror the same row transition + animation in the full notifications history**

In `FireNotificationHistoryView.swift`, locate the `ForEach(...)` over `notificationStore.fullNotifications` and apply the same `.fireRespectingReduceMotion { content, reduceMotion in content.transition(.fireListItem(reduceMotion: reduceMotion)) }` plus the matching `.animation(... , value: notificationStore.fullNotifications.map(\.id))` on the parent `List`.

If the parent isn't a `List` (it might be a `ScrollView` + `LazyVStack`), add `.transition(...)` to each row and `.animation(...)` to the container above the lazy stack so the implicit animation can drive the transition.

- [ ] **Step 3: Apply `.fireBadgePulse` to the unread-count text in the notifications header**

In `FireNotificationsView.swift:217-224`:

```swift
if notificationStore.unreadCount > 0 {
    ToolbarItem(placement: .topBarTrailing) {
        Button("全部已读") {
            notificationStore.markAllRead()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(FireTheme.accent)
    }
}
```

The toolbar Button itself does not show a number. The unread-count *number* surface in this view is exposed via `FireTabRoot.swift:50` `.badge(notificationStore.unreadCount)` on the `FireNotificationsView` tab item. **`.badge(...)` on a `tabItem` is a system view and does not accept a `.contentTransition` modifier**, so we cannot `fireNumericChange` it. Instead:

1. Apply `.fireCTAPress()` to the toolbar Button so the "全部已读" press still gets selection haptic + scale feedback.
2. Add a `.fireBadgePulse(value: notificationStore.unreadCount)` to a Text view *inside* the row that displays unread state per row (the read-dot or unread label) — search for the spot within `notificationRowContent` in `FireNotificationRowContent` (in `FireNotificationsView.swift`); it likely shows an unread indicator dot. Apply `.fireBadgePulse` there only if the indicator is an SF Symbol; otherwise skip.
3. Document in the commit message that the system tab badge is intentionally untouched.

Concrete edit for the toolbar button:

```swift
Button("全部已读") {
    notificationStore.markAllRead()
}
.font(.subheadline.weight(.medium))
.foregroundStyle(FireTheme.accent)
.fireCTAPress()
```

- [ ] **Step 4: Build**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 8: Apply `.fireCTAPress` to remaining primary CTAs and add the celebration confetti

**Files:**
- Modify: `native/ios-app/App/FireBookmarkEditorSheet.swift` — primary save button.
- Modify: `native/ios-app/App/FireComposerView.swift` — composer submit button.
- Modify: `native/ios-app/App/FirePostEditorView.swift` — post editor save button.
- Modify: `native/ios-app/App/FirePublicProfileView.swift` — celebration confetti on first follow.

- [ ] **Step 1: Apply `.fireCTAPress` to the bookmark editor primary save button**

Locate the Save / "完成" / "保存" Button in `FireBookmarkEditorSheet.swift` (search for `Button` near the toolbar items at the end of the file). Add `.fireCTAPress()` and `.fireSuccessFeedback(trigger:)` chained to the button. Use the local "save succeeded" published flag as the trigger.

If no such "save succeeded" boolean exists, add an `@State private var saveCompletionPulse: Int = 0`, increment it inside the Save button's success path, and feed the pulse to `.fireSuccessFeedback(trigger: saveCompletionPulse)`.

- [ ] **Step 2: Apply `.fireCTAPress` to the composer submit button**

In `FireComposerView.swift`, locate the primary submit / "发送" / "发布" button (search the file for `Button` near the end of the body). Apply `.fireCTAPress()`. Use the same success-pulse pattern as Step 1 to fire `.fireSuccessFeedback` on submit success.

- [ ] **Step 3: Apply `.fireCTAPress` to the post editor save button**

Same pattern in `FirePostEditorView.swift`.

- [ ] **Step 4a: Add a one-shot celebration gate to the FireMotion module**

Append to `native/ios-app/App/FireMotion/FireMotionEffects.swift` (after the existing modifiers):

```swift
/// One-shot per-session gates for celebration confetti. Static state is
/// fine here because the gates are inherently process-scoped: a relaunch
/// resets them implicitly, which matches the "rare, surprising moment"
/// intent. Logout calls `reset()` so a re-login user still gets a
/// fresh celebration.
@MainActor
enum FireMotionCelebrationGate {
    private static var firstFollowFiredThisSession = false

    /// Returns `true` the first time it is called in this process, then
    /// `false` for every subsequent call until `reset()` is invoked.
    static func consumeFirstFollow() -> Bool {
        guard !firstFollowFiredThisSession else { return false }
        firstFollowFiredThisSession = true
        return true
    }

    static func reset() {
        firstFollowFiredThisSession = false
    }
}
```

- [ ] **Step 4b: Reset the gate on logout**

In `FireTabRoot.swift` `.onChange(of: isAuthenticated)` at `:132-146`, the existing reset block calls `homeFeedStore.reset()`, `searchStore.reset()`, etc. Add the gate reset alongside:

```swift
.onChange(of: isAuthenticated) { _, authenticated in
    if !authenticated {
        homeFeedStore.reset()
        searchStore.reset()
        notificationStore.reset()
        topicDetailStore.reset()
        FireMotionCelebrationGate.reset()
    }
    // ... rest unchanged
}
```

- [ ] **Step 4c: Wire the celebration into the follow toggle**

In `FirePublicProfileView.swift`:

1. Add `@State private var celebrationPulse: Int = 0` to the view's properties.
2. In `toggleFollow()` at `:498-513`, after the successful `try await viewModel.followUser(username: username)` path (the *follow* branch, not the unfollow branch), check whether this is a fresh activation and consume the gate:
   ```swift
   do {
       if profileViewModel.profile?.isFollowed == true {
           try await viewModel.unfollowUser(username: username)
       } else {
           try await viewModel.followUser(username: username)
           if FireMotionCelebrationGate.consumeFirstFollow() {
               celebrationPulse += 1
           }
       }
       await profileViewModel.refreshAll()
   } catch {
       profileViewModel.errorMessage = error.localizedDescription
   }
   ```
3. On the outermost view of `FirePublicProfileView.body`, add `.fireCelebrationConfetti(trigger: $celebrationPulse)`.

The Reduce Motion gate is built into `.fireCelebrationConfetti` (it passes `num: 0` when reduce-motion is on, suppressing the burst entirely).

- [ ] **Step 4d: Badge-unlock celebration decision gate**

The spec lists "badge unlock" as a second celebration moment alongside first follow. The current codebase (`FireMyBadgesView.swift`, `FireBadgeDetailView.swift`) treats badges as a browse-and-display surface, not an event surface — there is no obvious in-app moment where the app says "you just unlocked X."

Use Explore + Analyze to answer one question before closing Phase 2: is there already a low-risk badge-unlock event surface that can fire `.fireCelebrationConfetti` without inventing a new state-diff subsystem?

- If **yes**, wire that surface in this phase and include it in the validation lap.
- If **no**, stop and use `vscode_askQuestions` through the orchestration flow to ask whether to add badge-diff detection in Track C or carve badge-unlock celebration into a follow-up spec.

Record the outcome in the Phase 2 artifact bundle so the unresolved scope does not disappear between handoffs.

- [ ] **Step 5: Build and verify**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Run the unit suite to catch regressions**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Manual smoke test in Simulator**

1. Like a post → heart icon bounces, success haptic plays, count flips with numeric transition.
2. Tap the same heart again to unlike → bounce reverses, success haptic plays again, count flips down.
3. Add a topic to bookmarks → bookmark icon swaps `bookmark` ↔ `bookmark.fill` via symbol-replace transition.
4. Follow a user (one you have not followed before in this session) → bounce on the button + a one-shot confetti burst from the top of the profile view.
5. Follow a *second* user in the same session → bounce + haptic, but **no confetti** (first-follow milestone was already used).
6. Toggle Settings → Accessibility → Motion → Reduce Motion = ON. Repeat 1–5 — bounces are absent, count Text changes are instant, no confetti. Haptics still play.
7. Run `grep -rn "UIFeedbackGenerator\|UIImpactFeedback" native/ios-app/App/` once more — should be empty.

- [ ] **Step 8: Commit Phase 2**

```bash
git add native/ios-app/App/FireMotion \
        native/ios-app/App/FireTopicDetailView.swift \
        native/ios-app/App/FirePublicProfileView.swift \
        native/ios-app/App/FireNotificationsView.swift \
        native/ios-app/App/FireNotificationHistoryView.swift \
        native/ios-app/App/FireBookmarkEditorSheet.swift \
        native/ios-app/App/FireComposerView.swift \
        native/ios-app/App/FirePostEditorView.swift \
        native/ios-app/App/FireTabRoot.swift

git commit -m "$(cat <<'EOF'
feat(ios/motion): T1 interaction micro-feedback (Track C / Phase 2)

Wires the FireMotion module into the like/bookmark/follow toggles,
mark-read flows, and primary CTAs. The system tab badge stays untouched
(SwiftUI .badge does not accept contentTransition); instead, in-view
unread surfaces use fireBadgePulse. Replaces the last raw
UIImpactFeedbackGenerator call site (swipe-to-reply) with the
centralised FireMotion feedback path. First-follow milestones fire one
ConfettiSwiftUI burst per app session through FireMotionCelebrationGate,
which resets on logout via FireTabRoot.

Badge-unlock celebration stays behind the Phase 2 decision gate: use an
existing low-risk unlock surface if one exists; otherwise stop and ask
whether Track C should add badge-diff detection or carve the celebration
into a follow-up spec.
EOF
)"
```

---

# Phase 3 — T2 numeric and badge transitions

## Task 9: Centralise existing `.contentTransition(.numericText())` into `.fireNumericChange`

**Files:**
- Modify: `native/ios-app/App/FireProfileStatsRow.swift:19`
- Modify: `native/ios-app/App/FireComponents.swift:259`
- Modify: `native/ios-app/App/FireTopicRow.swift:82-85` (like-count Text)
- Modify: `native/ios-app/App/FireSearchView.swift:404-405`

- [ ] **Step 1: Replace the raw `.contentTransition(.numericText())` calls with `.fireNumericChange(value:)`**

`FireProfileStatsRow.swift:15-19` currently:

```swift
Text(item.value.value)
    .font(.title3.monospacedDigit().weight(.semibold))
    .foregroundStyle(FireTheme.ink)
    .contentTransition(.numericText())
```

Replace with:

```swift
Text(item.value.value)
    .font(.title3.monospacedDigit().weight(.semibold))
    .foregroundStyle(FireTheme.ink)
    .fireNumericChange(value: item.value.value)
```

`FireComponents.swift:255-259` currently:

```swift
Text(value)
    .font(.title3.monospacedDigit().weight(.semibold))
    .foregroundStyle(valueColor)
    .contentTransition(.numericText())
```

Replace with:

```swift
Text(value)
    .font(.title3.monospacedDigit().weight(.semibold))
    .foregroundStyle(valueColor)
    .fireNumericChange(value: value)
```

- [ ] **Step 2: Apply `.fireNumericChange` to the like-count and view-count Text in topic rows**

In `FireTopicRow.swift:81-85`, the `topicStat(value: row.topic.likeCount, systemImage: "heart", ...)` helper renders the count as a Text inside `topicStat`. Locate the helper definition (likely earlier in the same file) and apply `.fireNumericChange(value:)` to its inner Text. If the helper renders with an integer that often equals zero (which it does — `likeCount`/`viewCount` start at 0), wrap the text-bearing modifier so `value` reflects each numeric tick.

If the helper is defined like:

```swift
private func topicStat(value: UInt32, systemImage: String, alignment: HorizontalAlignment) -> some View {
    Label("\(value)", systemImage: systemImage)
        .font(.caption2)
        // ... other modifiers
}
```

Replace with:

```swift
private func topicStat(value: UInt32, systemImage: String, alignment: HorizontalAlignment) -> some View {
    Label("\(value)", systemImage: systemImage)
        .font(.caption2)
        .fireNumericChange(value: value)
}
```

- [ ] **Step 3: Apply `.fireNumericChange` to the like-count Text in search results**

In `FireSearchView.swift:404-405`:

```swift
if post.likeCount > 0 {
    Label("\(post.likeCount)", systemImage: "heart")
}
```

Add `.fireNumericChange(value: post.likeCount)` to the `Label`:

```swift
if post.likeCount > 0 {
    Label("\(post.likeCount)", systemImage: "heart")
        .fireNumericChange(value: post.likeCount)
}
```

- [ ] **Step 4: Confirm no remaining raw `.contentTransition(.numericText())` calls remain in app sources**

```bash
grep -rn "contentTransition(.numericText" native/ios-app/App/
```

Expected: no matches. (Module-internal use inside `FireMotionEffects.swift` shows up — that's the centralisation target and is expected.)

- [ ] **Step 5: Build**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 10: Profile skeleton → loaded data crossfade and Phase 3 commit

**Files:**
- Modify: `native/ios-app/App/FireProfileView.swift` — profile-header section transition.
- Modify: `native/ios-app/App/FirePublicProfileView.swift` — same pattern at the public profile header.

- [ ] **Step 1: Wrap the loading-vs-loaded branch with a single `.transition`**

In `FireProfileView.swift`, find the section that conditionally renders a skeleton vs the loaded `profileHeader`. The conditional likely looks like:

```swift
if profileViewModel.profile == nil && profileViewModel.isLoadingProfile {
    profileSkeleton
} else {
    profileHeader
}
```

Wrap each branch with the spec's transition and apply an animation to the parent driven by the loaded state:

```swift
Group {
    if profileViewModel.profile == nil && profileViewModel.isLoadingProfile {
        profileSkeleton
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    } else {
        profileHeader
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
.animation(
    FireMotionTokens.animation(for: .standard, reduceMotion: false),
    value: profileViewModel.profile?.username
)
```

If no skeleton/loaded conditional exists in the current file (the screen may always render `profileHeader` and rely on inner conditionals), apply `.transition(.opacity.combined(with: .scale(scale: 0.98)))` to the inner data-bearing children that swap from `nil` to `loaded` state, and add `.animation(...)` to a stable parent.

For Reduce Motion: scale collapses harmlessly under accessibility, so this transition does not need extra gating — but to be safe, also wrap with `.fireRespectingReduceMotion { content, reduceMotion in content.transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))) }`.

- [ ] **Step 2: Mirror in `FirePublicProfileView`**

Same structure applies — find the loading-vs-loaded branch and apply the same `.transition` + `.animation` combo.

- [ ] **Step 3: Build, run unit tests, and commit Phase 3**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit Phase 3**

```bash
git add native/ios-app/App/FireProfileStatsRow.swift \
        native/ios-app/App/FireComponents.swift \
        native/ios-app/App/FireTopicRow.swift \
        native/ios-app/App/FireSearchView.swift \
        native/ios-app/App/FireProfileView.swift \
        native/ios-app/App/FirePublicProfileView.swift

git commit -m "$(cat <<'EOF'
feat(ios/motion): T2 numeric and badge transitions (Track C / Phase 3)

Centralises existing .contentTransition(.numericText()) call sites into
.fireNumericChange so Reduce Motion gating and tuning live in one
place. Adds the same modifier to like-count surfaces in topic rows and
search results, and wires a single opacity+scale crossfade for
profile skeleton → loaded swaps.
EOF
)"
```

---

# Phase 4 — T3 navigation, sheet, list transitions

## Task 11: NavigationStack push transitions (iOS 18 `.zoom`, iOS 17 `.firePush` fallback)

**Files:**
- Modify: `native/ios-app/App/FireHomeView.swift:41-49` — topic detail push.
- Modify: `native/ios-app/App/FireFilteredTopicListView.swift:291` — same pattern.
- Modify: `native/ios-app/App/FireBookmarksView.swift:194` — same pattern.
- Modify: `native/ios-app/App/FireNotificationHistoryView.swift:44` — same pattern.

- [ ] **Step 1: Inspect the existing topic-detail push site to find its source identifier**

In `FireHomeView.swift`, the topic-list rows likely use `NavigationLink { FireTopicDetailView(...) } label: { FireTopicRow(...) }` inside a `ForEach`. The `.zoom(sourceID:in:)` modifier requires a `Namespace.ID` shared between the source row and the detail view. If no `@Namespace` exists on the home view, add one:

```swift
@Namespace private var topicTransitionNamespace
```

On each row's outer container (the source), apply (iOS 18+):

```swift
.matchedTransitionSource(id: row.topic.id, in: topicTransitionNamespace)
```

On the detail destination view, apply:

```swift
.navigationTransition(.zoom(sourceID: row.topic.id, in: topicTransitionNamespace))
```

Both sit behind `if #available(iOS 18, *)` because the deployment target is iOS 17.0 (`project.yml:59`).

- [ ] **Step 2: Build the iOS 17 fallback as a custom modifier**

For iOS 17, there is no `.navigationTransition` API. The fallback per spec is to use `.firePush` as a transition on the destination view inside the navigationDestination:

```swift
.navigationDestination(item: $selectedRoute) { route in
    Group {
        FireAppRouteDestinationView(viewModel: viewModel, route: route)
    }
    .fireRespectingReduceMotion { content, reduceMotion in
        content.transition(.firePush(reduceMotion: reduceMotion))
    }
}
```

Note that NavigationStack's default push is itself a slide; the `.firePush` transition adds an opacity + mild-scale layer on top. Test in Simulator on iOS 17 — if the result is jarring (double-slide), drop the iOS 17 branch entirely and keep system default.

- [ ] **Step 3: Build a small helper modifier to keep the iOS-version split out of every call site**

To avoid copy-pasting the `if #available(iOS 18, *)` everywhere, add to `FireMotion/FireMotionTransitions.swift`:

```swift
extension View {
    /// Apply the iOS 18 zoom navigation transition where available,
    /// falling back to the centralised `.firePush` transition on iOS 17.
    /// Apply this to the destination view inside `.navigationDestination`.
    @ViewBuilder
    func fireNavigationPush<ID: Hashable>(
        sourceID: ID,
        namespace: Namespace.ID
    ) -> some View {
        if #available(iOS 18, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self.fireRespectingReduceMotion { content, reduceMotion in
                content.transition(.firePush(reduceMotion: reduceMotion))
            }
        }
    }
}
```

The matching `.matchedTransitionSource(id:in:)` lives at the call site (the row), guarded by `if #available(iOS 18, *)`.

- [ ] **Step 4: Apply the helper at each push call site**

For `FireHomeView.swift`, `FireFilteredTopicListView.swift:291`, `FireBookmarksView.swift:194`, and `FireNotificationHistoryView.swift:44`, in each case:

1. Add a `@Namespace private var pushTransitionNamespace` to the view.
2. On each `NavigationLink`'s row label or each row inside the list, add (iOS 18 only):
   ```swift
   .matchedTransitionSourceIfAvailable(id: <stable-row-id>, in: pushTransitionNamespace)
   ```
   where `matchedTransitionSourceIfAvailable` is a small extension you add to `FireMotion/FireMotionTransitions.swift`:
   ```swift
   extension View {
       @ViewBuilder
       func matchedTransitionSourceIfAvailable<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
           if #available(iOS 18, *) {
               self.matchedTransitionSource(id: id, in: namespace)
           } else {
               self
           }
       }
   }
   ```
3. Inside the corresponding `.navigationDestination(item:)` closure, on the destination view apply `.fireNavigationPush(sourceID: <same-stable-row-id>, namespace: pushTransitionNamespace)`.

For destinations whose `sourceID` cannot be derived from the route (e.g. category-list push from a button rather than a row), fall back to a fixed string sourceID like `"category-list"` or skip `matchedTransitionSourceIfAvailable` — the iOS 18 zoom degrades gracefully.

- [ ] **Step 5: Build**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

---

## Task 12: Apply `.fireSheet()` to existing sheet presentations

**Files:**
- Modify: `native/ios-app/App/FireBookmarksView.swift:203`
- Modify: `native/ios-app/App/FireBookmarkEditorSheet.swift` — root view of the sheet content.
- Modify: `native/ios-app/App/FireTagPickerSheet.swift:61` — root view of the sheet content.
- Modify: `native/ios-app/App/FireComposerView.swift:571` — root view of the category sheet.
- Modify: `native/ios-app/App/FireHomeView.swift:68-71` — both sheets.
- Modify: `native/ios-app/App/FireTopicDetailView.swift` — sheet at `:376`, `:404`, `:419`, `:435`.

- [ ] **Step 1: For each sheet content view, apply `.fireSheet()` to the root**

Pattern: the call site is

```swift
.sheet(isPresented: $foo) {
    SomeSheetContent(...)
}
```

Modify the `SomeSheetContent`'s outermost body view (e.g. inside `FireBookmarkEditorSheet.body`'s `NavigationStack { ... }` root) by chaining `.fireSheet()`:

```swift
var body: some View {
    NavigationStack {
        Form { ... }
        // ... existing modifiers ...
    }
    .fireSheet()
}
```

For sheet content defined inline at the call site (not a separate type), apply `.fireSheet()` to the inline content's outermost view.

- [ ] **Step 2: Build and confirm sheets still present**

```bash
xcodebuild build \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`. Smoke-test: open the bookmark editor sheet from a topic — the spring should feel slightly softer than the system default. Open the tag picker — same. Toggle Reduce Motion on; sheets present without the spring overshoot (instant).

---

## Task 13: List insert/delete transitions, full-suite verification, and Phase 4 commit

**Files:**
- Modify: `native/ios-app/App/FireProfileActivityTimelineView.swift` — activity row `ForEach`.
- Already covered for notifications in Task 7.

- [ ] **Step 1: Apply `.transition(.fireListItem)` to the profile activity timeline rows**

Locate the `ForEach` over `profileViewModel.actions` inside `FireProfileActivityTimelineView.swift` (the only file matching the activity timeline pattern in `App/`, see `FireProfileActivityTimelineView.swift:72`). Apply:

```swift
ForEach(visibleActions, id: \.id) { action in
    FireProfileActivityRow(action: action)
        .fireRespectingReduceMotion { content, reduceMotion in
            content.transition(.fireListItem(reduceMotion: reduceMotion))
        }
}
```

On the parent container (the `List` or `ScrollView` wrapping the `ForEach`), add an `.animation(...)` keyed off the row identity list:

```swift
.animation(
    FireMotionTokens.animation(for: .standard, reduceMotion: false),
    value: visibleActions.map(\.id)
)
```

- [ ] **Step 2: Update `FireTabRoot.swift` auth-gate animation to flow through the module**

The `.animation(.easeInOut(duration: 0.3), value: isAuthenticated)` at `FireTabRoot.swift:70` is a leftover raw motion API. Replace with:

```swift
.fireRespectingReduceMotion { content, reduceMotion in
    content.animation(
        FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
        value: isAuthenticated
    )
}
```

This brings the last existing app-wide animation site under the module's gate.

- [ ] **Step 3: Audit — no remaining raw motion APIs at T1/T2/T3 surfaces outside the module**

Run, in order:

```bash
# Numeric text content transitions
grep -rEn "contentTransition\(\.numericText" native/ios-app/App/ --include="*.swift" \
  | grep -v "FireMotion/"

# Symbol effects (bounce, pulse, replace, scale, etc.)
grep -rn "symbolEffect" native/ios-app/App/ --include="*.swift" \
  | grep -v "FireMotion/"

# Sensory feedback (haptics)
grep -rn "sensoryFeedback" native/ios-app/App/ --include="*.swift" \
  | grep -v "FireMotion/"

# Direct UIKit haptic generators
grep -rn "UIFeedbackGenerator\|UIImpactFeedback\|UISelectionFeedback\|UINotificationFeedback" \
  native/ios-app/App/ --include="*.swift"
```

Expected: each command returns no matches. Any hit indicates a missed centralisation — route it through the appropriate `.fire*` modifier before continuing. (Other `contentTransition` flavours such as `.opacity` are unaffected by the audit; the spec only centralises the three motion families above.)

- [ ] **Step 4: Run the full unit suite**

```bash
xcodebuild test \
  -project native/ios-app/Fire.xcodeproj \
  -scheme Fire \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -derivedDataPath /tmp/fire-ios-track-c \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** TEST SUCCEEDED **`. `FireMotionTokensTests` plus all previously-passing cases.

- [ ] **Step 5: Confirm no Xcode project drift**

```bash
xcodegen generate --spec native/ios-app/project.yml
git diff --exit-code -- native/ios-app/Fire.xcodeproj
```

Expected: exit code `0`.

- [ ] **Step 6: Manual smoke test — full motion lap**

Run the app on the iOS 17 simulator AND an iOS 18 simulator (the deployment-target boundary). For each:

1. Cold launch + login → auth-gate cross-fade is smooth, honours Reduce Motion.
2. Tap a topic from the home feed → push transition (iOS 18: zoom into the row; iOS 17: slide+fade).
3. Inside the topic, like a post → heart bounces, count flips numerically, success haptic plays.
4. Bookmark the topic via the menu → bookmark icon swap-transitions, success haptic plays.
5. Open the bookmark editor sheet → softer spring than system default.
6. Mark a notification as read → row fades out via `.fireListItem`.
7. Open profile of a user you have not followed yet → tap follow → bounce + confetti burst (this session only).
8. Toggle Reduce Motion = ON → repeat 1–7. All durations zero out, no scale, no bounce, no confetti. Haptics still play.

If any of the above misbehaves on iOS 17 specifically (the most likely fail point is the `if #available(iOS 18, *)` branch), audit Task 11 Step 4.

- [ ] **Step 7: Commit Phase 4**

```bash
git add native/ios-app/App/FireMotion/FireMotionTransitions.swift \
        native/ios-app/App/FireProfileActivityTimelineView.swift \
        native/ios-app/App/FireTabRoot.swift \
        native/ios-app/App/FireHomeView.swift \
        native/ios-app/App/FireFilteredTopicListView.swift \
        native/ios-app/App/FireBookmarksView.swift \
        native/ios-app/App/FireNotificationHistoryView.swift \
        native/ios-app/App/FireBookmarkEditorSheet.swift \
        native/ios-app/App/FireTagPickerSheet.swift \
        native/ios-app/App/FireComposerView.swift \
        native/ios-app/App/FireTopicDetailView.swift

git commit -m "$(cat <<'EOF'
feat(ios/motion): T3 navigation, sheet, list transitions (Track C / Phase 4)

Adds .fireNavigationPush helper that uses iOS 18 .zoom where available
and falls back to .firePush on iOS 17. Centralises sheet spring config
via .fireSheet() across composer, tag picker, bookmark editor, and the
topic-detail sheets. Wires .fireListItem into notification and profile
activity ForEach surfaces, and routes the FireTabRoot auth-gate cross
fade through the module so it honours Reduce Motion.
EOF
)"
```

- [ ] **Step 8: Hand off Track C to the unified PR flow**

Record the following in the handoff bundle:

- per-phase touched files and commit SHAs, or the proposed commit messages when VCS ownership stayed outside the slice
- commands run plus success/failure status
- unit/build/manual validation results, including the Reduce Motion lap and any badge-unlock decision taken in Phase 2
- docs updated or explicitly checked
- remaining risks or follow-ups before the unified PR

Stop after handoff. Do not open a phase PR or a Track C-only PR from this plan.
