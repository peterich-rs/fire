# Topic Push Navigation and Full-Screen Pop Implementation Record

**Status:** Implemented on 2026-06-18.

This document supersedes the earlier combined plan that mixed topic push
navigation, tab re-tap scroll-to-top, and a proposed `FireTopicPushNavigator`.
The code now uses the simpler UIKit path described below.

## Current Behavior

- Topic route requests still enter through `FireNavigationState.presentedTopicRoute`.
- `FireRootCoordinator` treats that value as a one-shot request. It resolves the
  selected tab's `UINavigationController`, builds the destination controller via
  `FireAppRouteControllerFactory.makeViewController`, pushes it, then immediately
  clears `presentedTopicRoute`.
- Topic detail controllers pushed from the tab shell set
  `hidesBottomBarWhenPushed = true`.
- Nested topic links reuse `FireAppRouteControllerFactory.makeTopicRoutePresenter`
  with the same navigation controller provider, so nested topic opens stay in the
  same tab stack.
- The legacy modal topic path was removed. There is no
  `FirePresentedTopicRouteHost`, modal topic navigation factory, or presented
  route navigation controller.
- `FireMainTabBarController` creates `FireMainNavigationController` instances
  for every production tab. Profile still has its tracked transitional SwiftUI
  root host, but it is contained by the same UIKit tab navigation shell.

## Full-Screen Interactive Pop

`FireMainNavigationController` owns the WeChat-style full-screen back gesture:

- The system edge-only `interactivePopGestureRecognizer` is disabled.
- A full-screen `UIPanGestureRecognizer` is attached to the navigation
  controller's root view.
- A pan can begin only when the stack has more than one controller, no navigation
  transition is already active, and the gesture is a rightward horizontal pan.
- Pop progress is driven by `UIPercentDrivenInteractiveTransition`.
- The custom pop animator moves the outgoing view rightward and brings the
  destination view in from a small left parallax offset.
- The gesture finishes when either progress reaches `0.34` or rightward velocity
  reaches `720 pt/s`; otherwise it cancels.

`FireTopicDetailViewController` disables its older non-interactive left-edge
back gesture whenever it is hosted inside `FireMainNavigationController`, so the
main tab shell has one authoritative back gesture. The old edge gesture remains
available only for non-main navigation or legacy modal-style hosts.

## Deliberately Separate Work

Tab re-tap scroll-to-top is not part of this implementation. It should be added
independently if needed, because it does not need to be coupled to topic push
navigation or full-screen interactive pop.

## Primary Files

| File | Current responsibility |
|---|---|
| `native/ios-app/App/Core/FireRootCoordinator.swift` | Converts one-shot topic route requests into pushes on the selected tab navigation stack. |
| `native/ios-app/App/Core/FireMainTabBarController.swift` | Builds tab navigation controllers and owns `FireMainNavigationController`, including the full-screen interactive pop. |
| `native/ios-app/App/Routing/FireAppRouteControllerFactory.swift` | Builds route view controllers and nested route presenters only; no longer builds modal navigation controllers. |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift` | Runs the native topic detail screen and disables its legacy edge gesture under the main navigation shell. |
| `native/ios-app/Tests/Unit/FireAppRouteTests.swift` | Covers topic route state behavior and `FireMainNavigationController` bar/gesture thresholds. |

## Verification

Verified with:

```bash
xcodebuild test -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' -only-testing:FireTests/FireAppRouteTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' CODE_SIGNING_ALLOWED=NO
git diff --check
```
