# iOS Topic Detail Native Reply Cell Plan

Status: proposed (2026-05-28)

## Summary

We want the iOS topic-detail reading surface to keep its current visual design
and screen-level SwiftUI shell while moving the hot-path reply rows off
`UIHostingConfiguration` and onto a pure UIKit `UICollectionViewCell` path.
This is the first concrete step in a broader direction: performance-critical and
interaction-heavy reading surfaces should progressively move to UIKit/AppKit,
while SwiftUI remains the shell and orchestration layer where it is not the
scroll-time bottleneck.

The current reply path is expensive in exactly the places we care about:
`FireTopicDetailCollectionView` builds every `.reply` item as `FirePostRow`,
`FireDiffableListController` hosts that view tree inside a single hosted cell
registration, and `FireRichTextView` still relies on `UITextView` intrinsic
measurement. That means reply rows pay SwiftUI tree rebuild, hosted-cell
reconfiguration, and main-thread text self-sizing costs during scroll and
incremental hydration.

The target state is a mixed collection host:

- non-hot-path items stay on the existing hosted path
- `.reply` items that meet a native-eligibility check render through a pure
  `FirePostCollectionViewCell`
- reply height and child frames are precomputed on a background queue and
  published in coalesced batches
- poll, placeholder, and temporary layout-miss cases retain a hosted fallback
  during the first delivery slice

This plan incorporates the latest code review feedback. The biggest adjustments
from the original proposal are:

- explicitly model native and hosted cells as parallel paths inside the generic
  `FireDiffableListController`, instead of treating the native cell as a small
  extension of the existing `RowContent` generic
- add a concrete width-change callback chain from collection controller to
  SwiftUI wrapper to reply layout manager, instead of relying on rotation-only
  hooks
- keep poll rows on hosted fallback in the first slice instead of embedding a
  `UIHostingController` inside a reusable native cell
- specify the missing parity work for menu actions, accessibility,
  trait-collection handling, divider rendering, and `prepareForReuse()` cleanup

## Current State

### Reply Rendering Path

- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
  builds `.reply` items in `replyRow(for:replyIndexByPostID:)`.
- Each loaded reply is wrapped in `FireSwipeToReplyContainer` and rendered by
  `FirePostRow` from `native/ios-app/App/FireTopicDetailView.swift`.
- `FirePostRow` owns the visual contract for:
  - avatar and thread line
  - single-line metadata header
  - `FireRichTextView`
  - `FireCookedImageCard`
  - `FirePollCard`
  - reaction capsules
  - post actions menu
- The collection host still uses a single
  `UICollectionView.CellRegistration<UICollectionViewListCell, ItemID>` and
  sets `UIHostingConfiguration` for every item.

### Host and Revision Path

- `native/ios-app/App/ListKit/FireCollectionHost.swift` caches per-item content
  tokens in `Coordinator.resolveItemContentTokens(...)`, keyed by
  `sections + contentVersion`.
- `native/ios-app/App/ListKit/FireDiffableListController.swift` diffs sections,
  derives `reconfigureItems`, and applies snapshots while preserving scroll
  anchors.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` publishes a coarse
  `topicCollectionRevision` whenever detail state or render cache state changes.
- `native/ios-app/App/FireTopicDetailView.swift` listens to that revision and
  refreshes `cachedDetail` / `cachedRenderState`, so any reply-native work must
  remain compatible with the existing revision flow.

### Existing Performance Boundaries

- `native/ios-app/App/FireTopicPresentation.swift` already builds
  `FireTopicDetailRenderCache` off the main actor and exposes
  `FireTopicPostRenderContent` as the right host-owned rendering boundary.
- `native/ios-app/App/FireRichTextRenderer.swift` still measures rich text via
  `FireRichTextUIView.intrinsicContentSize`, so even with off-main HTML parsing,
  the final row size is still determined on the main thread.
- `onPrefetchItems` already exists in the collection host and is a better first
  layout-warmup signal than immediately adding more display lifecycle hooks.

## Goals

- Move common `.reply` rows in topic detail from hosted SwiftUI rows to a pure
  UIKit cell path.
- Precompute reply row height and child geometry off the main thread.
- Preserve the current visual hierarchy, reply depth chrome, swipe-to-reply
  behavior, anchored scrolling, and mutation callbacks.
- Keep the SwiftUI screen shell, topic-detail store, render-cache production,
  and Rust/UniFFI surfaces unchanged.
- Reduce scroll-time `UIHostingConfiguration` churn and hosted-row rebuilds for
  large threads.
- Establish a reusable migration pattern for other UIKit/AppKit-heavy screens.

## Non-Goals

- No redesign of the topic-detail page.
- No same-slice rewrite of `FireTopicDetailStore`, `FireTopicPresentation`, or
  any Rust/UniFFI code.
- No first-slice migration of `.originalPost`; it remains hosted because it is a
  single instance, not the repeated scroll hotspot.
- No requirement that poll rows become native in the first delivery slice.
- No same-slice rewrite of the topic-detail quick-reply bar, screen shell,
  sheets, or navigation stack.

## Review-Driven Design Corrections

### 1. Mixed Registration Must Be Explicit

`FireDiffableListController<SectionID, ItemID, RowContent: View>` remains a
single generic controller, but the native reply path must be modeled as a
parallel cell-registration path, not as a mutation of `RowContent`.

The controller must gain:

- `shouldUseNativeCell: (ItemID) -> Bool`
- `nativeCellProvider: (UICollectionView, IndexPath, ItemID) -> UICollectionViewCell?`
- an update method for both closures during `updateUIViewController`

The data source cell provider becomes:

- if `shouldUseNativeCell(itemID)` is true, ask `nativeCellProvider` for a cell
- otherwise dequeue the existing hosted `UICollectionViewListCell`

This preserves the current `RowContent` generic for non-native items and keeps
native reply cells completely parallel.

### 2. Original Post Stays Hosted in Slice 1

`.originalPost` also renders `FirePostRow` today, but it is not the first
migration target.

The plan is:

- keep `.originalPost` on the hosted path in slice 1
- keep all visual constants in the new native code aligned to the existing
  `FirePostRow` contract
- only extract shared post-row metrics if implementation drift becomes likely

That gives us the performance win where it matters without widening the first
migration surface.

### 3. Divider Rendering Must Be Manual

Choosing `UICollectionViewCell` over `UICollectionViewListCell` means reply-row
separators are now the cell's responsibility. The native cell needs an explicit
bottom divider view that is shown for every reply except the last visible reply
in the loaded sequence.

### 4. Menu Actions Must Stay on the Ellipsis Button

`FirePostRow` currently exposes a SwiftUI `Menu` behind the ellipsis icon. The
native cell should keep the same interaction model with:

- an ellipsis `UIButton`
- a `UIMenu` built from the current post permissions
- `showsMenuAsPrimaryAction = true`

That is closer to the current UX than a long-press-only context menu.

### 5. Avatar Loading Needs a UIKit Path

The native cell cannot depend on `FireAvatarView`. It should reuse the existing
avatar URL helper and the shared image pipeline to feed a plain `UIImageView`
with a circle mask and monogram fallback.

### 6. Callback Surface Must Be Explicit

The native cell needs a typed callback bundle instead of a growing list of ad hoc
closures.

```swift
struct FirePostCellCallbacks {
    let onLinkTapped: (URL) -> Void
    let onOpenImage: (FireCookedImage) -> Void
    let onToggleLike: (TopicPostState) -> Void
    let onSelectReaction: (TopicPostState, String) -> Void
    let onEditPost: (TopicPostState) -> Void
    let onBookmarkPost: (TopicPostState) -> Void
    let onDeletePost: (TopicPostState) -> Void
    let onRecoverPost: (TopicPostState) -> Void
    let onFlagPost: (TopicPostState) -> Void
    let onOpenReplyTarget: (UInt32) -> Void
    let onOpenReplies: (TopicPostState) -> Void
    let onVotePoll: (TopicPostState, PollState, [String]) -> Void
    let onUnvotePoll: (TopicPostState, PollState) -> Void
    let onSwipeReply: (TopicPostState) -> Void
}
```

### 7. Accessibility and Trait Changes Are First-Class Work

SwiftUI gives us accessibility and trait adaptation implicitly. Native reply
cells must implement them explicitly:

- labels and values for post body and metadata
- selected traits for the active reaction capsule
- accessibility labels for ellipsis menu, links, reply target, and images
- `traitCollectionDidChange` handling for color refresh and Dynamic Type-driven
  layout invalidation

### 8. Width Changes Need a Real Callback Chain

Width changes should not rely only on `viewWillTransition(to:with:)`. The
collection host already owns the actual `UICollectionView` geometry, so the
plan adds:

- width observation in `FireDiffableListController.viewDidLayoutSubviews`
- `onContentWidthChanged` passthrough in `FireCollectionHost`
- local width state in `FireTopicDetailCollectionView`
- `FirePostLayoutManager.invalidateAll(reason: .widthChanged)` when the width
  changes

That covers rotation, split view, and other bounds changes with the real
measured content width.

### 9. Layout Publication Must Trigger Token Changes

Because `FireCollectionHost.Coordinator` caches tokens by `contentVersion`, the
layout manager cannot publish per-post results silently. It must coalesce ready
layouts into a batch and bump a local `replyLayoutSnapshotRevision` that is part
of `FireTopicDetailCollectionContentVersion`.

### 10. `prepareForReuse()` Must Reset More Than Images

The native cell needs a full reuse contract:

- cancel image-loading tasks
- cancel emoji-loading tasks
- reset swipe gesture state
- clear image views
- clear text delegates if needed
- clear placeholder/skeleton state
- clear per-post menu/actions state

## Architectural Decision

Use a mixed hosted/native topic-detail collection host with a reply-local
background layout manager.

### Key Design Points

1. `.reply` is the only native item type in slice 1.
2. The native path is gated by a reply-cell eligibility matrix.
3. Layout cache keys include only geometry-affecting inputs.
4. Render payload stays separate and is applied on every rebind.
5. Width and Dynamic Type changes are explicit invalidation sources.
6. Poll and placeholder rows stay hosted until the native path is stable.
7. Text height is precomputed off-main, but the first slice still reuses the
   existing rich-text interaction behavior through a fixed-frame UIKit wrapper.

### New Core Types

```swift
struct FirePostLayoutTraitSignature: Hashable, Sendable {
    let contentWidthPixels: Int
    let contentSizeCategory: String
}

struct FirePostCellLayoutKey: Hashable, Sendable {
    let postID: UInt64
    let depth: Int
    let showsThreadLine: Bool
    let replyTargetPostNumber: UInt32?
    let replyContext: String?
    let textContentID: String
    let imageSignature: [String]
    let pollSignature: [UInt64]
    let hasReactions: Bool
    let acceptedAnswer: Bool
    let trait: FirePostLayoutTraitSignature
}

struct FirePostCellLayout: Equatable, Sendable {
    let key: FirePostCellLayoutKey
    let totalHeight: CGFloat
    let avatarFrame: CGRect
    let threadLineFrame: CGRect?
    let metaFrame: CGRect
    let textFrame: CGRect?
    let textContainerSize: CGSize
    let imageFrames: [CGRect]
    let pollFrames: [CGRect]
    let reactionsFrame: CGRect?
    let menuFrame: CGRect?
    let dividerFrame: CGRect?
}

struct FirePostCellRenderPayload {
    let post: TopicPostState
    let renderContent: FireTopicPostRenderContent
    let baseURLString: String
    let canWriteInteractions: Bool
    let isMutating: Bool
    let replyContext: String?
    let replyTargetPostNumber: UInt32?
    let showsDivider: Bool
}
```

### Native Eligibility Matrix

The first slice uses explicit reply modes:

```swift
enum FireReplyCellMode {
    case native
    case hostedPoll
    case hostedPlaceholder
    case hostedLayoutMiss
}
```

Rules:

- `post == nil` -> `.hostedPlaceholder`
- `!post.polls.isEmpty` -> `.hostedPoll`
- layout not ready on first bind -> `.hostedLayoutMiss`
- all other common reply rows -> `.native`

This keeps the first win focused on the majority path.

## Proposed Execution Plan

### Phase 0. Baseline, Metrics, and Guardrails

Files:

- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
- `native/ios-app/App/ListKit/FireDiffableListController.swift`
- `native/ios-app/App/FireTopicDetailView.swift`

Changes:

- Record the current behavior baseline for:
  - anchored scroll-to-post
  - reply swipe and back-swipe coexistence
  - load-more and hydration churn
  - reaction optimistic updates
  - poll rows and placeholder rows
- Add or expand APM signposts around reply-row configure cost if the current
  instrumentation is insufficient.
- Define success criteria before code motion begins:
  - no regression in anchored scrolling
  - no regression in swipe/back gesture arbitration
  - fewer hosted reply reconfigurations during large-thread scroll

Rationale: the migration needs a concrete before/after bar, not just a target
architecture diagram.

### Phase 1. Shared ListKit Capability Lift

Files:

- `native/ios-app/App/ListKit/FireDiffableListController.swift`
- `native/ios-app/App/ListKit/FireCollectionHost.swift`

Changes:

- Add `shouldUseNativeCell`, `nativeCellProvider`, and update methods for both.
- Keep the existing hosted `UICollectionViewListCell` registration for all
  non-native items.
- Extend the controller with `onContentWidthChanged` published from
  `viewDidLayoutSubviews` when the effective content width changes.
- Keep `onPrefetchItems` as the first pre-layout signal.
- Do not add `willDisplay` / `didEndDisplaying` yet unless the native image and
  emoji lifetime work proves it is necessary.

Rationale: the host layer must first support mixed registration and real width
reporting before the reply-native implementation can remain local and reliable.

Exit criteria:

- the collection host can render a mix of hosted and native cells
- topic detail can receive actual collection content width changes without any
  GeometryReader-specific hacks

### Phase 2. Reply Layout Modeling and Background Cache

Files:

- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayout.swift` (new)
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayoutCalculator.swift` (new)
- `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift` (new)
- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`

Changes:

- Introduce `FirePostLayoutTraitSignature`, `FirePostCellLayoutKey`, and
  `FirePostCellLayout`.
- Keep `NSAttributedString`, `TopicPostState`, and TextKit objects out of the
  `Equatable` layout model.
- Build a stateless calculator that mirrors current `FirePostRow` layout
  constants:
  - `visualDepth = max(depth - 1, 0)`
  - `indentWidth = CGFloat(min(visualDepth, 3)) * 20`
  - `avatarSize = visualDepth > 0 ? 26 : 32`
  - `avatarSpacing = visualDepth > 0 ? 6 : 10`
  - outer horizontal padding remains 16
- Measure rich-text height via temporary TextKit 2 objects created entirely on
  the background worker.
- Exclude reaction count from the layout key; include only whether a reaction
  row exists.
- Keep poll rows off the native path in this phase.
- Add a reply-local `FirePostLayoutManager` that:
  - owns the layout cache on the main actor
  - computes missing layouts on a serial background worker
  - coalesces ready layouts into batch publication
  - exposes a `snapshotRevision` for diffable content-token invalidation
- In `FireTopicDetailCollectionView`:
  - own the layout manager locally
  - track current content width from `onContentWidthChanged`
  - include `replyLayoutSnapshotRevision` in `FireTopicDetailCollectionContentVersion`
  - derive a native eligibility mode per reply row
  - enqueue layout work from render-state changes and prefetch callbacks

Rationale: layout must be modeled and published before the cell can bind with
stable, non-self-sizing geometry.

Exit criteria:

- reply layout is cached by post + width + Dynamic Type + geometry-affecting
  inputs
- a batch of ready layouts results in one content-version bump, not one per post

### Phase 3. Native Reply Cell Skeleton and Fixed-Frame Rich Text

Files:

- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift` (new)
- `native/ios-app/App/ListKit/TopicDetail/FirePostRichTextContainerView.swift` (new)
- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
- `native/ios-app/App/FireComponents.swift`

Changes:

- Add `FirePostCollectionViewCell: UICollectionViewCell` with explicit subviews:
  - avatar image view
  - monogram fallback view
  - thread line view
  - metadata labels
  - accepted-answer badge
  - post number label
  - ellipsis menu button
  - rich-text container
  - image container
  - reaction scroll container
  - manual divider view
- Add `bind(layout:payload:callbacks:)` and `prepareForReuse()`.
- Add `preferredLayoutAttributesFitting(_:)` so the collection layout consumes
  the precomputed height instead of asking UIKit to self-measure the full row.
- Add `FirePostRichTextContainerView` as a fixed-frame wrapper around the
  existing `FireRichTextUIView` interaction behavior:
  - no intrinsic height path
  - explicit text-container size assignment
  - existing link callback behavior preserved
  - existing emoji attachment loading pattern reused
- Add a UIKit avatar path using `fireAvatarURL(...)`, `FireRemoteImagePipeline`,
  and a plain `UIImageView`.
- Keep `.hostedLayoutMiss` as a temporary fallback until native pre-layout is
  reliably warm for the common path.

Rationale: first ship the native reply cell with stable height and rich-text
interaction parity before adding every edge-case interaction.

Exit criteria:

- common reply rows can render natively with correct height and visual parity
- hosted fallback still covers layout misses without breaking the screen

### Phase 4. Native Images, Menu, Reactions, Swipe, and Accessibility

Files:

- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift`
- `native/ios-app/App/ListKit/FireDiffableListController.swift`
- `native/ios-app/App/ListKit/FireCollectionHost.swift`

Changes:

- Render cooked images with lightweight `UIImageView` instances positioned by
  precomputed frames.
- Reuse the shared image pipeline and cancel image tasks on reuse.
- Build the ellipsis `UIMenu` from current post permissions so edit/bookmark/
  flag/recover/delete remain available from the same affordance.
- Implement reaction capsules with `UIScrollView + UIButton` and keep the
  current callback split between heart and non-heart reactions.
- Implement swipe-to-reply with `UIPanGestureRecognizer`, preserving:
  - 32pt back-navigation reservation width
  - horizontal vs vertical axis arbitration
  - 55pt trigger threshold
  - 75pt max offset with dampening past threshold
  - haptic pulse on trigger
  - spring reset to zero on completion
- Add accessibility labels, values, and selected traits.
- If image or emoji lifetime handling needs explicit view lifecycle, add
  `onItemWillDisplay` / `onItemDidEndDisplaying` to the host layer in this
  phase, not earlier.

Rationale: these are the high-frequency interactions that make the reply-native
path actually complete and usable.

Exit criteria:

- native reply rows support the current menu, reaction, and swipe behaviors
- accessibility parity is functionally acceptable

### Phase 5. Invalidation, Trait Adaptation, and Fallback Hardening

Files:

- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift`
- `native/ios-app/App/ListKit/FireDiffableListController.swift`

Changes:

- Invalidate all reply layouts when content width changes.
- Invalidate all reply layouts when the Dynamic Type category changes.
- Refresh colors and other trait-dependent UI in `traitCollectionDidChange`.
- Keep normal reaction count changes as render-only rebinds; only invalidate
  layout if the row crosses the `hasReactions` boundary.
- Keep bookmark, accepted-answer, mutating state, and menu availability as
  render-only updates unless a height-affecting visual change is introduced.
- Preserve hosted fallback for poll and placeholder rows.
- If placeholder frequency proves high enough to matter, add a native skeleton
  state in this phase.

Rationale: invalidation granularity determines whether the native path keeps its
performance win under live updates.

Exit criteria:

- width, Dynamic Type, and live update changes do not leave stale heights behind
- hosted fallback still safely covers the remaining complex cases

### Phase 6. Poll Strategy Decision and Follow-Up Slice

Files:

- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift`

Changes:

- Decide after profiling whether poll rows need to migrate.
- If poll incidence is low and the hosted fallback cost is acceptable, keep the
  hosted poll path.
- If poll rows remain a measurable hotspot, implement a dedicated native poll
  subview instead of embedding a `UIHostingController` inside the reusable cell.

Rationale: poll complexity should not block the common reply-row win.

Exit criteria:

- the team has a measured decision on whether poll rows stay hosted or move to
  a dedicated native poll surface

### Phase 7. Verification and Rollout

Files:

- `native/ios-app/Tests/Unit/FireTopicPresentationTests.swift`
- `native/ios-app/Tests/Unit/FirePostCellLayoutCalculatorTests.swift` (new)
- `native/ios-app/Tests/Unit/FirePostLayoutManagerTests.swift` (new)
- `native/ios-app/App/ListKit/FireDiffableListController.swift`
- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift`

Changes:

- Add focused unit tests for:
  - layout-key stability
  - layout calculation for long text, images, reaction presence, depth, and
    Dynamic Type
  - layout manager batch publication and invalidation semantics
- Keep existing topic-detail store and presentation tests passing.
- Add APM signposts for:
  - layout batch calculation time
  - native cell bind time
  - hosted fallback frequency
- Manually verify:
  - anchored open to target post
  - reply swipe and back-swipe coexistence
  - load-more and hydration
  - reaction optimistic updates
  - image open
  - menu actions
  - Dynamic Type changes
  - rotation and split-view width changes
- Optionally gate the native reply path behind a temporary local feature flag if
  rollout risk remains high after verification.

Rationale: the migration should close with evidence, not only with code.

## Topic Detail Design Constraints

These remain non-negotiable:

1. One continuous scroll surface.
   Header, original post, replies, and footer remain on a single collection view.

2. Stable anchored scrolling.
   Route jumps must still work when the target reply becomes available later.

3. Back-swipe reservation.
   Reply swipe cannot steal the system back-navigation gesture from the leading
   edge.

4. Store boundary preservation.
   UIKit-only layout cache stays out of `FireTopicDetailStore`.

5. Batch publication.
   Layout readiness must publish in coalesced revisions, not one-item bursts.

6. Fallback is allowed.
   Poll, placeholder, and early layout-miss cases may stay hosted until their
   native path is justified.

7. Accessibility parity.
   Native reply cells cannot silently drop semantics that SwiftUI was giving us.

8. Width and Dynamic Type invalidation.
   Cached reply heights must respect both.

## Verification Checklist

- Build the iOS app target successfully.
- Run the focused unit tests for layout calculation and manager invalidation.
- Confirm existing topic-detail presentation and store tests still pass.
- Compare scroll smoothness and hosted-row rebuild frequency before and after.
- Verify that reply swipe, menu actions, reaction updates, image taps, and
  anchored scrolling still behave correctly.
- Verify rotation, split view, and Dynamic Type changes do not leave stale
  heights or broken colors.

## File Change Summary

- `docs/architecture/plans/ios-topic-detail-native-reply-cell-plan.md` -- adds
  the full migration plan for native topic-detail reply cells.
- `native/ios-app/App/ListKit/FireDiffableListController.swift` -- adds mixed
  hosted/native cell routing and content-width publication.
- `native/ios-app/App/ListKit/FireCollectionHost.swift` -- threads native cell
  routing and width-change callbacks through the SwiftUI wrapper.
- `native/ios-app/App/ListKit/TopicDetail/FireTopicDetailCollectionView.swift`
  -- adds reply-cell eligibility, local layout-manager ownership, width-driven
  invalidation, and native reply wiring.
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayout.swift` -- adds the
  reply layout key, trait signature, and geometry model.
- `native/ios-app/App/ListKit/TopicDetail/FirePostCellLayoutCalculator.swift`
  -- adds the pure background layout calculator.
- `native/ios-app/App/ListKit/TopicDetail/FirePostLayoutManager.swift` -- adds
  the reply-local layout cache and batch publication logic.
- `native/ios-app/App/ListKit/TopicDetail/FirePostCollectionViewCell.swift` --
  adds the pure UIKit reply cell implementation.
- `native/ios-app/App/ListKit/TopicDetail/FirePostRichTextContainerView.swift`
  -- adds the fixed-frame rich-text UIKit wrapper.
- `native/ios-app/App/FireComponents.swift` -- may be touched only if the native
  reply cell needs a shared avatar helper promoted from existing code.
- `native/ios-app/Tests/Unit/FirePostCellLayoutCalculatorTests.swift` -- adds
  focused layout-calculation tests.
- `native/ios-app/Tests/Unit/FirePostLayoutManagerTests.swift` -- adds focused
  cache and invalidation tests.
- `native/ios-app/Tests/Unit/FireTopicPresentationTests.swift` -- adds any
  small helper- or token-level coverage that belongs with existing topic-detail
  presentation tests.

## Explicitly Not Changed in Slice 1

- `native/ios-app/App/FireTopicDetailView.swift` stays the screen shell and
  continues to own the hosted `.originalPost` path.
- `native/ios-app/App/FireTopicPresentation.swift` remains the source of render
  content and render-cache production.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` remains the source of
  topic detail state and collection revisions.
- all Rust, UniFFI, and backend protocol surfaces remain untouched.
