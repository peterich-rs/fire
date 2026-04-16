# Redesign iOS Topic Detail Loading and Notification Routing

## Feasibility Assessment

The latest `main` already contains the hard parts needed for this slice: Rust `fetch_topic_detail_initial` in `rust/crates/fire-core/src/core/topics.rs` (line 19) already supports anchored `/t/{topicId}/{postNumber}.json` reads and intentionally keeps partial `post_stream` payloads (`rust/crates/fire-core/tests/network.rs`, lines 1001-1038), Swift topic-detail state is isolated in `native/ios-app/App/Stores/FireTopicDetailStore.swift` (lines 62, 527, 650, 764), and app-wide route delivery already flows through `native/ios-app/App/FireNavigationState.swift` (lines 7-10), `native/ios-app/App/Routing/FireRouteParser.swift` (line 28), and `native/ios-app/App/FireAppDelegate.swift` (line 31). MessageBus alert parsing already carries `post_url` in Rust and UniFFI (`rust/crates/fire-core/src/core/messagebus.rs`, line 1044; `rust/crates/fire-uniffi/src/state_messagebus.rs`, line 200), so reliable notification tap-through does not need a backend contract change. The work is local and mechanical: replace prefix-window assumptions with anchor-aware range state, collapse redundant topic-detail presentation shapes, and make target scrolling retry until the row is actually loaded. Fully feasible.

## Current Surface Inventory

- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `loadTopicDetail` (line 62) -- topic-detail entry point; currently returns early on cached detail before capturing a new route anchor.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `clearTopicDetailAnchor` (line 126) -- clears the stored topic anchor only on explicit refresh.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `refreshTopicDetailAfterMutation` (line 506) -- mutation refresh path; currently always reloads from topic start.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `scheduleTopicDetailRefresh` (line 527) -- MessageBus refresh path; preserves the recorded anchor only if one was stored before the cache short-circuit.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `applyTopicDetail` (line 650) -- merges incoming detail, recomposes thread/flat copies in Swift, and seeds hydration state from a prefix count.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` `hydrateTopicPostsToTargetIfNeeded` (line 764) -- incremental fetch loop; currently resolves missing posts against the start of `post_stream.stream`, not the anchored window the user is reading.
- `native/ios-app/App/FireTopicPresentation.swift` `loadedWindowCount` / `missingPostIDs` (lines 248, 274) -- prefix-based hydration helpers that treat “loaded” as a contiguous stream head.
- `native/ios-app/App/FireTopicDetailView.swift` `onPreferenceChange(FireVisiblePostFramePreferenceKey...)` (line 356) -- visible-post callback used to trigger preload.
- `native/ios-app/App/FireTopicDetailView.swift` `scrollToTargetPostIfNeeded` (line 614) -- one-shot scroll attempt that can complete before the target row exists.
- `native/ios-app/App/FireTopicDetailView.swift` `replyPostRows` (line 851) and `FireVisiblePostFrameReporter` (line 1310) -- row rendering and viewport reporting for long threads.
- `rust/crates/fire-core/src/core/topics.rs` `fetch_topic_detail_initial` (line 19) -- anchored initial read that intentionally preserves a partial stream.
- `rust/crates/fire-core/src/core/topics.rs` `hydrate_topic_detail_posts` (line 229) -- full missing-post hydration path used by the non-initial fetch.
- `rust/crates/fire-models/src/topic_detail.rs` `TopicThread::from_posts` / `flatten` (lines 245, 339) -- current thread-first/depth-first presentation order.
- `rust/crates/fire-uniffi/src/state_topic_detail.rs` `TopicDetailState` (line 588) -- current UniFFI payload bridges `post_stream`, `thread`, and `flat_posts` at the same time.
- `native/ios-app/App/FireNotificationsView.swift` `NotificationItemState.appRoute` (line 98) and `handleNotificationTap` (line 282) -- recent-notification route construction and tap handling.
- `native/ios-app/App/FireNotificationHistoryView.swift` `handleNotificationTap` (line 106) -- full-history route construction and tap handling.
- `native/ios-app/App/Stores/FireNotificationStore.swift` `loadFullPage` / `scheduleStateRefresh` (lines 93, 109) -- notification full-history paging and MessageBus refresh application.
- `native/ios-app/App/FireBackgroundNotificationAlert.swift` `present(alert:)` (line 111) -- builds local notification payloads; currently omits `postUrl` even though Rust provides it.
- `native/ios-app/App/Routing/FireRouteParser.swift` `route(fromNotificationUserInfo:)` (line 28) -- system-notification parser; currently requires `topicId` and ignores `postUrl` fallback.
- `native/ios-app/App/FireHomeView.swift` `consumePendingRouteIfVisible` (line 137) and `native/ios-app/App/FireTabRoot.swift` `selectTabForPendingRouteIfReady` (line 151) -- current pending-route handoff; already works for app and universal-link routing.
- `native/ios-app/README.md` (lines 111-115, 175) and `docs/architecture/ios-listkit-home.md` (lines 20-21) -- current iOS delivery/rendering gaps: beta notification polling, ListKit limited to home, and `Nuke` still planned rather than adopted.

## Design

### Remaining iOS Priority Workstreams

1. `P0 in this plan`: topic-detail loading/rendering correctness, anchor reliability, and retained-memory reduction.
2. `P0 in this plan`: notification tap-through reliability for reply/comment targets, including background/system notifications.
3. `P1 next`: real notification delivery beyond beta polling. Current iOS behavior is still `BGAppRefreshTask` + one-shot MessageBus alert polling plus local-only APNs token storage (`native/ios-app/README.md`, lines 111-115).
4. `P1 next`: high-volume non-home list surfaces. `docs/architecture/ios-listkit-home.md` explicitly states that notifications/history and topic detail were not part of the home migration, and current `List`-backed high-churn views still include notifications, history, bookmarks, PMs, filtered lists, read history, profile activity, and search results.
5. `P1 next`: production image/rendering infrastructure. The iOS README still calls out `Nuke` as upcoming (`native/ios-app/README.md`, line 175), while avatars, badges, composer uploads, and topic media still rely on `AsyncImage` surfaces (`native/ios-app/App/FireComponents.swift`, line 653; `native/ios-app/App/FireTopicDetailView.swift`, lines 1752, 1878).

### Key Design Decisions

1. **Make strict floor order the authoritative topic timeline order.**
   Chosen: render replies in ascending `post_number`, and keep reply depth/parent metadata as decoration only.
   Rejected: keep `TopicThread::flatten` as the primary display order.
   Why: anchor-centered reads, notification targets, and floor labels all reason about post numbers, while the current thread-first/depth-first order can surface reply `#180` far away from its numeric neighbors.

2. **Replace prefix-based hydration state with anchor-aware stream ranges.**
   Chosen: store the desired loaded window as a range of indices inside `post_stream.stream`, plus a pending scroll target.
   Rejected: keep `loadedWindowCount` / `missingPostIDs(upTo:)` semantics.
   Why: anchored `/t/{topicId}/{postNumber}.json` payloads load a centered slice; a prefix counter cannot describe that slice and hydrates the wrong posts.

3. **Capture route anchors before any cache reuse decision.**
   Chosen: treat a route/comment jump as a `TopicDetailRequest` with an explicit anchor, record it immediately, then decide whether cached data already satisfies it.
   Rejected: the current `topicDetails[topicId] != nil && !force` short-circuit.
   Why: latest main can silently drop a new notification anchor if the topic was already cached.

4. **Keep one lightweight presentation shape across Rust and Swift.**
   Chosen: remove `thread` and `flat_posts` from the bridged detail payload and replace them with a lightweight floor-ordered `timeline_entries` vector.
   Rejected: continue bridging raw posts plus a thread tree plus a flat threaded copy, then recompute again in Swift.
   Why: the current shape pays memory twice and still leaves Swift doing redundant recomposition work.

5. **Make scroll-to-target retriable until the row exists and becomes visible.**
   Chosen: keep a pending scroll target in store/view state and only mark it resolved after the target row is present in the rendered dataset.
   Rejected: one delayed `ScrollViewReader.scrollTo` guarded by `hasScrolledToTarget`.
   Why: a one-shot attempt can fire before incremental hydration has loaded the target post.

6. **Preserve the current app-wide route-state spine and only harden the payload parsing path.**
   Chosen: keep `FireNavigationState`, `FireAppDelegate`, `FireTabRoot`, and `FireHomeView` as the route-ingestion path; add `postUrl` fallback and rely on the improved topic-detail store for anchor correctness.
   Rejected: introduce a second deep-link coordinator or a tab-specific notification router.
   Why: latest main already routes app URLs and notification taps through one shared typed route model.

7. **Keep notification delivery product work separate from tap-through correctness.**
   Chosen: this slice only consumes existing notification payloads more reliably.
   Rejected: bundle APNs backend upload, push entitlement/product work, and topic-detail correctness into one implementation.
   Why: the current blocker for reply notifications is not payload creation in Rust; it is anchor preservation, payload fallback, and scroll completion.

8. **Do not combine the data-model rewrite with a same-PR ListKit host migration.**
   Chosen: keep the current `ScrollView`/`LazyVStack` host for this slice and win perceived performance through smaller bridged state, floor-order rendering, and bounded active windows.
   Rejected: rewrite topic detail into a collection host at the same time.
   Why: correctness and state-shape changes are already enough risk for one slice, and the later ListKit rollout should build on a stable topic-detail model.

### Concrete Types / Interface Definitions

File: `rust/crates/fire-models/src/topic_detail.rs`

```rust
pub struct TopicTimelineEntry {
    pub post_id: u64,
    pub post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u32,
    pub is_original_post: bool,
}

pub struct TopicDetail {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub post_stream: TopicPostStream,
    pub timeline_entries: Vec<TopicTimelineEntry>,
    pub details: TopicDetailMeta,
    // Existing scalar fields unchanged.
}
```

File: `native/ios-app/App/Stores/FireTopicDetailStore.swift`

```swift
private struct FireTopicDetailWindowState {
    static let maxWindowSize = 200

    var anchorPostNumber: UInt32?
    var requestedRange: Range<Int>
    var loadedIndices: IndexSet
    var loadedPostNumbers: Set<UInt32> = []
    var exhaustedPostIDs: Set<UInt64> = []
    var pendingScrollTarget: UInt32?
}

struct FireTopicDetailRequest: Equatable {
    enum Reason {
        case initialOpen
        case routeAnchor
        case visibleRangeExpansion
        case userRefresh
        case messageBusRefresh
    }

    var anchorPostNumber: UInt32?
    var reason: Reason
    var forceNetwork: Bool = false
}
```

File: `native/ios-app/App/FireTopicPresentation.swift`

```swift
struct FireTopicTimelineRow: Identifiable {
    let entry: TopicTimelineEntryState
    let post: TopicPostState?
    var id: UInt64 { entry.postId }
    var isLoaded: Bool { post != nil }
}
```

The topic detail view renders `[FireTopicTimelineRow]` instead of `[TopicThreadFlatPostState]`. Each row joins a lightweight timeline entry with an optional loaded post. Rows where `post == nil` (entry present but post not yet hydrated) render a compact loading placeholder. This replaces the current `FireTopicFlatPostPresentation` type alias.

Usage example: route/comment jump

```swift
await topicDetailStore.loadTopicDetail(
    topicId: payload.topicId,
    request: FireTopicDetailRequest(
        anchorPostNumber: payload.postNumber,
        reason: .routeAnchor
    )
)
```

Usage example: MessageBus refresh preserving the current window

```swift
await topicDetailStore.loadTopicDetail(
    topicId: topicId,
    request: FireTopicDetailRequest(
        anchorPostNumber: window.anchorPostNumber,
        reason: .messageBusRefresh,
        forceNetwork: true
    )
)
```

Usage example: system notification payload fallback (relative path, no `topicId`)

```swift
let route = FireRouteParser.route(fromNotificationUserInfo: [
    "postUrl": "/t/fire-native/987/6",
    "topicTitle": "Fire Native",
    "excerpt": "最新进展"
])
// → .topic(topicId: 987, postNumber: 6, preview: ...)
```

## Phased Implementation

## Phase 1: Replace Redundant Thread Payloads with a Floor-Ordered Timeline

**File: `rust/crates/fire-models/src/topic_detail.rs`**

- Add `TopicTimelineEntry` and `TopicDetail.timeline_entries`.
- Replace the current `TopicThread` / `TopicThreadFlatPost` display shape as the primary presentation surface.
- Build entries in ascending `post_number`; keep `depth` and `parent_post_number` only as render hints.

```rust
impl TopicDetail {
    pub fn rebuild_timeline_entries(&mut self) {
        self.timeline_entries = build_floor_timeline_entries(&self.post_stream.posts);
    }
}
```

`build_floor_timeline_entries` sorts posts by ascending `post_number` and computes each entry's `depth` by walking the `reply_to_post_number` parent chain within the loaded set. When a parent is missing from the current partial set (common in anchored initial loads), depth falls back to `1` — "known reply, unknown ancestry depth." `parent_post_number` is always preserved from the raw post regardless of whether the parent is loaded, so the UI can show "in reply to #N" before post #N arrives. Entries are rebuilt after every post set mutation (initial fetch, hydration batch, MessageBus refresh), so depth self-corrects as more posts arrive.

```rust
fn build_floor_timeline_entries(posts: &[TopicPost]) -> Vec<TopicTimelineEntry> {
    let post_numbers: HashSet<u32> = posts.iter().map(|p| p.post_number).collect();
    let min_pn = posts.iter().map(|p| p.post_number).min().unwrap_or(0);
    let mut sorted = posts.to_vec();
    sorted.sort_by_key(|p| (p.post_number, p.id));

    sorted.iter().map(|post| {
        let parent = normalized_reply_target(post.reply_to_post_number);
        let depth = match parent {
            Some(pn) if pn != post.post_number =>
                compute_depth_walk(pn, posts, &post_numbers, 1),
            _ => 0,
        };
        TopicTimelineEntry {
            post_id: post.id,
            post_number: post.post_number,
            parent_post_number: parent,
            depth,
            is_original_post: post.post_number == min_pn,
        }
    }).collect()
}

/// Walk up the parent chain to compute depth.
/// Terminates with `current_depth` when a parent is absent from the loaded set.
fn compute_depth_walk(
    parent_pn: u32,
    posts: &[TopicPost],
    loaded: &HashSet<u32>,
    current_depth: u32,
) -> u32 {
    if !loaded.contains(&parent_pn) {
        return current_depth;
    }
    match posts.iter().find(|p| p.post_number == parent_pn) {
        Some(p) => match normalized_reply_target(p.reply_to_post_number) {
            Some(gp) if gp != parent_pn =>
                compute_depth_walk(gp, posts, loaded, current_depth + 1),
            _ => current_depth,
        },
        None => current_depth,
    }
}
```

Rationale: the UI needs one stable numeric order, not three overlapping shapes. Depth is best-effort for partial post sets and self-correcting as hydration proceeds.

**File: `rust/crates/fire-core/src/core/topics.rs`**

- Keep `fetch_topic_detail_initial` partial by design.
- After initial fetch and after `hydrate_topic_detail_posts`, rebuild `timeline_entries` exactly once in Rust.
- Keep `post_stream.stream` untouched so Swift can still request missing post IDs by stream index.

```rust
let mut result = self.fetch_topic_detail_base(query).await?;
result.rebuild_timeline_entries();
```

Rationale: initial payload semantics stay the same; only the presentation payload changes.

**File: `rust/crates/fire-uniffi/src/state_topic_detail.rs`**

- Export `TopicTimelineEntryState`.
- Remove `thread` and `flat_posts` from `TopicDetailState`.
- Map `timeline_entries` through UniFFI.

```rust
#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimelineEntryState {
    pub post_id: u64,
    pub post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u32,
    pub is_original_post: bool,
}
```

Rationale: bridge only the data the native host actually needs to render.

**File: `rust/crates/fire-core/tests/network.rs`**

- Extend the anchored topic-detail tests so partial initial reads still keep a partial stream while producing stable floor-order timeline metadata.
- Add a regression test for an anchored `/t/{topicId}/{postNumber}.json` payload whose loaded posts are not a stream prefix.

Rationale: this is the cheapest executable proof that the new payload shape preserves current network behavior.

## Phase 2: Make Swift Topic Detail State Anchor-Aware

**File: `native/ios-app/App/Stores/FireTopicDetailStore.swift`**

- Replace `topicPostPaginationStates` with `topicWindowStates: [UInt64: FireTopicDetailWindowState]`.
- Change `loadTopicDetail` to accept `FireTopicDetailRequest` and record `anchorPostNumber` before any cache reuse.
- If a cached detail already contains the target post, reuse it and set `pendingScrollTarget` without a network fetch.
- If a cached detail does not contain the target post, force an anchored `fetchTopicDetailInitial` instead of returning early.
- Replace prefix-based `targetLoadedCount` math with range math over `post_stream.stream` indices.
- Expand the requested range in both directions when the user reads near the top or bottom of the current window. Cap `requestedRange` at `FireTopicDetailWindowState.maxWindowSize` (200 indices); when the user scrolls past the window edge, shift the window rather than expanding it. Posts outside the active window remain in `loadedIndices` as warm cache but are not actively hydrated.
- Preserve the active anchor for MessageBus refreshes and clear it only on explicit user refresh or lifecycle eviction.
- Replace `recomposedDetail` calls in both `applyTopicDetail` and `applyHydratedTopicPostsIfNeeded` with a unified composition path: merge posts → call `FireTopicPresentation.rebuildTimelineEntries` → recompute `interactionCount`. Remove the current `composeThread` / `thread` / `flatPosts` assignments.
- After hydration loop exits, check whether `pendingScrollTarget` refers to a post ID in `exhaustedPostIDs`; if so, clear the target and log a warning rather than retrying indefinitely.

```swift
private func needsAnchoredReload(
    detail: TopicDetailState?,
    anchorPostNumber: UInt32?,
    window: FireTopicDetailWindowState?
) -> Bool {
    guard let anchorPostNumber else { return detail == nil }
    guard let window else { return true }
    return !window.loadedPostNumbers.contains(anchorPostNumber)
}
```

`FireTopicDetailWindowState.loadedPostNumbers` is a `Set<UInt32>` maintained alongside `loadedIndices`, providing O(1) anchor-presence checks instead of a linear scan over `post_stream.posts`.

Rationale: route/comment jumps must be able to reuse cache when valid and bypass it when invalid. The sliding window cap ensures that even in long topics, active hydration stays bounded while already-loaded posts remain available as warm cache.

**File: `native/ios-app/App/FireTopicPresentation.swift`**

- Remove `loadedWindowCount` and `missingPostIDs(upTo:)` as the store’s primary pagination helpers.
- Add range-based helpers keyed by stream indices.
- Replace `recomposedDetail` with a streamlined composition path that removes the `composeThread` call and its `thread`/`flatPosts` output. Keep the post merge and `interactionCount` computation. Add a call to `rebuildTimelineEntries` so timeline entries stay consistent after every post set mutation (initial apply, incremental hydration, MessageBus refresh).
- Add `rebuildTimelineEntries` as the Swift-side counterpart to Rust’s `build_floor_timeline_entries`. This function is called after Swift-side incremental hydration to extend `timeline_entries` with newly loaded posts, using the same floor-order and best-effort depth logic. This is necessary because Swift-side hydration fetches individual posts via `fetchTopicPosts` and merges them locally — the Rust-side `rebuild_timeline_entries` only runs on the initial fetch path.
- Add `timelineRows` mapper that joins `timeline_entries` with `post_stream.posts` into `[FireTopicTimelineRow]` for the view.
- Remove the `FireTopicFlatPostPresentation`, `FireTopicReplyPresentation`, `FireTopicReplySectionPresentation`, and `FireTopicThreadPresentation` type aliases once all consumers are migrated.

```swift
static func missingPostIDs(
    orderedPostIDs: [UInt64],
    in requestedRange: Range<Int>,
    loadedPostIDs: Set<UInt64>,
    excluding exhaustedPostIDs: Set<UInt64>
) -> [UInt64]

/// Rebuild timeline entries in Swift after incremental hydration.
/// Same algorithm as Rust `build_floor_timeline_entries`: ascending post_number,
/// depth by parent-chain walk with fallback to 1 when parent is not loaded.
static func rebuildTimelineEntries(
    from posts: [TopicPostState]
) -> [TopicTimelineEntryState]

/// Join timeline entries with loaded posts into renderable rows.
/// Posts not yet hydrated produce rows with `post == nil` (loading placeholder).
static func timelineRows(
    entries: [TopicTimelineEntryState],
    posts: [TopicPostState]
) -> [FireTopicTimelineRow] {
    let postsByID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
    return entries.map { entry in
        FireTopicTimelineRow(entry: entry, post: postsByID[entry.postId])
    }
}
```

Rationale: the view should no longer infer meaning from “how many posts from the front are loaded.” The `rebuildTimelineEntries` function ensures `timeline_entries` stays consistent with `post_stream.posts` regardless of whether posts arrived from the initial Rust fetch or from Swift-side incremental hydration.

**File: `native/ios-app/App/FireTopicDetailView.swift`**

- Change the data source of `replyPostRows` from `[FireTopicFlatPostPresentation]` (alias for `TopicThreadFlatPostState`) to `[FireTopicTimelineRow]`. Each row accesses `row.post` for rendering content and `row.entry` for depth/parent metadata. Rows where `row.post == nil` render a compact loading placeholder (height-estimated skeleton matching the expected post layout).
- Render replies from the new floor-ordered timeline entry list.
- Replace `hasScrolledToTarget` with a pending-target state that retries while the target post is still absent, with an exhaustion-based termination condition.
- Report the visible top and bottom post numbers back into the store so range expansion can be symmetric around an anchor.
- Keep the current reply composer, mutation, and image-viewer affordances unchanged.

```swift
private func scrollToTargetPostIfNeeded(proxy: ScrollViewProxy) {
    guard let target = topicDetailStore.pendingScrollTarget(topicId: topic.id) else { return }

    // Terminate: target was exhausted (deleted/hidden post) — clear and stop retrying.
    if topicDetailStore.isScrollTargetExhausted(topicId: topic.id, postNumber: target) {
        topicDetailStore.markScrollTargetSatisfied(topicId: topic.id, postNumber: target)
        return
    }

    guard renderedPostNumbers.contains(target) else { return }
    withAnimation(.easeInOut(duration: 0.25)) {
        proxy.scrollTo(target, anchor: .top)
    }
    topicDetailStore.markScrollTargetSatisfied(topicId: topic.id, postNumber: target)
}
```

`isScrollTargetExhausted` checks whether the target post's ID appears in the window state's `exhaustedPostIDs` — meaning the server confirmed the post does not exist or the hydration loop completed without finding it. This prevents infinite retry when a post has been deleted or hidden by a moderator.

Rationale: a scroll target is satisfied only when the row exists, not when a timer fired. Exhausted targets are cleared immediately instead of retrying indefinitely.

## Phase 3: Harden Notification Tap-Through with `postUrl` Fallback

**File: `native/ios-app/App/FireBackgroundNotificationAlert.swift`**

- Add `postUrl` to `UNNotificationContent.userInfo` when `NotificationAlertState.postUrl` is present.
- Keep `topicId`, `postNumber`, `topicTitle`, and `excerpt` unchanged.

```swift
if let postURL = alert.postUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !postURL.isEmpty {
    content.userInfo["postUrl"] = postURL
}
```

Rationale: latest main already has `post_url` in Rust; the host just drops it.

**File: `native/ios-app/App/Routing/FireRouteParser.swift`**

- Keep numeric `topicId` / `postNumber` parsing as the first path.
- Fall back to `postUrl` / `post_url` and reuse the existing `parse(url:)` implementation.
- Preserve preview metadata even when the route came from `postUrl`.

```swift
static func route(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> FireAppRoute? {
    if let topicId = integerUInt64(from: userInfo["topicId"]) {
        let postNumber = integerUInt32(from: userInfo["postNumber"])
        return .topic(topicId: topicId, postNumber: postNumber, preview: preview(from: userInfo))
    }

    if let rawURL = stringValue(from: userInfo["postUrl"]) ?? stringValue(from: userInfo["post_url"]) {
        // Absolute URL: parse directly via existing URL router.
        if let url = URL(string: rawURL), url.host != nil, let route = parse(url: url) {
            return route.overlayPreview(preview(from: userInfo))
        }
        // Relative path (e.g. "/t/slug/123/6"): extract path components and parse.
        if rawURL.hasPrefix("/"), let route = parse(path: rawURL) {
            return route.overlayPreview(preview(from: userInfo))
        }
    }

    return nil
}
```

`parse(path:)` reuses the same path-component matching logic as `parse(url:)` without requiring a base URL, avoiding hardcoded domain assumptions. If `postUrl` is an absolute URL (includes scheme and host), the existing `parse(url:)` handles it directly.

Rationale: route parsing should succeed when either numeric ids or a canonical post URL is present, without coupling the parser to a specific site domain.

**File: `native/ios-app/App/FireNotificationsView.swift`**

- Keep the current `item.appRoute` and `handleNotificationTap` structure.
- No routing-model rewrite is required; the store-level anchor fix is what makes these taps reliable.

Rationale: latest main already has correct recent-list mark-read + route dispatch semantics.

**File: `native/ios-app/App/FireNotificationHistoryView.swift`**

- Keep the current full-history tap handler and route dispatch.
- No behavioral divergence from the recent-list path.

Rationale: both notification surfaces should stay on the same route model.

**File: `native/ios-app/App/FireAppDelegate.swift`**

- No code change.
- Audit confirms the delegate is already the correct `UNUserNotificationCenter` ingestion point; improving `FireRouteParser` is sufficient.

Rationale: avoid inventing a second notification-entry path.

## Phase 4: Validation and Regression Coverage

**File: `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift`** (new)

- Add cache/anchor regression tests:
  - cached detail + new route anchor forces an anchored reload when the target is absent from `loadedPostNumbers`
  - cached detail + already-loaded route anchor skips the network and only schedules pending scroll
  - visible-range expansion requests older and newer missing post ids around the current anchor
  - `requestedRange` does not grow beyond `maxWindowSize` when scrolling continuously; instead the window slides
  - MessageBus refresh preserves the active anchor window
  - pending scroll target for an exhausted post ID is cleared after hydration loop completes
  - `rebuildTimelineEntries` is called after `applyHydratedTopicPostsIfNeeded`, and the resulting entries cover newly hydrated posts

Rationale: the core failure modes now live in store state, so they need store-level tests.

**File: `native/ios-app/Tests/Unit/FireTopicPresentationTests.swift`**

- Replace the current prefix-window assertions with range-window assertions.
- Add a regression that proves floor-order rendering no longer depends on thread-first flattening.
- Add `rebuildTimelineEntries` tests:
  - full post set produces correct depth via parent chain walk
  - partial post set (anchored load) falls back to depth 1 for missing parents
  - depth self-corrects when the same post set is extended with previously missing parents
- Add `timelineRows` tests:
  - entries with loaded posts produce `isLoaded == true` rows
  - entries without loaded posts produce `isLoaded == false` placeholder rows

Rationale: current tests encode the old prefix model and must stop protecting it. The new `rebuildTimelineEntries` and `timelineRows` functions are the critical bridge between the Rust model change and the Swift rendering pipeline.

**File: `native/ios-app/Tests/Unit/FireRouteParserTests.swift`**

- Add `postUrl`-only notification payload tests (both relative path and absolute URL variants).
- Add malformed numeric payload + valid `postUrl` fallback coverage.
- Add `parse(path:)` unit tests for common Discourse path formats (`/t/slug/id/postNumber`, `/t/id/postNumber`, `/t/slug/id`).

Rationale: this is the cheapest executable proof of system-notification fallback routing.

**File: `rust/crates/fire-core/tests/network.rs`**

- Verify anchored initial fetches keep partial streams.
- Verify the initial anchored payload does not trigger any implicit “hydrate from the stream front” behavior.
- Verify `build_floor_timeline_entries` produces correct floor-order entries for a partial post set with missing parent chains (depth should fall back to 1, not panic or return 0).
- Verify `rebuild_timeline_entries` after `hydrate_topic_detail_posts` produces entries covering all hydrated posts with corrected depths.

Rationale: the initial-fetch contract is intentional and should remain so. The `build_floor_timeline_entries` function is the shared algorithm between Rust and Swift; its edge cases (partial parents, self-referencing replies, depth cycles) must be covered in Rust tests.

Verification commands:

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath /tmp/fire-ios-topic-detail CODE_SIGNING_ALLOWED=NO test
cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets
```

Manual verification matrix:

- Open a reply notification for a long topic where the target post is outside the initial prefix; the topic view must land on the target comment.
- Re-open the same topic from a different notification anchor while the old cache is retained; the second anchor must still win.
- Trigger a topic-detail MessageBus refresh while reading an anchored window; the window must stay centered on the same target region.
- Pull to refresh from topic detail; the explicit user refresh must clear the anchor and return to the topic-start window.
- Deliver a background/system notification that only has a valid `post_url`; the app must still route into the correct topic/comment.
- Open a reply notification targeting a post that has been deleted by a moderator; the app must land on the topic without hanging on a perpetual loading state (scroll target cleared after exhaustion).

## Architectural Notes

- **No backend API change in this slice**: the plan keeps using `/t/{topicId}.json`, `/t/{topicId}/{postNumber}.json`, `/t/{topicId}/posts.json`, and the existing MessageBus `notification-alert` payload.
- **UniFFI host shape changes are internal, not public semver**: `TopicDetailState` changes require regenerated Swift/Kotlin bindings, but there is no external crate API or backend contract break. Android bindings regeneration is mechanical and requires no Kotlin code change in this slice; Android-side adaptation is tracked as a separate follow-up.
- **Retained-memory impact is positive**: removing bridged `thread` + `flat_posts` copies and stopping Swift-side recomposition cuts duplicate post retention while preserving `post_stream.stream` as the hydration source of truth.
- **Object ownership stays aligned with repository architecture**: Rust owns canonical topic-detail models and initial timeline presentation metadata; Swift owns viewport state, route handling, native scrolling, and timeline entry rebuild after incremental hydration (using the same floor-order algorithm as Rust, keeping depth self-correcting as more posts arrive).
- **What is explicitly not changed**: APNs/backend token upload, server-side push delivery, ListKit rollout to non-home surfaces, and the production `Nuke` image pipeline are identified as top follow-up workstreams but remain out of scope for this implementation slice.
- **Cross-dependency impact is neutral**: no new third-party dependency is required for the in-scope topic-detail and notification-routing work.

## File Change Summary

- `native/ios-app/App/FireBackgroundNotificationAlert.swift` -- preserve `postUrl` in local-notification payloads so system taps can fall back to URL parsing.
- `native/ios-app/App/FireTopicDetailView.swift` -- render a floor-ordered timeline and retry anchor scrolling until the target row exists.
- `native/ios-app/App/FireTopicPresentation.swift` -- replace prefix-window helpers with range-based window helpers and timeline row mapping.
- `native/ios-app/App/Routing/FireRouteParser.swift` -- add `postUrl`/`post_url` fallback routing for notification payloads.
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` -- introduce anchor-aware window state, cache-aware anchor reuse, and bidirectional hydration.
- `native/ios-app/Tests/Unit/FireRouteParserTests.swift` -- cover `postUrl` fallback and malformed-id recovery.
- `native/ios-app/Tests/Unit/FireTopicDetailStoreTests.swift` -- add anchor/window regression coverage for the new store state.
- `native/ios-app/Tests/Unit/FireTopicPresentationTests.swift` -- replace prefix-based expectations with range/floor-order expectations.
- `rust/crates/fire-core/src/core/topics.rs` -- rebuild lightweight floor-order timeline metadata after initial fetch and hydration.
- `rust/crates/fire-core/tests/network.rs` -- prove anchored initial payloads remain partial and do not regress into prefix hydration assumptions.
- `rust/crates/fire-models/src/topic_detail.rs` -- replace thread-first presentation payloads with lightweight floor-order timeline entries.
- `rust/crates/fire-uniffi/src/state_topic_detail.rs` -- expose `timeline_entries` and stop bridging redundant `thread`/`flat_posts` copies.
- `uniffi/fire_uniffi/fire_uniffi.kt` -- regenerate Android bindings for the updated `TopicDetailState` UniFFI shape (mechanical regeneration only; Android-side code adaptation is tracked separately).