# iOS Topic Detail UIKit + Texture Execution Plan

> **For agentic workers:** use checkbox tasks as the source of truth for
> implementation sequencing. Each task below is designed to be landed as a
> reviewable commit slice.

**Goal:** replace the current mixed SwiftUI plus Texture topic-detail page with
an authoritative `UIViewController + ASCollectionNode` runtime that owns page
state, feed updates, layout measurement, and topic-detail-specific presentation.

**Architecture:** keep `FireTopicDetailStore` and Rust feed ownership unchanged,
introduce a dedicated `App/TopicDetail/` module for controller and feed
coordination, activate `FirePostLayoutManager` as the precise layout authority,
and retire the current `FireTopicDetailView` plus `FireTopicDetailListHost`
active path.

**Tech Stack:** Swift 5.10 app target, UIKit, Texture `AsyncDisplayKit.xcframework`,
existing topic-detail store/runtime models, existing post cell node/layout
types, `xcodegen`, `xcodebuild`.

---

## File Structure

| File | Action | Responsibility |
| --- | --- | --- |
| `native/ios-app/App/TopicDetail/Host/FireTopicDetailControllerHost.swift` | Create | route bridge from SwiftUI navigation into the controller |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift` | Create | page lifecycle, subscriptions, quick reply state, toolbar ownership, route-anchor handling |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift` | Create | UIKit-owned sheets, alerts, fullscreen presentation, and shared-screen launching |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift` | Create | top bar menu, share, bookmark, topic actions |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailPageState.swift` | Create | typed page state composed from store state plus page-local ephemeral UI state |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailPageSnapshot.swift` | Create | immutable render snapshot for feed and chrome |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailSnapshotAssembler.swift` | Create | maps page state to snapshot items, tokens, and chrome state |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift` | Create | `ASCollectionDataSource`, `ASCollectionDelegate`, scroll callbacks, node creation |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedUpdatePipeline.swift` | Create | item diff policy, no-op reuse, in-place updates, batch updates, full reload fallback |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailPaginationCoordinator.swift` | Create | batch fetch, near-footer probe, append retry, loading-footer retention |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailVisibilityCoordinator.swift` | Create | visible post-number debounce, scroll-target coordination, range-expansion triggers |
| `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift` | Create | root node containing feed plus topic-detail-specific bottom chrome |
| `native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift` | Create | UIKit/Texture bottom input owned by the page runtime |
| `native/ios-app/App/Routing/FireAppRouteDestinationView.swift` | Modify | swap active `.topic` destination to the controller host |
| `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift` | Modify | consume cached layout data, remove synchronous precise measurement from the hot path |
| `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift` | Modify | become active-path layout authority, publish layout revisions for visible relayout |
| `native/ios-app/App/Stores/FireTopicDetailStore.swift` | Modify | keep ownership, add any missing page-consumption hooks only if the new controller requires them |
| `native/ios-app/App/Views/Detail/FireTopicDetailView.swift` | Retire from active path | historical SwiftUI page owner, no longer the topic-detail route target |
| `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListHost.swift` | Retire from active path | old `UIViewControllerRepresentable` runtime bridge |
| `docs/architecture/ios-topic-detail-uikit-texture-design.md` | Create | active architecture and technical-design authority |
| `docs/architecture/plans/ios-topic-detail-uikit-texture-execution-plan.md` | Create | active execution checklist |
| `docs/architecture/plans/ios-topic-detail-feed-rewrite-iglistkit-texture-nuke-rust-cache-plan.md` | Modify | mark as superseded historical plan |
| `docs/architecture/ios-topic-detail-loading-and-notification-routing.md` | Modify | add status note pointing to the new redesign docs |

---

### Task 1: Create the new TopicDetail module skeleton

**Files:**

- Create: `native/ios-app/App/TopicDetail/Host/FireTopicDetailControllerHost.swift`
- Create: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Create: `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift`
- Modify: `native/ios-app/App/Routing/FireAppRouteDestinationView.swift`
- Modify: `native/ios-app/Fire.xcodeproj/project.pbxproj` or regenerate through XcodeGen if needed

- [ ] Create the `App/TopicDetail/Host`, `Controller`, `State`, `Feed`, and `Nodes` directories.
- [ ] Add a thin `FireTopicDetailControllerHost` that conforms to `UIViewControllerRepresentable` and only passes immutable route input into the controller.
- [ ] Add a minimal `FireTopicDetailViewController` that can be initialized with `FireAppViewModel`, `FireTopicRowPresentation`, and an optional `scrollToPostNumber`.
- [ ] Add a minimal `FireTopicDetailRootNode` that owns an `ASDisplayNode` root and a placeholder feed container node.
- [ ] Swap `FireAppRouteDestinationView` so `.topic(...)` routes to the new host instead of `FireTopicDetailView`.
- [ ] Keep the old page implementation reachable only through temporary internal wiring if needed during migration, not through the app route path.
- [ ] Verify the project generates cleanly:

```bash
xcodegen generate --spec native/ios-app/project.yml
```

- [ ] Verify the app builds after route rewiring:

```bash
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

- [ ] Commit:

```bash
git commit -m "refactor(ios): add topic detail controller host skeleton"
```

---

### Task 2: Move page lifecycle and route hosting to UIKit

**Files:**

- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`
- Create: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift`
- Modify: `native/ios-app/App/Stores/FireTopicDetailStore.swift` only if new lifecycle hooks are required

- [ ] Move topic-detail lifecycle ownership from `FireTopicDetailView` into the controller:
  - `beginTopicDetailLifecycle(...)`
  - `endTopicDetailLifecycle(...)`
  - initial `loadTopicDetail(...)`
  - `maintainTopicDetailSubscription(...)`
- [ ] Move `FireTopicTimingTracker` ownership into the controller so reading interactions are tied to controller appearance and disappearance instead of SwiftUI `View` lifecycle.
- [ ] Move route-anchor and pending-scroll-target ownership into the controller input path and keep `markScrollTargetSatisfied(...)` on the controller side.
- [ ] Add `FireTopicDetailToolbarCoordinator` and make the controller the owner of share/bookmark/topic actions instead of SwiftUI toolbar modifiers.
- [ ] Keep behavior parity before touching feed internals: initial load, mutation refresh, message-bus subscription, and pending-scroll-target handling must still work.
- [ ] Verify focused store behavior by running the topic-detail store tests:

```bash
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FireTopicDetailStoreTests test
```

- [ ] Commit:

```bash
git commit -m "refactor(ios): move topic detail lifecycle into controller"
```

---

### Task 3: Introduce page snapshot assembly and controller subscriptions

**Files:**

- Create: `native/ios-app/App/TopicDetail/State/FireTopicDetailPageState.swift`
- Create: `native/ios-app/App/TopicDetail/State/FireTopicDetailPageSnapshot.swift`
- Create: `native/ios-app/App/TopicDetail/State/FireTopicDetailSnapshotAssembler.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`

- [ ] Define `FireTopicDetailPageState` as the controller-local state structure that combines store-backed data with page-local ephemeral UI state.
- [ ] Define `FireTopicDetailPageSnapshot` as an immutable render description for:
  - toolbar state
  - quick reply state
  - runtime feed items
  - notices
  - pending scroll target
  - current topic-detail presentation affordances
- [ ] Implement `FireTopicDetailSnapshotAssembler` so it builds stable item `id`, `contentToken`, and `inPlaceUpdateToken` values from the current store-backed page state.
- [ ] Replace the closure-heavy `FireTopicDetailRuntimeConfiguration` usage on the active route with controller-owned action methods plus immutable snapshot consumption.
- [ ] Make controller subscriptions explicit: when relevant store publications change, rebuild page state, assemble a new snapshot, and hand it to the feed pipeline.
- [ ] Add or update unit tests for:
  - stable item identity
  - `contentToken` changes only when structural render output changes
  - `inPlaceUpdateToken` changes for local affordance updates

```bash
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FireTopicDetailRuntimeTests test
```

- [ ] Commit:

```bash
git commit -m "refactor(ios): assemble immutable topic detail page snapshots"
```

---

### Task 4: Split feed controller, update pipeline, and pagination coordinators

**Files:**

- Create: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift`
- Create: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedUpdatePipeline.swift`
- Create: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailPaginationCoordinator.swift`
- Create: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailVisibilityCoordinator.swift`
- Modify: `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListViewController.swift` as source material to split, then retire from the active path

- [ ] Move raw `ASCollectionNode` data source and delegate ownership into `FireTopicDetailFeedController`.
- [ ] Move update policy into `FireTopicDetailFeedUpdatePipeline` and preserve the four explicit modes:
  - no-op
  - visible in-place update
  - small animated batch
  - full reload
- [ ] Move batch-fetch, footer-distance probe, append retry, and loading-footer retention into `FireTopicDetailPaginationCoordinator`.
- [ ] Move visible-post publication, debounce, and pending-scroll-target handling into `FireTopicDetailVisibilityCoordinator`.
- [ ] Switch the active data source to `collectionNode:nodeBlockForItemAtIndexPath:` and ensure all payload needed by the node block is precomputed and thread-safe before returning the block.
- [ ] Preserve the existing runtime guarantees:
  - unchanged snapshots do not trigger updates
  - active scrolling suppresses gratuitous animation
  - accepted load-more requests set `loadingMore` immediately
- [ ] Verify runtime tests after the split:

```bash
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FireTopicDetailRuntimeTests test
```

- [ ] Commit:

```bash
git commit -m "refactor(ios): split topic detail feed coordination"
```

---

### Task 5: Activate FirePostLayoutManager and remove synchronous post measurement from the scroll path

**Files:**

- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift`
- Modify: `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayout.swift`
- Modify: `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift`

- [ ] Make `FirePostLayoutManager` the active-path precise layout authority for topic-detail post rows.
- [ ] Ensure the feed controller eagerly enqueues layout calculations for:
  - newly visible post rows
  - preload-range post rows
  - pending-scroll-target rows
- [ ] Remove precise rich-text overflow measurement from `FirePostCellNode.layoutSpecThatFits`.
- [ ] Replace node-local precision decisions with cached layout data and a cheap placeholder fallback when no layout is ready yet.
- [ ] Publish layout revisions from the layout manager and relayout only visible rows whose layout keys are affected.
- [ ] Preserve generation-based stale-result dropping and duplicate enqueue suppression.
- [ ] Verify the layout manager suite and row-layout suite:

```bash
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FirePostLayoutManagerTests -only-testing:FireTests/FirePostCellLayoutCalculatorTests test
```

- [ ] Confirm by profiling that precise rich-text measurement no longer runs on the hot scroll path.
- [ ] Commit:

```bash
git commit -m "perf(ios): activate topic detail layout manager"
```

---

### Task 6: Rewrite page-owned modal and input surfaces in UIKit

**Files:**

- Create: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift`
- Create: `native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift`
- Modify: `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift`
- Modify: `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift`

- [ ] Move quick reply from SwiftUI `TextField` plus `safeAreaInset` into `FireTopicQuickReplyBarNode`.
- [ ] Move page-owned alert and sheet presentation into `FireTopicDetailModalRouter`:
  - delete confirmation
  - flag flow
  - topic voters
  - reply overflow
  - image viewer
- [ ] Keep shared cross-feature destinations reusable if needed, but launch them from UIKit ownership instead of SwiftUI topic-detail modifiers.
- [ ] Ensure keyboard focus, submit, and cancellation flows are controller-owned and survive feed updates without re-binding to SwiftUI view identity.
- [ ] Verify the manual flows on device or simulator:
  - quick reply send
  - delete post
  - open reply overflow
  - open image viewer
  - open topic voters
- [ ] Commit:

```bash
git commit -m "refactor(ios): move topic detail overlays to uikit"
```

---

### Task 7: Remove old active-path SwiftUI topic-detail surfaces and sync docs

**Files:**

- Modify or retire: `native/ios-app/App/Views/Detail/FireTopicDetailView.swift`
- Modify or retire: `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListHost.swift`
- Create: `docs/architecture/ios-topic-detail-uikit-texture-design.md`
- Create: `docs/architecture/plans/ios-topic-detail-uikit-texture-execution-plan.md`
- Modify: `docs/architecture/plans/ios-topic-detail-feed-rewrite-iglistkit-texture-nuke-rust-cache-plan.md`
- Modify: `docs/architecture/ios-topic-detail-loading-and-notification-routing.md`

- [ ] Remove the old active route dependency on `FireTopicDetailView`.
- [ ] Remove the need for the old `UIViewControllerRepresentable` list host on the active path.
- [ ] Delete all "defer callbacks to avoid SwiftUI mid-update publication" logic that existed only because the page state was owned by SwiftUI.
- [ ] Keep any historical files only if they are no longer part of the route path and are clearly marked as legacy.
- [ ] Write and land the new design doc and execution plan as the active documentation authority.
- [ ] Add a superseded banner to the older IGList-centered plan and a status note to the historical runtime doc.
- [ ] Verify docs and route cleanup:

```bash
git diff --cached --check
```

- [ ] Commit:

```bash
git commit -m "docs(ios): sync topic detail redesign plan"
```

---

## Verification Matrix

| Area | Verification |
| --- | --- |
| build generation | `xcodegen generate --spec native/ios-app/project.yml` completes without project-generation errors |
| topic-detail unit tests | `FireTopicDetailRuntimeTests`, `FirePostCellLayoutCalculatorTests`, `FirePostLayoutManagerTests`, and `FireTopicDetailStoreTests` pass |
| deep-link anchor | opening a topic route with `postNumber` lands on the correct floor and clears the pending target after success |
| pagination anchor preservation | appending reply pages does not jump back to the top or collapse already visible appended rows |
| long-text expansion | tapping `... 展开` expands the target row without broad list churn |
| reaction and poll mutations | local mutation state updates visible rows in place without broad row replacement |
| quick reply | send, cancel, and keyboard focus remain stable during list updates and scrolling |
| Cloudflare recovery | recovery-driven refresh restores the topic-detail page without breaking the current runtime snapshot |
| FPS and main-thread profiling | Instruments or `xctrace` confirms precise rich-text measurement is no longer on the hot scroll path and the list does not fall back to hosted SwiftUI row rendering |

Manual profiling note:

- Capture an instrumented long-thread scroll trace after Task 5 and confirm the
  main-thread hotspot is not `measureRichTextHeight(...)` or equivalent
  synchronous precise post sizing.
