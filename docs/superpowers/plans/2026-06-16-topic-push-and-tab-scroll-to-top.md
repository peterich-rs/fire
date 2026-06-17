# Topic Push Navigation + Tab Re-tap Scroll-to-Top Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert topic detail presentation from full-screen modal to in-stack push navigation, and add WeChat-style "re-tap selected tab to scroll to top" behavior, so the iOS app gets native iOS swipe-back gestures and a familiar tab-bar interaction.

**Architecture:** Topic detail stops being presented modally via `FireRootCoordinator.syncTopicPresentation` + a root-level `topicNavigationController`. Instead, the currently-selected tab's `UINavigationController` pushes `FireTopicDetailViewController`. This unlocks the system `interactivePopGestureRecognizer` (edge-swipe-back) for free, and sets up a single `UINavigationControllerDelegate` site where a future full-screen interactive transition can land. Separately, `FireMainTabBarController` gains a `previouslySelectedIndex` to detect re-taps, and routes them through a new `FireTabScrollsToTop` protocol that `FireHomeViewController` and `FireNotificationsViewController` already conform to via their `FireListViewController` child.

**Tech Stack:** UIKit (`UINavigationController`, `UITabBarController`, `UIGestureRecognizer`), Combine (`@Published`, `navigationState.$presentedTopicRoute`), XCTest.

---

## Context an engineer needs to know

### Current topic presentation path (what we're changing)

Today, opening a topic goes through this chain:

1. Something calls `navigationState.presentTopicRoute(route)` (e.g. tapping a home row → `FireTopicRoutePresenter.appRoot` → `navigationState.presentTopicRoute`).
2. `FireNavigationState.$presentedTopicRoute` fires.
3. `FireRootCoordinator.syncTopicPresentation(_:)` (`App/Core/FireRootCoordinator.swift:383-406`) builds a **new** `FirePresentedRouteNavigationController` via `FireAppRouteControllerFactory.makeNavigationController(...)`, sets `modalPresentationStyle = .fullScreen`, and calls `presentationAnchor()?.present(navigationController, animated: true)`.
4. The modal nav controller's `onDidDismiss` callback fires `topicPresentationDidDismiss()` which clears `navigationState.presentedTopicRoute` and updates APM.

The topic detail is therefore **always a modal full-screen cover above the tab shell**, never part of any tab's nav stack. This is why the system `interactivePopGestureRecognizer` does nothing useful at the topic root, and why the custom non-interactive edge gesture exists at `FireTopicDetailViewController.swift:20-29`.

### Files that own topic presentation

| File | Role |
|---|---|
| `App/Core/FireRootCoordinator.swift:383-406` | `syncTopicPresentation` — builds + presents the modal nav controller |
| `App/Core/FireRootCoordinator.swift:408-417` | `topicPresentationDidDismiss` — clears state on modal dismiss |
| `App/Core/FireRootCoordinator.swift:45` | `private weak var topicNavigationController: UINavigationController?` |
| `App/Routing/FireAppRouteControllerFactory.swift:6-32` | `makeNavigationController(viewModel:topicDetailStore:route:onDismiss:)` — builds the modal nav controller |
| `App/Routing/FireAppRouteControllerFactory.swift:34-71` | `makeViewController(viewModel:topicDetailStore:route:topicRoutePresenter:)` — builds the `FireTopicDetailViewController` (or other route VC) |
| `App/Routing/FireAppRouteControllerFactory.swift:73-105` | `makeTopicRoutePresenter(...:navigationControllerProvider:)` — builds a presenter that pushes **nested** topic routes onto the same nav controller |
| `App/Routing/FireAppRouteControllerFactory.swift:112-128` | `FirePresentedRouteNavigationController` — private `UINavigationController` subclass, only reports dismiss |
| `App/Routing/FireTopicRoutePresenter.swift:10-32` | `FireTopicRoutePresenter.appRoot(...)` — the presenter used by Home (writes to `navigationState.presentedTopicRoute`) |
| `App/Navigation/FireNavigationState.swift:9,19-27` | `presentedTopicRoute` + `presentTopicRoute(_:)` / `dismissPresentedTopicRoute()` |
| `App/TopicDetail/Controller/FireTopicDetailViewController.swift:20-29, 605-629` | The custom non-interactive edge-pan back gesture (kept; it still gates modal-style back for push stacks with one item) |

### Current tab re-tap behavior (what we're changing)

`FireMainTabBarController` (`App/Core/FireMainTabBarController.swift:58-63`) implements `UITabBarControllerDelegate.tabBarController(_:didSelect:)` and forwards the index via `onSelectedTabChanged?(index)`. UIKit fires this on **every** tap, including re-taps of the already-selected tab, but the closure body in `FireRootCoordinator` (`App/Core/FireRootCoordinator.swift:300-308`) only does: haptic + conditionally update `navigationState.selectedTab` + APM + pending-route handling. **No scroll-to-top, no sheet dismissal.**

The list screens (`FireHomeViewController`, `FireNotificationsViewController`) own a `FireListViewController<SectionID, ItemID>` child controller whose `collectionView` is **private** (`App/ListKit/FireDiffableListController.swift:164`). There is no public scroll-to-top hook today.

### Test conventions

Unit tests live in `Tests/Unit/`, import `@testable import Fire`, and follow `XCTest`. Pure-logic helpers (like `fireHomeShouldRequestNextPage`) are unit-tested directly; view-controller behavior is tested via host-app introspection. See `Tests/Unit/FireTopicPresentationTests.swift` and `Tests/Unit/FireListPaginationAndUpdateTests.swift` for style. There is **no** UI test target today — tests are logic-level.

### Architecture guardrails (from AGENTS.md)

- "Prefer one authoritative implementation path per feature. If behavior is missing, fix the authoritative path instead of hiding the gap behind a secondary fallback."
- "Do not add fallback, compatibility, or parallel rendering logic unless it is required by a current production constraint."
- "In iOS topic detail, post and reply rows should stay on the native runtime cell path; do not reintroduce SwiftUI post-row fallbacks."

This plan does **not** add a parallel path — it replaces the modal path with the push path as the single authoritative route.

---

## File Structure

### Files created

| File | Responsibility |
|---|---|
| `App/Navigation/FireTopicPushNavigation.swift` | `FireTopicPushNavigator` — the single object that resolves the active tab's nav controller and pushes a topic VC onto it; owns the weak push-stack nav controller reference and the nested-route presenter wiring. Replaces `FireRootCoordinator`'s direct modal presentation. |
| `App/Navigation/FireTabScrollsToTop.swift` | `protocol FireTabScrollsToTop` — one-method protocol (`func scrollToTopForTabRetap()`) that tab-root view controllers conform to so the tab bar can request scroll-to-top without knowing concrete types. |
| `Tests/Unit/FireTopicPushNavigationTests.swift` | Unit tests for `FireTopicPushNavigator` selection logic (which nav controller gets the push, nested-route presenter wiring, cross-tab switching). |
| `Tests/Unit/FireTabScrollsToTopTests.swift` | Unit tests for the `FireTabScrollsToTop` protocol routing in `FireMainTabBarController` (re-tap detection + scroll dispatch). |

### Files modified

| File | Change |
|---|---|
| `App/ListKit/FireDiffableListController.swift` | Add `func scrollToTop(animated:)` public method that safely scrolls the private `collectionView` to inset origin. |
| `App/Core/FireMainTabBarController.swift` | Add `previouslySelectedIndex` storage; in `didSelect`, detect re-tap and call `scrollToTopForTabRetap()` on the selected tab's root VC via `FireTabScrollsToTop`; also dismiss any presented sheet on re-tap. |
| `App/Views/Home/FireHomeView.swift` | Conform `FireHomeViewController` to `FireTabScrollsToTop`; forward `scrollToTopForTabRetap()` to `listController.scrollToTop(animated:)`. |
| `App/Views/Notifications/FireNotificationsViewController.swift` | Conform `FireNotificationsViewController` to `FireTabScrollsToTop`; same forwarding. |
| `App/Core/FireRootCoordinator.swift` | Replace `syncTopicPresentation` modal-present logic with `FireTopicPushNavigator` push logic; delete `topicNavigationController` ivar and `topicPresentationDidDismiss` modal-clearing; wire the navigator's "did pop to empty" callback to `navigationState.dismissPresentedTopicRoute()`. |
| `App/Routing/FireAppRouteControllerFactory.swift` | Keep `makeViewController` and `makeTopicRoutePresenter` (reused); `makeNavigationController` becomes unused by the push path but stays for any remaining modal callers — verify no callers remain, then delete it and `FirePresentedRouteNavigationController`. |
| `App/TopicDetail/Controller/FireTopicDetailViewController.swift` | Update `canNavigateBackFromTopicDetail` logic: with push nav, "back" is always a pop when `viewControllers.count > 1`, else dismiss. The existing edge-pan gesture stays (it still triggers `navigateBackFromTopicDetail`). |
| `App/Routing/FireTopicRoutePresenter.swift` | No change — `appRoot` presenter still writes to `navigationState.presentedTopicRoute`; the coordinator now reacts to that by pushing instead of presenting. |

---

## Tasks

### Task 1: Add `scrollToTop` to `FireListViewController`

This is the foundation for tab re-tap scroll-to-top. It exposes a safe scroll-to-origin on the private `collectionView` without breaking the refresh-control settling logic.

**Files:**
- Modify: `native/ios-app/App/ListKit/FireDiffableListController.swift` (add method after the existing `scrollToItemWillMove` helper near line 828)

- [ ] **Step 1: Write the failing test**

Create `Tests/Unit/FireListScrollToTopTests.swift`:

```swift
import XCTest
@testable import Fire

final class FireListScrollToTopTests: XCTestCase {
    func testScrollToTopIsExposedOnListViewController() {
        // The method must exist and be callable without a live collectionView
        // (no-op when collectionView is nil, e.g. before viewDidLoad).
        let controller = FireListViewController<
            FireHomeCollectionSectionForTest,
            FireHomeCollectionItemForTest
        >(
            layout: UICollectionViewLayout(),
            backgroundColor: .systemBackground
        )

        // Should not crash when collectionView is nil.
        controller.scrollToTop(animated: true)
    }
}

// Test-only section/item types so we don't depend on Home's private types.
enum FireHomeCollectionSectionForTest: Int, Hashable { case content }
enum FireHomeCollectionItemForTest: Hashable { case topic(UInt64) }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireListScrollToTopTests`
Expected: FAIL — `scrollToTop(animated:)` does not exist on `FireListViewController`.

- [ ] **Step 3: Implement `scrollToTop`**

Add this method to `FireListViewController` in `FireDiffableListController.swift`, immediately after the `scrollToItemWillMove` private helper (after line ~828):

```swift
func scrollToTop(animated: Bool) {
    guard let collectionView else { return }
    guard !isSettlingAfterRefresh else { return }
    let topInset = collectionView.adjustedContentInset.top
    let topOffsetY = -topInset
    guard abs(collectionView.contentOffset.y - topOffsetY) >= 0.5 else { return }
    collectionView.setContentOffset(
        CGPoint(x: collectionView.contentOffset.x, y: topOffsetY),
        animated: animated
    )
}
```

Rationale: mirrors the existing `scrollToItemWillMove` guard pattern (`abs(contentOffset - target) < 0.5` → no-op) and respects `isSettlingAfterRefresh` so we don't fight UIKit's refresh-control rebound (documented at lines 173-179).

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireListScrollToTopTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/ListKit/FireDiffableListController.swift \
        native/ios-app/Tests/Unit/FireListScrollToTopTests.swift
git commit -m "feat(ios): expose scrollToTop on FireListViewController"
```

---

### Task 2: Define `FireTabScrollsToTop` protocol

The protocol that lets `FireMainTabBarController` request scroll-to-top without knowing about `FireListViewController` generics.

**Files:**
- Create: `native/ios-app/App/Navigation/FireTabScrollsToTop.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Unit/FireTabScrollsToTopTests.swift`:

```swift
import XCTest
@testable import Fire

final class FireTabScrollsToTopTests: XCTestCase {
    func testProtocolIsCallableThroughExistential() {
        let conformer = FireTestScrollsToTopConformer()
        let existential: Any = conformer
        XCTAssertTrue(existential is FireTabScrollsToTop)
        (existential as? FireTabScrollsToTop)?.scrollToTopForTabRetap()
        XCTAssertTrue(conformer.didCallScrollToTop)
    }
}

private final class FireTestScrollsToTopConformer: FireTabScrollsToTop {
    var didCallScrollToTop = false
    func scrollToTopForTabRetap() {
        didCallScrollToTop = true
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTabScrollsToTopTests`
Expected: FAIL — `FireTabScrollsToTop` does not exist.

- [ ] **Step 3: Create the protocol file**

Create `native/ios-app/App/Navigation/FireTabScrollsToTop.swift`:

```swift
import Foundation

protocol FireTabScrollsToTop: AnyObject {
    func scrollToTopForTabRetap()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTabScrollsToTopTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Navigation/FireTabScrollsToTop.swift \
        native/ios-app/Tests/Unit/FireTabScrollsToTopTests.swift
git commit -m "feat(ios): add FireTabScrollsToTop protocol"
```

---

### Task 3: Conform `FireHomeViewController` and `FireNotificationsViewController` to `FireTabScrollsToTop`

Wire the two UIKit list screens so a tab re-tap can scroll them to top.

**Files:**
- Modify: `native/ios-app/App/Views/Home/FireHomeView.swift` (add conformance + method)
- Modify: `native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift` (add conformance + method)

- [ ] **Step 1: Add conformance to `FireHomeViewController`**

In `FireHomeView.swift`, find the class declaration (line 55):

```swift
@MainActor
final class FireHomeViewController: UIViewController {
```

Change it to:

```swift
@MainActor
final class FireHomeViewController: UIViewController, FireTabScrollsToTop {
```

Then add the method (place it near the other `listController`-forwarding helpers, e.g. right after `viewDidLoad` or any existing private extension on the class). Add inside the class body:

```swift
func scrollToTopForTabRetap() {
    listController.scrollToTop(animated: true)
}
```

- [ ] **Step 2: Add conformance to `FireNotificationsViewController`**

In `FireNotificationsViewController.swift`, find the class declaration (line 34):

```swift
final class FireNotificationsViewController: UIViewController {
```

Change it to:

```swift
final class FireNotificationsViewController: UIViewController, FireTabScrollsToTop {
```

Add inside the class body:

```swift
func scrollToTopForTabRetap() {
    listController.scrollToTop(animated: true)
}
```

Both classes already store `listController` as a non-private property (Home: `FireHomeView.swift:76`, Notifications: `FireNotificationsViewController.swift:49`), so the forward is direct.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: BUILD SUCCEEDED. (No test here because the conformance is verified by compilation + the tab-bar integration test in Task 4.)

- [ ] **Step 4: Commit**

```bash
git add native/ios-app/App/Views/Home/FireHomeView.swift \
        native/ios-app/App/Views/Notifications/FireNotificationsViewController.swift
git commit -m "feat(ios): conform Home and Notifications to FireTabScrollsToTop"
```

---

### Task 4: Add re-tap detection + scroll-to-top dispatch in `FireMainTabBarController`

Detect when the user taps the already-selected tab and dispatch `scrollToTopForTabRetap()` plus dismiss any presented sheet.

**Files:**
- Modify: `native/ios-app/App/Core/FireMainTabBarController.swift` (add `previouslySelectedIndex`, update `didSelect`)

- [ ] **Step 1: Write the failing test**

Append to `Tests/Unit/FireTabScrollsToTopTests.swift` (created in Task 2):

```swift
final class FireTabRetapRoutingTests: XCTestCase {
    func testRetapRoutesToScrollsToTopConformer() {
        let conformer = FireTestScrollsToTopConformer()
        let navController = UINavigationController(rootViewController: conformer)
        let tabController = FireMainTabBarController(
            viewControllersForRetapTest: [navController]
        )

        // Simulate first selection (index 0).
        tabController.simulateDidSelect(index: 0)
        XCTAssertFalse(conformer.didCallScrollToTop, "first tap should not scroll")

        // Simulate re-tap (same index).
        tabController.simulateDidSelect(index: 0)
        XCTAssertTrue(conformer.didCallScrollToTop, "re-tap should scroll to top")
    }
}
```

This test uses two test-only helpers on `FireMainTabBarController`: a convenience init `viewControllersForRetapTest:` and `simulateDidSelect(index:)`. They are added in Step 3 and marked `internal` so the test target (which uses `@testable import Fire`) can reach them.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTabRetapRoutingTests`
Expected: FAIL — `viewControllersForRetapTest` and `simulateDidSelect` do not exist.

- [ ] **Step 3: Implement re-tap detection**

In `FireMainTabBarController.swift`:

3a. Add stored property after line 5 (`var onSelectedTabChanged`):

```swift
private var previouslySelectedIndex: Int?
```

3b. Replace the `didSelect` implementation (lines 58-63):

```swift
func tabBarController(
    _ tabBarController: UITabBarController,
    didSelect viewController: UIViewController
) {
    guard let index = viewControllers?.firstIndex(of: viewController) else {
        return
    }
    if previouslySelectedIndex == index {
        handleTabRetap(at: index, in: viewController)
    }
    previouslySelectedIndex = index
    onSelectedTabChanged?(index)
}

private func handleTabRetap(at index: Int, in viewController: UIViewController) {
    if let navController = viewController as? UINavigationController {
        navController.dismiss(animated: true)
        if let root = navController.viewControllers.first,
           let scrollable = root as? FireTabScrollsToTop {
            scrollable.scrollToTopForTabRetap()
        }
    } else if let scrollable = viewController as? FireTabScrollsToTop {
        scrollable.scrollToTopForTabRetap()
    }
}
```

3c. Add the test-only helpers (place them near the bottom of the class, before the closing brace). These are `internal` (not `private`) so `@testable import Fire` can reach them:

```swift
#if DEBUG
convenience init(viewControllersForRetapTest: [UIViewController]) {
    self.init(
        viewModel: FireAppViewModel(),
        navigationState: FireNavigationState.shared,
        homeFeedStore: FireHomeFeedStore(appViewModel: FireAppViewModel()),
        searchStore: FireSearchStore(appViewModel: FireAppViewModel()),
        notificationStore: FireNotificationStore(appViewModel: FireAppViewModel()),
        topicDetailStore: FireTopicDetailStore(appViewModel: FireAppViewModel()),
        profileViewModel: FireProfileViewModel()
    )
    viewControllers = viewControllersForRetapTest
}

func simulateDidSelect(index: Int) {
    guard let controllers = viewControllers, controllers.indices.contains(index) else { return }
    tabBarController(self, didSelect: controllers[index])
}
#endif
```

> **Note:** The convenience init constructs real store objects because `FireMainTabBarController` is not fully DI-friendly yet. These stores are cheap to allocate and unused in the test path. If allocation is too heavy at test time, the engineer may instead refactor `FireMainTabBarController` to accept an optional `viewControllers:` parameter in the designated init — but that is out of scope for this task unless it blocks.

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTabRetapRoutingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Core/FireMainTabBarController.swift \
        native/ios-app/Tests/Unit/FireTabScrollsToTopTests.swift
git commit -m "feat(ios): dispatch scroll-to-top on tab re-tap"
```

---

### Task 5: Define `FireTopicPushNavigator`

The object that replaces `FireRootCoordinator.syncTopicPresentation`'s modal-present logic. It resolves the active tab's nav controller and pushes the topic VC.

**Files:**
- Create: `native/ios-app/App/Navigation/FireTopicPushNavigation.swift`
- Create: `native/ios-app/Tests/Unit/FireTopicPushNavigationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Unit/FireTopicPushNavigationTests.swift`:

```swift
import XCTest
import UIKit
@testable import Fire

final class FireTopicPushNavigationTests: XCTestCase {
    @MainActor
    func testPushTopicOntoActiveTabNavController() throws {
        let rootVC = UIViewController()
        let navController = UINavigationController(rootViewController: rootVC)
        let tabController = UITabBarController()
        tabController.viewControllers = [navController]
        tabController.selectedIndex = 0

        let navigationState = FireNavigationState()
        let viewModel = FireAppViewModel()
        let topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)

        let navigator = FireTopicPushNavigator(
            tabBarControllerProvider: { tabController },
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationState: navigationState,
            onDidPopToRoot: { _ in }
        )

        let route = FireAppRoute.topic(
            topicId: 42,
            postNumber: nil,
            preview: nil
        )
        navigator.push(route: route)

        XCTAssertEqual(navController.viewControllers.count, 2, "topic VC should be pushed onto the active tab's nav controller")
        XCTAssertTrue(navController.viewControllers.last is FireTopicDetailViewController)
    }

    @MainActor
    func testPushSwitchesTabBeforePushingWhenRouteArrivesFromInactiveTab() throws {
        let homeNav = UINavigationController(rootViewController: UIViewController())
        let notificationsNav = UINavigationController(rootViewController: UIViewController())
        let tabController = UITabBarController()
        tabController.viewControllers = [homeNav, notificationsNav]
        tabController.selectedIndex = 1

        let navigationState = FireNavigationState()
        let viewModel = FireAppViewModel()
        let topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)

        let navigator = FireTopicPushNavigator(
            tabBarControllerProvider: { tabController },
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationState: navigationState,
            onDidPopToRoot: { _ in }
        )

        // Simulate the common case: route arrives, navigator should push onto the
        // *currently selected* tab (index 1 here), not force-switch to Home.
        let route = FireAppRoute.topic(topicId: 7, postNumber: nil, preview: nil)
        navigator.push(route: route)

        XCTAssertEqual(tabController.selectedIndex, 1, "should not force-switch tabs")
        XCTAssertEqual(notificationsNav.viewControllers.count, 2, "topic pushed onto the selected tab")
    }

    @MainActor
    func testNestedTopicRoutePushesDeeperOntoSameNavController() throws {
        let rootVC = UIViewController()
        let navController = UINavigationController(rootViewController: rootVC)
        let tabController = UITabBarController()
        tabController.viewControllers = [navController]
        tabController.selectedIndex = 0

        let navigationState = FireNavigationState()
        let viewModel = FireAppViewModel()
        let topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)

        let navigator = FireTopicPushNavigator(
            tabBarControllerProvider: { tabController },
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationState: navigationState,
            onDidPopToRoot: { _ in }
        )

        let first = FireAppRoute.topic(topicId: 1, postNumber: nil, preview: nil)
        let second = FireAppRoute.topic(topicId: 2, postNumber: nil, preview: nil)
        navigator.push(route: first)
        navigator.push(route: second)

        XCTAssertEqual(navController.viewControllers.count, 3, "two topics pushed deep on the same stack")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTopicPushNavigationTests`
Expected: FAIL — `FireTopicPushNavigator` does not exist.

- [ ] **Step 3: Implement `FireTopicPushNavigator`**

Create `native/ios-app/App/Navigation/FireTopicPushNavigation.swift`:

```swift
import UIKit

@MainActor
final class FireTopicPushNavigator {
    private let tabBarControllerProvider: () -> UITabBarController?
    private let viewModel: FireAppViewModel
    private let topicDetailStore: FireTopicDetailStore
    private let navigationState: FireNavigationState
    private let onDidPopToRoot: (UINavigationController) -> Void

    init(
        tabBarControllerProvider: @escaping () -> UITabBarController?,
        viewModel: FireAppViewModel,
        topicDetailStore: FireTopicDetailStore,
        navigationState: FireNavigationState,
        onDidPopToRoot: @escaping (UINavigationController) -> Void
    ) {
        self.tabBarControllerProvider = tabBarControllerProvider
        self.viewModel = viewModel
        self.topicDetailStore = topicDetailStore
        self.navigationState = navigationState
        self.onDidPopToRoot = onDidPopToRoot
    }

    func push(route: FireAppRoute) {
        guard let tabBarController = tabBarControllerProvider(),
              let navController = tabBarController.selectedViewController as? UINavigationController
        else {
            viewModel.topicRouteLogger()?.warning(
                "push navigator could not resolve active nav controller for \(route.diagnosticsSummary)"
            )
            return
        }

        let weakNavController = FireWeakPushNavControllerBox()
        weakNavController.navigationController = navController

        let topicRoutePresenter = FireAppRouteControllerFactory.makeTopicRoutePresenter(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationControllerProvider: { weakNavController.navigationController }
        )

        let viewController = FireAppRouteControllerFactory.makeViewController(
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            route: route,
            topicRoutePresenter: topicRoutePresenter
        )

        navController.pushViewController(viewController, animated: true)
        viewModel.topicRouteLogger()?.info(
            "push navigator pushed route \(route.diagnosticsSummary) new_stack_count=\(navController.viewControllers.count)"
        )
    }

    func popToRoot() {
        guard let tabBarController = tabBarControllerProvider(),
              let navController = tabBarController.selectedViewController as? UINavigationController
        else {
            return
        }
        guard navController.viewControllers.count > 1 else {
            onDidPopToRoot(navController)
            return
        }
        navController.popToRootViewController(animated: true)
        onDidPopToRoot(navController)
    }
}

private final class FireWeakPushNavControllerBox {
    weak var navigationController: UINavigationController?
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireTopicPushNavigationTests`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add native/ios-app/App/Navigation/FireTopicPushNavigation.swift \
        native/ios-app/Tests/Unit/FireTopicPushNavigationTests.swift
git commit -m "feat(ios): add FireTopicPushNavigator for in-stack topic push"
```

---

### Task 6: Wire `FireTopicPushNavigator` into `FireRootCoordinator`, remove modal presentation

Replace the modal-present path with the push path. This is the central behavior change of the plan.

**Files:**
- Modify: `native/ios-app/App/Core/FireRootCoordinator.swift` (replace `syncTopicPresentation`, delete modal ivar, add navigator)
- Modify: `native/ios-app/App/Routing/FireAppRouteControllerFactory.swift` (delete `makeNavigationController` + `FirePresentedRouteNavigationController` if no other callers)

- [ ] **Step 1: Write the failing test**

Append to `Tests/Unit/FireTopicPushNavigationTests.swift`:

```swift
final class FireRootCoordinatorPushIntegrationTests: XCTestCase {
    @MainActor
    func testPresentedTopicRouteTriggersPushNotModal() throws {
        // The integration contract: setting navigationState.presentedTopicRoute
        // must push onto the tab's nav controller, not present a modal.
        // We verify by checking no modal is presented after the route fires.
        let window = UIWindow(frame: UIScreen.main.bounds)
        let coordinator = FireRootCoordinator(windowForTest: window)
        coordinator.startForTest(authenticated: true)

        let tabController = try XCTUnwrap(
            window.rootViewController as? FireMainTabBarController
        )
        let navController = try XCTUnwrap(
            tabController.selectedViewController as? UINavigationController
        )
        let initialStackCount = navController.viewControllers.count

        coordinator.navigationStateForTest.presentTopicRoute(
            .topic(topicId: 99, postNumber: nil, preview: nil)
        )

        // Runloop tick so the @Published sink fires.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(navController.viewControllers.count, initialStackCount + 1, "topic pushed")
        XCTAssertNil(tabController.presentedViewController, "no modal should be presented")
    }
}
```

This test uses two test-only helpers on `FireRootCoordinator`: `init(windowForTest:)`, `startForTest(authenticated:)`, and `navigationStateForTest`. They are added in Step 3.

> **Note:** `FireRootCoordinator` currently uses `FireNavigationState.shared` and constructs its own `FireAppViewModel`/stores in `init(window:)`. The test helpers expose the navigation state for assertion. If full app bootstrap in a test proves too heavy (network/auth), the engineer may instead add a lighter "coordinator receives pre-built stores" init — but that refactor is out of scope unless it blocks the test.

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireRootCoordinatorPushIntegrationTests`
Expected: FAIL — `windowForTest` / `startForTest` / `navigationStateForTest` do not exist, and the current code presents modally so `presentedViewController` would be non-nil.

- [ ] **Step 3: Replace modal logic with push logic**

In `FireRootCoordinator.swift`:

3a. Delete the ivar at line 45:
```swift
private weak var topicNavigationController: UINavigationController?
```

3b. Add a navigator property (near the other properties, e.g. after line 47):
```swift
private var topicPushNavigator: FireTopicPushNavigator?
```

3c. Replace `syncTopicPresentation(_:)` (lines 383-406) entirely:

```swift
private func syncTopicPresentation(_ route: FireAppRoute?) {
    guard authController == nil else { return }
    guard let mainTabBarController else { return }

    if topicPushNavigator == nil {
        topicPushNavigator = FireTopicPushNavigator(
            tabBarControllerProvider: { [weak self] in self?.mainTabBarController },
            viewModel: viewModel,
            topicDetailStore: topicDetailStore,
            navigationState: navigationState,
            onDidPopToRoot: { [weak self] _ in
                self?.topicPresentationDidDismiss()
            }
        )
    }

    if let route {
        guard !hasActiveTopicPush else { return }
        viewModel.topicRouteLogger()?.info("root coordinator pushing topic route \(route.diagnosticsSummary)")
        topicPushNavigator?.push(route: route)
        return
    }

    if hasActiveTopicPush {
        topicPushNavigator?.popToRoot()
    }
}

private var hasActiveTopicPush: Bool {
    guard let navController = mainTabBarController?.selectedViewController as? UINavigationController else {
        return false
    }
    return navController.viewControllers.contains { $0 is FireTopicDetailViewController }
}
```

3d. Keep `topicPresentationDidDismiss()` (lines 408-417) **unchanged** — it still clears `navigationState.presentedTopicRoute` and updates APM. It now fires from the navigator's `onDidPopToRoot` callback instead of the modal's `onDidDismiss`.

3e. Add the test-only helpers at the bottom of the class (before the closing brace):

```swift
#if DEBUG
convenience init(windowForTest window: UIWindow) {
    self.init(window: window)
}

func startForTest(authenticated: Bool) {
    // Force the authenticated root path without going through real auth/boot.
    if authenticated {
        updateRoot(animated: false)
    }
}

var navigationStateForTest: FireNavigationState { navigationState }
#endif
```

- [ ] **Step 4: Delete dead modal code in `FireAppRouteControllerFactory.swift`**

In `FireAppRouteControllerFactory.swift`:

4a. Delete `makeNavigationController` (lines 6-32) — now unused.

4b. Delete `FirePresentedRouteNavigationController` (lines 112-128) — now unused.

4c. Delete `FireWeakNavigationControllerBox` (lines 108-110) — only used by the deleted `makeNavigationController`.

4d. Verify no other callers of `makeNavigationController` exist:

Run: `rg "makeNavigationController" native/ios-app/`
Expected: zero matches outside the (now-deleted) definition.

- [ ] **Step 5: Build to verify no broken references**

Run: `xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the test to verify it passes**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:FireTests/FireRootCoordinatorPushIntegrationTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add native/ios-app/App/Core/FireRootCoordinator.swift \
        native/ios-app/App/Routing/FireAppRouteControllerFactory.swift \
        native/ios-app/Tests/Unit/FireTopicPushNavigationTests.swift
git commit -m "refactor(ios): push topic detail onto tab nav stack instead of modal present"
```

---

### Task 7: Update `FireTopicDetailViewController` back-navigation for the push model

The topic detail's `canNavigateBackFromTopicDetail` and `navigateBackFromTopicDetail` were written for a modal-presented root. With push nav, the back logic must prefer `popViewController` and rely on the system `interactivePopGestureRecognizer`.

**Files:**
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift` (lines 593-629, 309-310)

- [ ] **Step 1: Read the current back-navigation logic**

Re-read `FireTopicDetailViewController.swift` lines 593-629 to confirm the current `canNavigateBackFromTopicDetail` and `navigateBackFromTopicDetail` shape before editing.

- [ ] **Step 2: Simplify `navigateBackFromTopicDetail`**

Find `navigateBackFromTopicDetail()` (lines 622-629). Replace its body:

```swift
private func navigateBackFromTopicDetail() {
    if let navigationController, navigationController.viewControllers.count > 1 {
        navigationController.popViewController(animated: true)
    } else {
        dismiss(animated: true)
    }
}
```

The `popViewController` branch now covers the common case (we're pushed onto a tab nav stack). The `dismiss` branch is a safety net for any non-push presentation that still exists (e.g. a SwiftUI-hosted entry path during migration). This is not a "parallel path" — it's the single authoritative back method handling both stack depths.

- [ ] **Step 3: Confirm `canNavigateBackFromTopicDetail` is still correct**

The property at lines ~593-603 already checks `navigationController.viewControllers.count > 1` OR `presentingViewController != nil`. This remains correct for the push model — keep it unchanged.

- [ ] **Step 4: Verify the system `interactivePopGestureRecognizer` enablement**

Confirm lines 309-310 already enable the system pop gesture when `viewControllers.count > 1`:

```swift
navigationController?.interactivePopGestureRecognizer?.isEnabled =
    (navigationController?.viewControllers.count ?? 0) > 1
```

This is now effective because the topic is on a real nav stack. No change needed — but verify the build still includes it.

- [ ] **Step 5: Build and run the full test suite**

Run: `xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: BUILD SUCCEEDED, all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift
git commit -m "refactor(ios): prefer popViewController for topic detail back navigation"
```

---

### Task 8: Manual smoke test + documentation sync

Verify the end-to-end behavior on a simulator and update the architecture doc.

**Files:**
- Modify: `docs/superpowers/plans/2026-06-13-ios16-uikit-root-contract.md` (mark topic presentation as push, note the removal of modal topic presentation)

- [ ] **Step 1: Manual smoke test on simulator**

Build and run on a simulator:
1. Launch app, log in if needed.
2. From Home, tap a topic → confirm it **pushes** (slides in from right), not modal cover.
3. Swipe from the left edge → confirm the system interactive pop gesture works (finger-tracked reveal of Home).
4. Tap the back button or the edge-pan → confirm it pops back to Home.
5. From Home, tap a topic, then from inside the topic tap an @mention to a profile → confirm profile is pushed (or presented per existing modal router — that's unchanged).
6. Tap the Notifications tab → confirm it switches.
7. Scroll down the Notifications list, then tap the Notifications tab **again** → confirm the list scrolls to top.
8. Repeat step 7 on Home.
9. Open a presented sheet on Home (e.g. search), then re-tap the Home tab → confirm the sheet dismisses.
10. Verify the Notifications badge still updates.

- [ ] **Step 2: Update the architecture plan doc**

In `docs/superpowers/plans/2026-06-13-ios16-uikit-root-contract.md`, find the "Root Shell" workstream section and add a note under it:

```markdown
- Topic detail presentation (updated 2026-06-16): topic routes now push onto the
  selected tab's `UINavigationController` via `FireTopicPushNavigator`, replacing
  the earlier root-level modal `FirePresentedRouteNavigationController`. This
  unlocks the system `interactivePopGestureRecognizer` for edge-swipe back. The
  modal nav controller factory was removed.
- Tab re-tap (updated 2026-06-16): `FireMainTabBarController` now detects re-taps
  of the already-selected tab and dispatches `scrollToTopForTabRetap()` via the
  `FireTabScrollsToTop` protocol (conformed by Home and Notifications), plus
  dismisses any presented sheet.
```

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-06-13-ios16-uikit-root-contract.md
git commit -m "docs: document topic-push and tab re-tap scroll-to-top"
```

---

## Self-Review

After writing, I checked the plan against the spec:

**1. Spec coverage:**
- "贴文页改回 push 进 tab 的 nav 栈" → Tasks 5, 6, 7 (build navigator, wire into coordinator replacing modal, update VC back logic). ✅
- "Tab 重 tap 滚到顶" → Tasks 1, 2, 3, 4 (add scrollToTop, protocol, conformers, tab-bar dispatch). ✅
- "侧滑返回" (implied by push model) → Task 7 step 4 confirms system `interactivePopGestureRecognizer` now effective. ✅ (Full-screen WeChat-style interactive transition is explicitly out of scope here — this plan delivers the system edge-swipe, which is the 80% win, and leaves the custom `UIPercentDrivenInteractiveTransition` as a documented future task.)

**2. Placeholder scan:**
- No "TBD"/"TODO"/"implement later".
- No "add appropriate error handling".
- Every code step shows the actual code.
- The two `#if DEBUG` test-helper inits are fully specified with real store allocations, not stubs.

**3. Type consistency:**
- `FireTabScrollsToTop.scrollToTopForTabRetap()` — used identically in Task 2 (definition), Task 3 (conformers), Task 4 (dispatch). ✅
- `FireListViewController.scrollToTop(animated:)` — defined Task 1, called Task 3. ✅
- `FireTopicPushNavigator.push(route:)` / `popToRoot()` — defined Task 5, called Task 6. ✅
- `FireAppRouteControllerFactory.makeViewController` / `makeTopicRoutePresenter` — reused from existing code (Task 5 calls them, Task 6 deletes only `makeNavigationController`). ✅
- `onDidPopToRoot` callback signature `(UINavigationController) -> Void` — consistent across Task 5 init, Task 6 wiring, Task 6 `topicPresentationDidDismiss` (which ignores the param). ✅

---

## Out of scope (explicit)

The following are **not** in this plan and should be filed as follow-ups:

1. **Full-screen WeChat-style interactive pop with parallax** (`UIPercentDrivenInteractiveTransition` + full-screen pan + snapshot-based parallax reveal). This plan delivers the system edge-swipe gesture by moving to push nav. A future plan can add the custom transition on top of the now-single `UINavigationController` site.
2. **Badge polish** (99+ clamp, badgeColor, profile red-dot).
3. **iPad split-view** (`UISplitViewController` / iOS 18 `.sidebarAdaptable`).
4. **Profile tab `scrollToTopForTabRetap`** — Profile is still SwiftUI (`FireProfileTabRootHost`); conforming it requires routing through the SwiftUI scroll view, deferred until Profile migrates to UIKit.
5. **Haptic refinement** (gate `selectionChanged()` to tab-actually-changed).
