# iOS Home and Topic Detail List Host Plan

Status: initial implementation landed on `refactor/ios-listkit-topic-host` (2026-04-19)

## Summary

We want smoother, more controllable high-volume list surfaces on iOS without
changing the current visual design of the home feed or topic detail screen.
The right direction is not a fresh SwiftUI `List` rewrite. The home feed has
already moved to the collection-host ListKit path, and that path is the one
that matches our performance goals: explicit visible-item reporting, diffable
updates, cache control, scroll-metric driven prefetch, and predictable gesture
arbitration.

The main migration target was topic detail. That host swap has now landed in
code on top of the existing home/ListKit foundation. The remaining work is
cleanup and hardening: trim legacy in-file scroll-stack helpers that are no
longer on the runtime path, expand verification, and continue tightening the
shared host contract.

## Implemented Slice

The current branch now includes the core migration described in this plan:

- `native/ios-app/App/ListKit/FireDiffableListController.swift` and
  `native/ios-app/App/ListKit/FireCollectionHost.swift` now expose a generic
  one-shot scroll-request path so a screen can wait for a target item to enter
  the diffable snapshot and then scroll it into view.
- topic detail now renders through
  `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
  instead of the old `ScrollViewReader -> ScrollView -> LazyVStack` body path.
- topic detail visible-post reporting and preload triggering now come from the
  ListKit visible-item callback instead of geometry preference frames.
- route target scrolling now resolves a pending post number to a typed
  collection item and clears the pending target after the host completes the
  scroll request.
- topic detail keeps the existing SwiftUI shell for navigation, toolbar,
  sheets, fullscreen covers, and the bottom quick-reply bar.
- the migration reuses the existing topic row/post row styling and swipe to
  reply container so the visual design and gesture reservation stay intact.

## Current State

### Home

- `native/ios-app/App/FireHomeView.swift` already keeps navigation, sheets,
  toolbar, and pagination ownership in SwiftUI.
- `native/ios-app/App/ListKit/Home/FireHomeCollectionView.swift` already renders
  the hot-path feed content through the shared collection-backed host.
- `native/ios-app/App/ListKit/FireDiffableListController.swift` already provides:
  - diffable snapshot application
  - visible-item publication
  - scroll-metric publication
  - refresh-control bridging
  - scroll-anchor preservation across updates
  - explicit scroll requests for target items that appear after a snapshot update
- Remaining home work is refinement, not first migration.

### Topic Detail

- `native/ios-app/App/FireTopicDetailView.swift` now keeps the SwiftUI shell,
  but its body content is rendered through
  `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`.
- Visibility and preload now depend on ListKit visible-item publication instead
  of SwiftUI geometry preference reporting.
- Anchored route scrolling now resolves a post number to a typed collection
  item and uses the shared host scroll-request callback to clear the pending
  target.
- The screen already has the right state split for migration:
  - `FireTopicDetailStore` owns loading, range expansion, and hydration
  - `FireTopicPresentation` owns row metadata derivation
  - the view mostly owns composition and gesture wiring
- The remaining work is cleanup and hardening, not first-host migration.

## Goals

- Keep the current visual hierarchy and styling for both screens.
- Standardize high-volume reading surfaces on one list-host foundation.
- Improve smoothness under refresh, append, live updates, and anchored jumps.
- Expose explicit visible-item state for hydration, metrics, and future caching.
- Reduce SwiftUI layout churn in topic detail during incremental post loading.
- Preserve stable route, pagination, and reply-target behavior.

## Non-Goals

- No redesign of topic rows or post rows.
- No rewrite to plain SwiftUI `List` if it weakens gesture control or visible-item
  reporting.
- No same-slice rewrite of data ownership across Rust and Swift beyond what topic
  detail already trimmed in the recent UniFFI payload reduction.
- No broad migration of every list-like surface in this slice. Notifications,
  PM history, bookmarks, and search can follow after home and topic detail share
  the same mature host.

## Architectural Decision

Use the existing ListKit collection host as the standard list foundation.

Reasoning:

- It already powers home successfully.
- It exposes the control points we actually care about:
  - visible items
  - scroll metrics
  - diffable updates
  - refresh control
  - scroll anchor restore policy
- It avoids SwiftUI `List` limitations around row lifecycle ambiguity,
  separators/insets, gesture conflicts, and limited visibility hooks.
- It lets us keep the screen shell in SwiftUI while moving only the hot-path
  body into the list host.

## Scope Split

### 1. Home Refinement

Home is already on the right host, so this work is a consolidation pass:

- extract any home-specific controller behavior that topic detail will need into
  generic ListKit primitives
- make visible-item publication stable enough for both home and topic detail
- tighten row identity and snapshot policy so live list patches do not cause
  unnecessary scroll-anchor work
- keep category/filter chrome visually unchanged while preserving current
  section composition

Deliverable: home stays visually identical, but the host APIs become reusable
enough that topic detail can adopt them without screen-specific hacks.

### 2. Topic Detail Host Migration

Topic detail moves onto the shared list host as one continuous reading surface.

The target surface remains:

- topic header
- original post block
- replies header / placeholder rows
- loaded reply rows
- append/loading/footer rows

The migration must preserve:

- current post-row styling and thread-depth chrome
- `scrollToPostNumber` anchored jumps
- swipe-to-reply gesture behavior and back-swipe reservation
- visibility-driven preload and timing reporting
- pull-to-refresh
- bottom quick-reply bar outside the scroll content

## Proposed Execution Plan

### Phase 0. Baseline and Guardrails

- Record current home and topic-detail behavior as the baseline:
  - scroll-anchor stability
  - refresh behavior
  - append behavior
  - anchored open to a target post
  - reply swipe behavior
- Add focused unit coverage where host-independent policy exists:
  - topic-detail item identity
  - section/item modeling
  - visible-range to preload request mapping
  - scroll-anchor restore policy

Exit criteria:

- current home and topic-detail behavior is described concretely enough that
  host migration can be judged against it

### Phase 1. Shared ListKit Capability Lift

Status: implemented in the current branch.

- extend `FireDiffableListController` with the controller outputs topic detail
  needs:
  - stable visible-item publication by item identity
  - explicit callback when a specific target item becomes renderable
  - configurable anchor-restore policy for partial snapshot updates
- keep these additions generic and host-level, not topic-detail specific
- avoid moving topic-detail business logic into the controller

Exit criteria:

- home still behaves the same
- topic detail can consume the new controller APIs without geometry-preference
  hacks as its long-term dependency

### Phase 2. Topic Detail List Modeling

Status: implemented in the current branch.

- introduce typed topic-detail section/item models under ListKit or a dedicated
  topic-detail list adapter layer
- use stable IDs for:
  - header section items
  - original post
  - reply placeholders
  - reply rows keyed by post number/post id
  - append/loading/footer rows
- build snapshots from `FireTopicDetailRenderState` and `FireTopicDetailStore`
  state without re-deriving heavy presentation work inside the view body

Exit criteria:

- topic detail can be described as a pure section/item snapshot over existing
  store output

### Phase 3. Topic Detail Host Swap

Status: implemented in the current branch.

- replace `ScrollView` + `LazyVStack` with a topic-detail collection host
- keep the SwiftUI screen shell for:
  - navigation title and toolbar
  - sheets and fullscreen covers
  - quick reply bar / safe-area inset
  - high-level route task wiring
- move row rendering and list mechanics into the collection host

Exit criteria:

- screen behavior matches the old surface with the new host
- visible-post reporting comes from the host instead of geometry preferences

### Phase 4. Cleanup and Hardening

Status: partially remaining.

- delete geometry-preference visibility tracking that the host replaces
- delete migration-only compatibility glue
- tighten snapshot update batching for MessageBus/live state changes
- document the host contract so later surfaces can migrate consistently

Exit criteria:

- topic detail no longer depends on the old scroll-stack path
- shared list host responsibilities are documented and stable

## Topic Detail Design Constraints

These are non-negotiable for the migration:

1. One scroll surface.
   The topic header and replies must remain part of one continuous list.

2. Stable target scrolling.
   Route/comment jumps must continue to retry until the target row exists.

3. Gesture correctness.
   Reply swipe cannot regress iOS back navigation behavior.

4. Visibility-driven hydration.
   Preload should use explicit host visible items rather than ad hoc geometry
   thresholds.

5. Style preservation.
   Default collection/list chrome must be neutralized so the result still looks
   like the current Fire reading surface.

6. Quick reply isolation.
   The composer stays outside the scrolling row hierarchy.

## Risks

### Gesture Regressions

Topic detail currently has custom swipe arbitration. A host swap can easily
break back navigation or reply swipe.

Mitigation:

- migrate the row container and gesture policy together
- verify with targeted interaction tests before removing the old path

### Anchor / Jump Regressions

Topic detail correctness depends on route anchors and delayed row availability.

Mitigation:

- keep stable item IDs by post number
- add an explicit “target became renderable” callback path from the host

### UI Drift

List/collection defaults can introduce spacing, separator, and background drift.

Mitigation:

- reuse existing row views
- keep styling in SwiftUI row composition rather than controller defaults

### Premature Generalization

Trying to solve every list surface in the same slice will slow delivery.

Mitigation:

- stop at home refinement + topic detail migration
- migrate other screens only after the shared host contract is proven

## Verification Plan

### Unit / Focused Tests

- section/item identity stability
- visible-item to preload mapping
- scroll-anchor restore policy
- topic-detail route target resolution

### Manual / Simulator Verification

- home feed refresh and append
- home filter changes without scroll jumps
- topic detail open from home and from anchored notification routes
- topic detail scroll-to-post after partial initial payload
- topic detail swipe-to-reply and back-swipe coexistence
- topic detail quick reply bar stability during scroll and keyboard changes

### Performance Checks

- no visible jump on diffable updates
- lower layout churn during topic-detail incremental hydration
- stable frame pacing during long-topic scrolls
- bounded memory growth while opening and leaving multiple topic-detail screens

## Recommended First Slice

Start with topic detail host migration on top of the existing home/ListKit
foundation rather than reworking home again first.

Concretely:

1. Lift the small missing host APIs out of home-specific code.
2. Build a topic-detail section/item adapter over current store/render state.
3. Swap the topic-detail body host while preserving the existing shell.
4. Use home only as the reference implementation and regression baseline.

This gets the biggest UX improvement on the screen that still pays the most
SwiftUI scroll-stack cost, while keeping the already-migrated home surface
stable.