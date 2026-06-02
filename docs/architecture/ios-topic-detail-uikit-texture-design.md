# iOS Topic Detail Redesign: Pure UIKit + Texture

This document is the active redesign specification for the iOS topic-detail
screen. It replaces the older IGListKit-centered redesign direction and is
written for cross-platform engineers who may not be familiar with iOS runtime
details.

The target outcome is a single authoritative topic-detail reading path built on
`UIViewController`, `ASCollectionNode`, `ASCellNode`, and page-owned UIKit
state. SwiftUI remains only as a route host bridge in the surrounding app
navigation.

## Summary

The current topic-detail runtime already uses Texture for the scrolling surface,
but the page is still owned by a SwiftUI state tree:

- `FireAppRouteDestinationView` pushes `FireTopicDetailView`
- `FireTopicDetailView` owns page state, lifecycle tasks, bottom input, and
  modal presentation
- `FireTopicDetailListHost` bridges into `FireTopicDetailListViewController`
- `FireTopicDetailListViewController` owns the Texture `ASCollectionNode`

That mixed ownership has three concrete costs:

1. The scrolling surface is Texture, but state publication still has to avoid
   SwiftUI update-pass hazards.
2. Page-owned UI such as quick reply, sheets, and alerts still depends on
   SwiftUI state lifetimes instead of controller lifetimes.
3. `FirePostCellNode.layoutSpecThatFits` still performs precise rich-text
   overflow measurement on the hot path instead of relying on the background
   layout cache service.

The redesign keeps the existing Rust/store ownership model and replaces only the
iOS page runtime architecture.

## Feasibility Assessment

This redesign is fully feasible in the current repository state.

- Fire already links Texture directly through
  `native/ios-app/LocalPackages/TextureCore/Artifacts/AsyncDisplayKit.xcframework`
  and wires it in `native/ios-app/project.yml`.
- The active topic-detail runtime already uses `ASCollectionNode`,
  `ASCellNode`, `ASTextNode`, and `ASNetworkImageNode`.
- The remaining work is not a dependency spike. It is an ownership cleanup and
  active-path replacement that reorganizes where state, layout, and controller
  responsibilities live.
- The older redesign direction that treated IGListKit as the primary container
  is no longer aligned with the current repo state or the desired end-state.

Official source facts that shape this decision:

- Texture's current public podspec still declares `spec.version = '3.2.0'` and
  exposes `Core`, `PINRemoteImage`, and `IGListKit` subspecs, while
  `Texture/IGListKit` still depends on `IGListKit ~> 4.0`:
  <https://raw.githubusercontent.com/TextureGroup/Texture/master/Texture.podspec>
- Texture documents `ASCollectionNode`, `ASTextNode`, intelligent preloading,
  automatic subnode management, and collection asynchronous updates as first
  class capabilities:
  <https://texturegroup.org/docs/getting-started.html>
- IGListKit's official Vision page defines its core scope as data-driven lists,
  state management, and diffing, and explicitly lists sizing/layout, render and
  display pipelines, and third-party integration as outside its scope:
  <https://instagram.github.io/IGListKit/vision.html>

## Reader Orientation

The redesign maps naturally to Android list-runtime concepts:

| iOS object | Android mental model | Responsibility |
| --- | --- | --- |
| `FireTopicDetailStore` | ViewModel plus repository-facing state holder | owns topic-detail entities, cursors, refresh state, message-bus refresh, mutation refresh, and visibility-driven hydration |
| `FireTopicDetailSnapshotAssembler` | UI model mapper | converts store dictionaries and page-local state into immutable page snapshots |
| `FireTopicDetailFeedController` | `RecyclerView.Adapter` plus scroll coordinator | owns list data source, scroll callbacks, batch fetch, visible-item publication, and list update application |
| `FirePostLayoutManager` | background measurement and layout cache service | computes rich-text, image, and poll layout off the scroll path and publishes layout revisions |
| `ASCollectionNode` | `RecyclerView` plus async cell pipeline | container that owns Texture node lifecycle, interface state, and asynchronous measurement/update behavior |
| `FirePostCellNode` | custom `RecyclerView.ViewHolder` item renderer | authoritative renderer for original posts and replies |

## Current Surface Inventory

The current active path is spread across these files:

- `native/ios-app/App/Routing/FireAppRouteDestinationView.swift`
- `native/ios-app/App/Views/Detail/FireTopicDetailView.swift`
- `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListHost.swift`
- `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListViewController.swift`
- `native/ios-app/App/TopicDetailRuntime/FireTopicDetailFeedRuntimeModels.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift`
- `native/ios-app/App/Stores/FireTopicDetailStore.swift`

Important current facts:

- `FireTopicDetailView` still owns `@State` for quick reply, image viewer,
  sheets, flags, route pushes, and lifecycle task IDs.
- `FireTopicDetailListHost` is a `UIViewControllerRepresentable` wrapper whose
  only job is to feed a runtime configuration into the controller.
- `FireTopicDetailListViewController` still contains deferred callback logic
  specifically to avoid mutating SwiftUI-owned state during the host update pass.
- `FirePostLayoutManager` exists, already supports background layout
  computation, and has tests, but it is not the active-path layout authority.
- `FirePostCellNode.layoutSpecThatFits` still calls
  `FirePostCellLayoutCalculator.measureRichTextHeight(...)` through
  `shouldSuppressAttachmentsForCollapsedText(...)` when deciding overflow and
  collapsed-media suppression.

## Non-Negotiable Decisions

1. Topic-detail repeated post rows keep one authoritative renderer:
   `FirePostCellNode`.
2. The active topic-detail path must not reintroduce SwiftUI row fallbacks,
   `UIHostingController`, or `UIHostingConfiguration`.
3. The physical list container remains `ASCollectionNode`.
4. The redesign does not use `IGListAdapter` or `ASSectionController`.
5. Rust ownership is unchanged: session state, bootstrap parsing, API
   orchestration, MessageBus, shared models, networking integration, and logging
   integration remain Rust-owned.
6. The host-side store contract is unchanged: `FireTopicDetailStore` remains the
   state source of truth for the page.
7. `FirePostLayoutManager` becomes the active-path layout authority for precise
   post measurement.
8. Page-owned topic-detail surfaces become UIKit-owned even if some
   cross-feature shared screens remain temporarily reusable existing
   implementations.

## Why IGListKit Is Not the Active Path

IGListKit is not the right center of gravity for this redesign.

The key reason is scope. IGListKit's official Vision document says the library's
core goal is building fast, stable, data-driven lists and includes:

- `UICollectionView` and `UITableView` integrations
- data and state management
- diffing algorithms

The same page explicitly lists these as outside IGListKit scope:

- advanced or custom collection layouts
- sizing and layout
- render and display pipelines
- integration with third parties

That boundary is a direct mismatch for Fire topic detail, where the hard
problems are:

- post-row rendering
- rich-text measurement
- preloading and interface state
- fast native updates under heavy scroll
- image and poll display inside complex cells

Texture already owns exactly those capabilities. Official Texture docs position
nodes as thread-safe, background-creatable render primitives and `ASCollectionNode`
as the integration point between UIKit and Texture. The current repo already
uses that model.

The Texture podspec reinforces the same conclusion: its `Texture/IGListKit`
subspec still pins IGListKit `~> 4.0`, while current upstream IGListKit docs are
generated for `5.2.0`. That is not a safe foundation for a new authoritative
runtime path.

The redesign therefore keeps list diffing local to the topic-detail runtime item
pipeline instead of delegating the container to IGListKit.

## Target Runtime Architecture

The target runtime shape is:

```text
SwiftUI app navigation
  FireAppRouteDestinationView
    -> FireTopicDetailControllerHost
         -> FireTopicDetailViewController
              -> FireTopicDetailRootNode
                   -> ASCollectionNode (feed)
                   -> FireTopicQuickReplyBarNode

Topic-detail state pipeline
  FireTopicDetailStore
    -> FireTopicDetailPageState
    -> FireTopicDetailSnapshotAssembler
    -> FireTopicDetailPageSnapshot
    -> FireTopicDetailFeedUpdatePipeline
    -> FireTopicDetailFeedController

Layout pipeline
  FireTopicDetailFeedController
    -> FirePostLayoutManager.enqueueCalculation(...)
    -> background layout queue
    -> layout revision publish
    -> visible FirePostCellNode relayout
```

Ownership boundaries:

- `FireTopicDetailControllerHost` is only a route bridge.
- `FireTopicDetailViewController` owns the page lifecycle.
- `FireTopicDetailRootNode` owns page chrome layout.
- `FireTopicDetailFeedController` owns scrolling and item application.
- `FireTopicDetailStore` owns topic entities and refresh state.
- `FirePostLayoutManager` owns precise post measurement and layout caching.

## File Architecture

The redesign introduces a dedicated `App/TopicDetail/` module and retires the
old active-path host files.

| File | Action | Responsibility |
| --- | --- | --- |
| `native/ios-app/App/TopicDetail/Host/FireTopicDetailControllerHost.swift` | Create | thin route bridge from SwiftUI into the controller |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailViewController.swift` | Create | page coordinator, lifecycle, subscriptions, quick reply state, toolbar, router wiring |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailModalRouter.swift` | Create | UIKit-owned present/push routing for page-owned flows |
| `native/ios-app/App/TopicDetail/Controller/FireTopicDetailToolbarCoordinator.swift` | Create | share, bookmark, topic actions, notification-level menu coordination |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailPageState.swift` | Create | controller-local page state composed from store plus ephemeral UI state |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailPageSnapshot.swift` | Create | immutable feed plus chrome snapshot consumed by nodes/controllers |
| `native/ios-app/App/TopicDetail/State/FireTopicDetailSnapshotAssembler.swift` | Create | page-state to snapshot mapper, identity tokens, item assembly |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedController.swift` | Create | `ASCollectionDataSource`, `ASCollectionDelegate`, scroll callbacks, node creation |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailFeedUpdatePipeline.swift` | Create | no-op, in-place update, batch update, full reload decision logic |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailPaginationCoordinator.swift` | Create | batch-fetch, footer-distance probe, retry/restore-footer handling |
| `native/ios-app/App/TopicDetail/Feed/FireTopicDetailVisibilityCoordinator.swift` | Create | visible-post debounce, scroll-target handling, range expansion triggers |
| `native/ios-app/App/TopicDetail/Nodes/FireTopicDetailRootNode.swift` | Create | root node holding feed plus bottom input and page-owned chrome |
| `native/ios-app/App/TopicDetail/Nodes/FireTopicQuickReplyBarNode.swift` | Create | UIKit/Texture quick reply UI owned by the page runtime |
| `native/ios-app/App/Views/Detail/FireTopicDetailView.swift` | Retire from active path | historical SwiftUI page owner, no longer the main topic-detail runtime |
| `native/ios-app/App/TopicDetailRuntime/FireTopicDetailListHost.swift` | Retire from active path | `UIViewControllerRepresentable` host used only by the old runtime |

Existing files that remain authoritative and are reused:

- `native/ios-app/App/Stores/FireTopicDetailStore.swift`
- `native/ios-app/App/TopicDetailRuntime/FireTopicDetailFeedRuntimeModels.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellNode.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayout.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayoutCalculator.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift`

## Data Ownership and Flow

The redesign keeps state ownership explicit:

| Layer | Owned by | Contents |
| --- | --- | --- |
| network/session/bootstrap/message bus | Rust core and UniFFI session store | cookies, bootstrap, API orchestration, shared models, message-bus channels |
| page entities and fetch state | `FireTopicDetailStore` | `TopicDetailState`, render state, post lookup, pagination cursor, loading flags, notices, AI summary, reply context state |
| page-local ephemeral UI state | `FireTopicDetailViewController` | quick reply draft, currently presented modal, selected route, current filter route, current image viewer state |
| immutable render model | `FireTopicDetailPageSnapshot` | toolbar state, quick reply state, list items, runtime invalidation tokens, pending scroll target |
| precise layout cache | `FirePostLayoutManager` | `FirePostCellLayoutKey -> FirePostCellLayout`, in-flight layout keys, revision counter |
| item-local display state | `FirePostCellNode` and auxiliary nodes | current payload, current callbacks, gesture state, temporary image view state |

Data flow is one directional:

1. `FireTopicDetailStore` changes published topic-detail state.
2. `FireTopicDetailViewController` receives the relevant publication.
3. The controller builds `FireTopicDetailPageState`.
4. `FireTopicDetailSnapshotAssembler` maps state to immutable
   `FireTopicDetailPageSnapshot`.
5. `FireTopicDetailFeedUpdatePipeline` compares the new snapshot to the active
   snapshot.
6. `FireTopicDetailFeedController` applies the chosen update mode to
   `ASCollectionNode`.
7. Visible post nodes receive payload reconfiguration only when their
   `inPlaceUpdateToken` changes.

## Update Pipeline

The feed update system uses four explicit modes.

### 1. No-op snapshot reuse

If the page snapshot invalidation token and item content are unchanged, the feed
does nothing beyond checking pending scroll targets and any deferred page-owned
actions.

Use when:

- store published unrelated state
- visible rows did not change
- page-owned state not represented in the feed did not affect item tokens

### 2. Visible in-place node reconfigure

If item identity and `contentToken` are unchanged but `inPlaceUpdateToken`
changes, the feed reconfigures only currently visible nodes.

Use when:

- reaction selection state changes
- reply context loading flag changes
- mutation busy state changes
- a post's local affordance changes without requiring relayout identity churn

### 3. Small animated batch update

If the feed structure changes but the delta is small and the user is not
actively scrolling, the feed uses `performBatch(...)` with insert/delete/reload
index paths.

Use when:

- a reply page appends a small number of items
- a notice row appears or disappears
- a footer changes between `loadMore` and `loadingFooter`

### 4. Full reload

If the feed is attaching for the first time, the width signature changes, or
the diff is broad enough that anchor preservation and visible relayout become
harder than a full reset, the feed uses `reloadData`.

Use when:

- first page render
- page rotation or inset-width change
- broad snapshot replacement
- the collection is not attached or is already processing incompatible updates

### Identity rules

- `id` is the durable item identity.
- `contentToken` decides whether the row's structural render output changed.
- `inPlaceUpdateToken` decides whether an already-rendered visible node needs a
  payload refresh without structural row replacement.

### Node creation path

The target data-source path is `collectionNode:nodeBlockForItemAtIndexPath:`.
The controller must prepare thread-safe payload inputs before returning the
block. The block may instantiate and configure `ASCellNode` subclasses on a
background queue.

## Threading and Measurement Model

### Main-thread responsibilities

- UIKit navigation and controller lifecycle
- store mutation requests
- page snapshot assembly
- list update submission to `ASCollectionNode`
- applying published layout revisions to visible nodes

### Background-thread responsibilities

- Texture node creation through `nodeBlockForItemAtIndexPath`
- `FirePostLayoutManager` layout calculation
- rich-text sizing
- image frame sizing
- poll height calculation
- Texture internal collection update preparation

### Measurement authority

`FirePostLayoutManager` becomes the only precise layout authority for post rows.

That means:

- `FirePostCellNode.layoutSpecThatFits` may consume cached layout results
  directly.
- `layoutSpecThatFits` must not call precise rich-text measurement APIs such as
  `measureRichTextHeight(...)` to determine overflow or attachment suppression.
- If no layout is cached yet, the node uses a cheap placeholder layout or the
  best-known coarse estimate and requests background computation.

### Layout key

`FirePostCellLayoutKey` must include:

- `postID`
- `depth`
- `showsThreadLine`
- `showsDivider`
- `replyTargetPostNumber`
- `replyContext`
- `textContentID`
- `imageSignature`
- `pollSignature`
- `hasReactions`
- `replyShortcutCount`
- `textExpansionState`
- `acceptedAnswer`
- trait signature with content width pixels and content-size category

### Layout lifecycle

```text
1. snapshot assembled
2. feed decides which post rows need layout keys
3. feed enqueues calculations in FirePostLayoutManager
4. background queue computes precise layouts
5. layout manager publishes a new layout revision on MainActor
6. feed controller reconfigures and relayouts only visible post nodes that use
   the updated keys
```

### Invalidation rules

- Width changes invalidate all cached layouts through a generation bump.
- Dynamic Type changes invalidate all cached layouts through a generation bump.
- Post-content changes invalidate only affected layout keys.
- Any layout result computed for an older generation is discarded when it returns
  to the main actor.

## Pagination, Preloading, and Scroll Coordination

The redesign separates three concerns that are currently easy to blur:

1. page append requests
2. visibility-driven range expansion
3. image and node preloading

### Page append requests

Page append requests are controlled by `FireTopicDetailPaginationCoordinator`.

Triggers:

- `shouldBatchFetch(...)`
- `collectionNode(_:willBeginBatchFetchWith:)`
- explicit near-footer distance probe

Rules:

- only one append task per topic is allowed at a time
- accepted append requests synchronously mark `loadingMore`
- the footer may remain in `loadingFooter` while a follow-up request is being
  retried or resumed

### Visibility-driven range expansion

Visibility is controlled by `FireTopicDetailVisibilityCoordinator`.

Responsibilities:

- publish visible post numbers with debounce
- hand visible post sets to `FireTopicDetailStore`
- trigger requested-range expansion for hydration
- preserve pending scroll targets until the target row exists

The current 240 ms visible-post debounce remains the right starting point for
store work. It reduces publication churn while still tracking the reading
window.

### Image and node preloading

Texture owns node lifecycle and interface-state preloading.

Responsibilities:

- `ASCollectionNode` range tuning controls when nodes enter display and preload
  ranges
- `FirePostCellNode` may react to preload-state transitions if a small amount of
  local preparation is needed
- image preloading for repeated post cells stays with Texture node lifecycle and
  `ASNetworkImageNode`

That means page append networking is not triggered by image prefetch. The page
append boundary remains in the pagination coordinator.

### Scroll-target handling

- `pendingScrollTarget` stays in snapshot state until an item with the matching
  `postNumber` exists in the runtime item list
- the feed scrolls only after the target item exists
- after a successful jump, the controller calls
  `markScrollTargetSatisfied(...)`

## Rendering Policy and Offscreen Work

In this redesign, "offscreen work" has a precise meaning.

It means work that is prepared outside the hot main-thread scroll path:

- Texture node allocation and configuration through node blocks
- Texture measurement and layout preparation
- `ASTextNode` text sizing and drawing preparation
- `FirePostLayoutManager` rich-text and poll measurement
- interface-state-driven preloading before nodes become visible

It does not mean "turn on random rasterization flags and hope scrolling gets
faster."

### Allowed rendering policies

- repeated topic-detail rows are `ASCellNode` subclasses
- text-only leaf nodes should use `isLayerBacked = true` where interaction is
  not needed
- page chrome is built from Texture or UIKit primitives, not hosted SwiftUI
- placeholders are node-local and do not require whole-row snapshot replacement

### Disallowed policies

- global subtree rasterization for the whole page
- reintroducing hosted SwiftUI fallback cells
- Auto Layout driven repeated-row height calculation
- broad page reloads in response to image-only display events

### Image policy

The active repeated-row path continues to use `ASNetworkImageNode` for avatar
and inline post-image display. The redesign does not simultaneously swap the
entire repeated-row image pipeline to a custom Nuke-backed node. That keeps the
rendering migration focused on ownership and measurement first.

## Interaction and Modal Boundaries

The redesign distinguishes page-owned surfaces from reusable cross-feature
screens.

### Page-owned surfaces that must move to UIKit now

- quick reply bar
- typing presence strip
- reply overflow presentation
- topic voters presentation
- delete confirmation alert
- flag sheet
- full-screen image viewer

These surfaces are owned by the topic-detail runtime and should move under
`FireTopicDetailViewController` and `FireTopicDetailModalRouter`.

### Reusable screens that may remain existing implementations temporarily

- composer
- bookmark editor
- post editor
- topic editor
- public profile

These screens may still be presented from UIKit even if their internal
implementation remains shared and reusable for now. The key redesign constraint
is that topic detail itself no longer depends on SwiftUI state to own the
presentation.

## Phased Migration

### Phase 1: Host and controller extraction

- introduce `FireTopicDetailControllerHost`
- introduce `FireTopicDetailViewController`
- move lifecycle, task ownership, route-anchor ownership, and toolbar ownership
  out of `FireTopicDetailView`

### Phase 2: Snapshot assembly layer

- add `FireTopicDetailPageState`
- add `FireTopicDetailPageSnapshot`
- add `FireTopicDetailSnapshotAssembler`
- replace closure-heavy runtime configuration with immutable page snapshots plus
  controller-owned action methods

### Phase 3: Feed split and update pipeline

- split list-controller responsibilities into feed, update pipeline, visibility
  coordinator, and pagination coordinator
- move to `nodeBlockForItemAtIndexPath`

### Phase 4: Active layout-manager adoption

- make `FirePostLayoutManager` the precise layout authority
- remove synchronous rich-text overflow measurement from the scroll path
- publish layout revisions and relayout only affected visible post rows

### Phase 5: UIKit-owned overlays and input

- move quick reply, image viewer, reply overflow, flag sheet, alerts, and topic
  voters to UIKit-owned presentation

### Phase 6: Old path retirement

- remove `FireTopicDetailView` and `FireTopicDetailListHost` from the active
  route path
- sync documentation and verification records

## Verification Strategy

Repository checks:

- `xcodegen generate --spec native/ios-app/project.yml`
- `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
- focused topic-detail tests such as:
  - `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FireTopicDetailRuntimeTests test`
  - `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FirePostCellLayoutCalculatorTests test`
  - `xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -only-testing:FireTests/FirePostLayoutManagerTests test`

Runtime verification:

- deep-link anchor opens the correct target floor
- pagination append does not jump back to the top
- long-text expansion preserves row stability
- reaction and poll mutations do not trigger broad list churn
- quick reply remains responsive during scroll
- Cloudflare recovery refresh still returns to a coherent topic-detail state

Performance verification:

- use Instruments or `xctrace` to confirm no precise rich-text measurement
  remains on the hot scroll path
- use Texture range visualization or equivalent runtime instrumentation to tune
  display and preload buffers

## Risks and Failure Modes

### Width-signature churn

If width calculation depends on unstable inset or bounds sources, layout keys can
invalidate too often and destroy cache value.

Mitigation:

- define one authoritative content-width calculation path
- use the same width source for key generation and node layout

### Stale layout publication

If background layouts return after content or trait invalidation, old results can
apply to new content.

Mitigation:

- keep generation counters in `FirePostLayoutManager`
- discard results whose generation no longer matches

### Duplicate load-more requests

If footer probes, batch fetch, and retry logic are not unified, append requests
can race each other.

Mitigation:

- centralize append gating in `FireTopicDetailPaginationCoordinator`
- keep one in-flight append task per topic

### Visible-post churn causing excess store work

If visible-row publication is too eager, scrolling can produce excessive
hydration recalculation and message-bus-related state churn.

Mitigation:

- keep debounce on visible-post publication
- publish only when the visible post-number set actually changes

### Modal routing regressions

Moving topic-detail-owned flows from SwiftUI modifiers to UIKit presentation can
break dismissal and nested navigation if presentation rules are not centralized.

Mitigation:

- centralize page-owned presentations in `FireTopicDetailModalRouter`
- keep a single source of truth for currently presented topic-detail flows

### Partial migration ambiguity

If route hosting moves to UIKit but page-owned surfaces remain split between two
state trees, debugging gets harder instead of easier.

Mitigation:

- migrate page-owned surfaces as a single phase
- avoid long-lived dual ownership for quick reply and image viewer state
