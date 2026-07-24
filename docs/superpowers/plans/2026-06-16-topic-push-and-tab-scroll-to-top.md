# Secondary Stack and Full-Screen Pop Implementation Record

**Status:** Updated 2026-07-24 — all product secondary pages use an app-root
full-screen stack that covers the tab shell (Android multi-Activity analogue).

## Current Behavior

- Topic route requests still enter through `FireNavigationState.presentedTopicRoute`.
- Arbitrary secondary view controllers enter through
  `FireRootCoordinator.presentSecondary(_:)`.
- Typed secondary routes (topic / profile / badge) also enter through
  `FireRootCoordinator.presentSecondaryRoute(_:)` /
  `FireAppRouteControllerFactory.presentSecondaryRoute`.
- `FireRootCoordinator` owns one **app-root secondary `FireMainNavigationController`**
  presented full-screen above `FireMainTabBarController`.
- The tab shell (including `UITabBar`) is **not** mutated: there is no
  `hidesBottomBarWhenPushed` for secondary product pages. The secondary page simply
  covers the tab bar the same way a second Android Activity covers the first.
- If a secondary stack is already presented, additional secondary opens **push**
  onto that stack.
- Nested topic links reuse
  `FireAppRouteControllerFactory.makeTopicRoutePresenter` with a provider that
  returns the secondary navigation controller (or `appRoot` which single-flights
  through `presentedTopicRoute` and then pushes onto the same stack).
- Logout / switch to onboarding dismisses the secondary stack without leaving a
  stale presented host.

### Surfaces that open on the secondary stack

| Entry | How |
|---|---|
| Topic detail (home / notifications / deep link) | `presentTopicRoute` → secondary stack |
| Search | `FireRootCoordinator.presentSecondary(FireSearchViewController)` |
| Profile content (bookmarks, history, drafts, messages, badges, follow lists) | Profile `pushFullScreen` → `presentSecondary` |
| Settings / LDC / CDK / invites | Profile `pushFullScreen` / hosting → `presentSecondary` |
| Notification history | `presentSecondary` |
| Public profile / badge routes | `presentSecondaryRoute` |
| Nested drill-down already on secondary | local `navigationController.push` |

Tab roots stay tab-owned: home feed, notifications list, profile root.

## Full-Screen Interactive Pop / Dismiss

`FireMainNavigationController` owns the WeChat-style full-screen back gesture:

- The system edge-only `interactivePopGestureRecognizer` is disabled.
- A full-screen `UIPanGestureRecognizer` is attached to the navigation
  controller's root view.
- A pan can begin when either:
  - the stack has more than one controller (in-stack pop), or
  - `allowsInteractiveDismissWhenAtRoot` is true and this controller is presented
    (interactive dismiss of the whole secondary stack, revealing the untouched tab shell).
- Progress is driven by `UIPercentDrivenInteractiveTransition`.
- In-stack pop uses a card animator plus a **navigation-bar snapshot** so chrome
  rides with the outgoing page instead of flipping to the destination bar early.
- Present / dismiss of the secondary stack use the same card push/pop motion
  (slide from right / slide out to right with light parallax on the under page).
- Root secondary pages without their own left bar item get an explicit back control
  that dismisses the stack.
- The gesture finishes when either progress reaches `0.34` or rightward velocity
  reaches `720 pt/s`; otherwise it cancels.

`FireTopicDetailViewController` already supports the presented-root path:

- Root of a presented secondary stack shows an explicit back control that dismisses.
- Its legacy edge-only non-interactive gesture stays disabled under
  `FireMainNavigationController` so there is one authoritative back gesture.

## Deliberately Separate Work

Tab re-tap scroll-to-top is not part of this implementation. Modal tools
(composer, category/tag pickers, sheets) remain `present`ed modals and are not
secondary stack pages.

## Primary Files

| File | Current responsibility |
|---|---|
| `native/ios-app/App/Core/FireRootCoordinator.swift` | Presents / pushes the app-root secondary stack; dismisses it on logout. |
| `native/ios-app/App/Core/FireMainTabBarController.swift` | Tab shell + `FireMainNavigationController` (full-screen pop, interactive root dismiss, card transitions, nav-bar snapshot). |
| `native/ios-app/App/Routing/FireAppRouteControllerFactory.swift` | Builds route VCs, nested presenters, `presentSecondaryRoute`. |
| `native/ios-app/App/Routing/FireAppRoute.swift` | `presentsAsSecondaryPage` classification. |
| `native/ios-app/App/Views/Profile/FireProfileViewController.swift` | Profile secondary entries via `presentSecondary`. |
| `native/ios-app/App/Views/Home/FireHomeView.swift` | Search + secondary route opens via root stack. |
| `native/ios-app/Tests/Unit/FireAppRouteTests.swift` | Route classification + pop / dismiss gate tests. |

## Verification

```bash
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireAppRouteTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' CODE_SIGNING_ALLOWED=NO
```
