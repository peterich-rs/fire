# Implement Notification Tap-Through and Full Notification Experience

## Feasibility Assessment

All notification models (`NotificationItem`, `NotificationState`, etc.) and API methods
(`fetchNotifications`, `markNotificationRead`, `pollNotificationAlertOnce`) are already
implemented in `fire-core` and exposed via `fire-uniffi`. Three structural gaps exist:

1. `loadTopicDetail` at `FireAppViewModel.swift:432` hardcodes `postNumber: nil`, while
   `fire-core` `fetch_topic_detail_base` at `topics.rs:158` already builds
   `/t/{topicId}/{postNumber}.json` when `post_number` is `Some`. Without anchored fetch,
   long topics won't have the target post in the loaded window.
2. `FireAppDelegate` has no `didReceive` handler, `FireTabRoot`'s `TabView` has no
   `selection` binding, and `FireApp` creates `FireTabRoot()` which owns
   `@StateObject viewModel` -- there is no path from delegate to viewModel.
3. `NotificationAlertState` carries `message_id` but not the inbox `notification.id`, so
   system-notification-tap cannot call `markNotificationRead(id:)` directly.

All three are solvable without Rust-side changes (except the optional inbox id addition
to alerts). Fully feasible with the caveats noted below.

## Current Surface Inventory

- `FireAppViewModel.loadTopicDetail(topicId:force:)` (line 407) -- Builds
  `TopicDetailQueryState(postNumber: nil)`, always loads from topic start
- `FireAppViewModel.scheduleTopicDetailRefresh(topicId:)` (line 1145) -- MessageBus-triggered
  refresh, also hardcodes `postNumber: nil`
- `FireAppViewModel.loadRecentNotifications(force:)` (line 785) -- Fetches via
  `fetchRecentNotifications()`, sets `recentNotifications`
- `FireAppViewModel.markNotificationRead(id:)` (line 804) -- Marks read, updates
  `recentNotifications[idx].read` locally
- `FireAppViewModel.markAllNotificationsRead()` (line 819) -- Maps all `recentNotifications`
  to `.read = true`
- `FireSessionStore.fetchNotifications(limit:offset:)` (line 268) -- Exposed, never called
  from UI; core maintains `full` + `full_next_offset`
- `FireNotificationsView.notificationRow(_:)` (line 212) -- Routes only when `stubRow != nil`
  (topicId present); non-topic rows are inert
- `FireTopicDetailView.init(viewModel:row:)` (line 46) -- No `scrollToPostNumber` parameter
- `FireApp` (line 4) -- Creates `FireTabRoot()`, no shared navigation state
- `FireTabRoot` (line 14) -- `TabView` without `selection` binding
- `FireAppDelegate` (line 5) -- Only `willPresent`, no `didReceive`
- `FireSystemNotificationPresenter.present(alert:)` (line 118) -- Puts `topicId`,
  `postNumber`, `messageId` into `userInfo`; no inbox notification `id`
- `NotificationAlertState` (uniffi line 604) -- `message_id`, `notification_type`, `topic_id`,
  `post_number`; no `id` (inbox row id)
- `NotificationCenterState` (uniffi line 777) -- Exposes `full`, `has_loaded_full`,
  `full_next_offset`, bidirectional read-sync in core
- `DiscourseNotificationType` (Swift) -- 15 of 40+ types; uses `groupedLikes` for type 19
  instead of Discourse canonical `likedConsolidated`

## Design

### Key Design Decisions

1. **Anchored topic fetch is the primary mechanism, UI scroll is secondary.** The Discourse
   API `/t/{topicId}/{postNumber}.json` returns a window of posts centered on `postNumber`.
   The current `loadTopicDetail` always fetches from the beginning. For notification
   tap-through, `postNumber` must flow from the notification row through `loadTopicDetail`
   into `TopicDetailQueryState.post_number`, so the server returns the correct window.
   `ScrollViewReader` scroll-to is only the follow-up step after the correct window is
   loaded.

   Rejected: scroll-only approach -- in a 500-post topic, post #487 won't be in the initial
   window at all.

2. **MessageBus-triggered refresh preserves the anchored position.** The current
   `scheduleTopicDetailRefresh` at line 1145 hardcodes `postNumber: nil`. After anchored
   load, a refresh must not reset the window. Store the active `targetPostNumber` per topic
   in `FireAppViewModel` and reuse it in the refresh path. On explicit pull-to-refresh
   (user-initiated), reset to `nil` (standard from-beginning behavior).

   Rejected: always re-fetching from beginning on MessageBus events -- loses the user's
   position.

3. **Unified tap handler for all notification rows, not just topic-bearing rows.** Every
   notification tap must: (a) mark read if unread, (b) dispatch to the type-appropriate
   destination. Currently, mark-read and navigation are bundled inside the `NavigationLink`
   conditional, making non-topic rows completely inert. Extract a shared
   `handleNotificationTap` function that all rows call.

   Rejected: keeping the current split between NavigationLink rows and display-only rows --
   leaves badge/follower/membership notifications as dead-ends.

4. **App-level navigation coordinator for deep linking.** Lift a `FireNavigationState`
   `ObservableObject` from `FireTabRoot` up to `FireApp`. `FireAppDelegate.didReceive`
   writes a pending deep link to this shared object. `FireTabRoot` observes it, switches tab
   selection, and pushes the appropriate destination via `NavigationStack(path:)`. Cold-start
   is handled by the pending link persisting until session restore completes.

   Rejected: giving `FireAppDelegate` direct access to `FireAppViewModel` -- the delegate
   outlives SwiftUI lifecycle and creates ownership problems. Rejected: URL scheme routing --
   unnecessary indirection for in-app deep links.

5. **Notification history reuses core's `full` state, not a separate array.** The Rust
   `FireNotificationRuntime` already maintains `full`, `full_next_offset`, and bidirectional
   read-sync with `recent`. The iOS history view should read from
   `NotificationCenterState.full` via `notificationState()`, and page via
   `fetchNotifications(limit: nil, offset: state.fullNextOffset)`. No separate
   `notificationHistory` array.

   Rejected: maintaining a separate `notificationHistory` array on `FireAppViewModel` --
   would desync with core's `full` list on mark-read, mark-all-read, and MessageBus live
   merge.

6. **This milestone scope: topic deep link done thoroughly, profile/badge deferred
   explicitly.** Profile and badge views don't exist yet and are separate feature scopes.
   For types that would route to profile/badge, the tap handler marks read and shows a short
   toast. This is an explicit, visible no-op rather than a silent dead-end.

   Rejected: attempting profile/badge routing in this milestone -- creates unfinished views.
   Rejected: silent no-op -- user gets no feedback on tap.

7. **System notification tap: navigate only, do not attempt mark-read from tap payload.**
   `NotificationAlertState` lacks the inbox notification `id`. Adding it requires Rust
   changes to the MessageBus alert parser. For this milestone, system notification tap
   navigates to the topic; the notification tab's own refresh will sync read state.

   Rejected: attempting mark-read without the inbox id -- would require a
   search-by-topic-id-and-post-number workaround that is fragile.

### Complete Notification Type Routing Table

| Type ID | Canonical Name | Destination | Required Fields | Missing-Field Behavior |
|---------|----------------|-------------|-----------------|------------------------|
| 1 | mentioned | Topic(scrollTo: postNumber) | topicId | No navigation |
| 2 | replied | Topic(scrollTo: postNumber) | topicId | No navigation |
| 3 | quoted | Topic(scrollTo: postNumber) | topicId | No navigation |
| 4 | edited | Topic(scrollTo: postNumber) | topicId | No navigation |
| 5 | liked | Topic(scrollTo: postNumber) | topicId | No navigation |
| 6 | privateMessage | Topic(scrollTo: postNumber) | topicId | No navigation |
| 7 | invitedToPrivateMessage | Topic(scrollTo: postNumber) | topicId | No navigation |
| 8 | inviteeAccepted | [Deferred] Profile | username | Toast |
| 9 | posted | Topic(scrollTo: postNumber) | topicId | No navigation |
| 10 | movedPost | Topic(scrollTo: postNumber) | topicId | No navigation |
| 11 | linked | Topic(scrollTo: postNumber) | topicId | No navigation |
| 12 | grantedBadge | [Deferred] Badge | badgeId | Toast |
| 13 | invitedToTopic | Topic(scrollTo: postNumber) | topicId | No navigation |
| 14 | custom | Topic(scrollTo: postNumber) | topicId | No navigation |
| 15 | groupMentioned | Topic(scrollTo: postNumber) | topicId | No navigation |
| 16 | groupMessageSummary | Topic (PM thread) | topicId | No navigation |
| 17 | watchingFirstPost | Topic | topicId | No navigation |
| 18 | topicReminder | Topic | topicId | No navigation |
| 19 | likedConsolidated | Topic(scrollTo: postNumber) | topicId | No navigation |
| 20 | postApproved | Topic(scrollTo: postNumber) | topicId | No navigation |
| 22 | membershipRequestAccepted | Explicit no-op | -- | Mark read only |
| 24 | bookmarkReminder | Topic(scrollTo: postNumber) | topicId | No navigation |
| 25 | reaction | Topic(scrollTo: postNumber) | topicId | No navigation |
| 800 | following | [Deferred] Profile | username | Toast |
| 801 | followingCreatedTopic | Topic | topicId | No navigation |
| 802 | followingReplied | Topic(scrollTo: postNumber) | topicId | No navigation |
| 900 | circlesActivity | Topic(scrollTo: postNumber) | topicId | No navigation |
| other | unknown | Topic(scrollTo: postNumber) | topicId | No navigation |

Username resolution for deferred profile routing: `data.displayUsername` ->
`data.username` -> `data.originalUsername` (all three present on `NotificationDataState`).

### Navigation State Model

```swift
@MainActor
final class FireNavigationState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var pendingDeepLink: FireDeepLink?

    struct FireDeepLink: Equatable {
        let topicId: UInt64
        let postNumber: UInt32?
    }
}
```

Owned by `FireApp`, injected into `FireTabRoot` via `@EnvironmentObject`.
`FireAppDelegate.didReceive` writes to `pendingDeepLink` via the shared instance.
`FireTabRoot` observes it, switches `selectedTab` to 1, pushes topic detail into the
notification tab's `NavigationStack(path:)`.

## Phased Implementation

### Phase 1: Anchored Topic Fetch from Notification Tap

**File: `native/ios-app/App/FireAppViewModel.swift`**

- Change `loadTopicDetail` signature to accept optional `targetPostNumber: UInt32? = nil`.
  Pass it into `TopicDetailQueryState(postNumber: targetPostNumber)`.
- Store active `targetPostNumber` per topic in
  `private var topicDetailTargetPostNumbers: [UInt64: UInt32] = [:]`.
- In `scheduleTopicDetailRefresh`, read `topicDetailTargetPostNumbers[topicId]` and pass it
  as `postNumber` instead of `nil`. This preserves the anchored window on MessageBus refresh.
- Add `func clearTopicDetailAnchor(topicId: UInt64)` that removes from
  `topicDetailTargetPostNumbers` -- called on explicit pull-to-refresh.

**File: `native/ios-app/App/FireTopicDetailView.swift`**

- Add `scrollToPostNumber: UInt32? = nil` parameter. Store as `@State`.
- Wrap `ScrollView` in `ScrollViewReader`. After `detail` loads, use `.onChange(of: detail)`
  to fire `proxy.scrollTo(scrollToPostNumber, anchor: .top)` once.
- Pass `targetPostNumber: scrollToPostNumber` into
  `viewModel.loadTopicDetail(topicId:targetPostNumber:)`.
- On `.refreshable`, call `viewModel.clearTopicDetailAnchor(topicId:)` then force-reload
  with `targetPostNumber: nil`.
- Assign `.id(post.postNumber)` to each `FirePostRow` for `ScrollViewReader` targeting.

**File: `native/ios-app/App/FireNotificationsView.swift`**

- Pass `scrollToPostNumber: item.postNumber` to `FireTopicDetailView`.
- Existing callers (`FireHomeView`, `FireSearchView`, `FireFilteredTopicListView`) continue
  to pass `scrollToPostNumber: nil` (default), unchanged.

### Phase 2: Unified Tap Handler and Notification Type Expansion

**File: `native/ios-app/App/FireNotificationsView.swift`**

- Replace `DiscourseNotificationType` with full Discourse/LinuxDo enum (40+ cases). Use
  Discourse canonical names: rename `groupedLikes` -> `likedConsolidated`, add all missing
  types from `references/fluxdo/lib/models/notification.dart`.
- Extract `handleNotificationTap(_:)` function that:
  1. If `!item.read`, calls `viewModel.markNotificationRead(id: item.id)`.
  2. Switches on `discourseType`:
     - `inviteeAccepted`, `following`: show toast (mark read, no navigation).
     - `grantedBadge`: show toast (mark read, no navigation).
     - `membershipRequestAccepted`: mark read only, no feedback.
     - All others: if `topicId != nil`, navigate to
       `FireTopicDetailView(scrollToPostNumber: item.postNumber)`. If `topicId == nil`,
       no navigation.
- Replace the current `if let stubRow / else` split with a single `Button` wrapping each
  row that calls `handleNotificationTap`, and a `@State var navigationDestination` that
  triggers navigation via `.navigationDestination(item:)`.
- Update `displayDescription`, `typeSystemImage`, `typeIconColor` for all new types.

### Phase 3: App-Level Navigation Coordinator and System Notification Deep Link

**File: `native/ios-app/App/FireNavigationState.swift` (new)**

- Define `FireNavigationState: ObservableObject` with `@Published var selectedTab`,
  `@Published var pendingDeepLink: FireDeepLink?`, and `struct FireDeepLink`.

**File: `native/ios-app/App/FireApp.swift`**

- Create `@StateObject private var navigationState = FireNavigationState()`.
- Inject as `.environmentObject(navigationState)` on `FireTabRoot()`.

**File: `native/ios-app/App/FireAppDelegate.swift`**

- Add `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
- Extract `topicId` and `postNumber` from
  `response.notification.request.content.userInfo`.
- Write to `FireNavigationState.shared.pendingDeepLink`.
- Handle both `Int` and `UInt64` value types defensively.

**File: `native/ios-app/App/FireTabRoot.swift`**

- Bind `TabView(selection: $navigationState.selectedTab)`.
- Add `.tag(0)`, `.tag(1)`, `.tag(2)` to tabs.
- Convert `FireNotificationsView`'s internal `NavigationStack` to accept a `path` binding.
- On `.onChange(of: navigationState.pendingDeepLink)`, set `selectedTab = 1`, push topic
  detail into the navigation path, then clear `pendingDeepLink`.
- Guard consumption behind `viewModel.session.readiness.canReadAuthenticatedApi`.

### Phase 4: Notification History via Core's Full State

**File: `native/ios-app/App/FireNotificationHistoryView.swift` (new)**

- On appear, calls `viewModel.loadNotificationFullPage(offset: nil)` (first page).
- Reads `viewModel.notificationFullList` which is driven by `NotificationCenterState.full`.
- Shares the same row rendering and tap handler from Phase 2.
- Footer loading indicator; when it appears, calls
  `viewModel.loadNotificationFullPage(offset: viewModel.notificationFullNextOffset)`.
- Pull-to-refresh resets: calls `viewModel.loadNotificationFullPage(offset: nil)`.

**File: `native/ios-app/App/FireAppViewModel.swift`**

- Add `@Published var notificationFullList: [NotificationItemState] = []`
- Add `@Published var notificationFullNextOffset: UInt32? = nil`
- Add `@Published var isLoadingNotificationFullPage: Bool = false`
- Add `@Published var hasMoreNotificationFull: Bool = false`
- Add `func loadNotificationFullPage(offset: UInt32?) async`:
  1. Call `sessionStore.fetchNotifications(limit: nil, offset: offset)`.
  2. Read updated state via `sessionStore.notificationState()`.
  3. Set `notificationFullList = state.full`,
     `notificationFullNextOffset = state.fullNextOffset`,
     `hasMoreNotificationFull = state.fullNextOffset != nil`.
- Update `markNotificationRead(id:)` and `markAllNotificationsRead()`: after the API call
  returns the updated `NotificationCenterState`, also update `notificationFullList` from
  `state.full` if `has_loaded_full` is true.
- Add "查看全部" `NavigationLink` at the bottom of the recent list in
  `FireNotificationsView`.

### Phase 5: Verification

- `xcodebuild build` for compilation.
- Run existing tests.
- Manual verification matrix:
  - Tap "replied" notification on a 200-post topic where reply is post #180 -> server
    returns anchored window around #180, detail view scrolls to it.
  - MessageBus update while viewing post #180 -> refresh preserves the #180 window.
  - Pull-to-refresh on topic detail -> resets to beginning.
  - Tap "grantedBadge" notification -> marked read, toast shown.
  - Tap "following" notification -> marked read, toast shown.
  - Tap "membershipRequestAccepted" -> marked read, no toast.
  - Background notification with topicId tap -> app opens, switches to notifications tab,
    navigates to topic detail.
  - Background notification tap during cold start -> deep link held, consumed after session
    restore.
  - "查看全部" -> history loads from core `full`, scroll down uses server `next_offset`.
  - Mark-read in history view -> both history and recent list reflect the change.
  - "全部已读" -> both views update.

## Architectural Notes

- **No Rust core changes required for phases 1-4.** `TopicDetailQueryState.post_number` is
  already plumbed through. `NotificationCenterState.full` + `full_next_offset` are already
  exposed. The `fetchNotifications` API updates the core runtime's `full` list with
  bidirectional read-sync.
- **`NotificationAlertState` does not carry inbox `notification.id`.** System notification
  tap cannot mark a specific notification read. This is accepted for this milestone. A
  follow-up could investigate whether the `/notification-alert/{userId}` MessageBus channel
  payload includes the notification id.
- **Pagination uses server-returned `next_offset`, not computed `offset += 60`.** The core's
  `full_next_offset` is set from `parse_notification_list_response_value`.
- **`DiscourseNotificationType` naming follows Discourse/Fluxdo canonical names** (e.g.,
  `likedConsolidated` not `groupedLikes`).
- **What is NOT changed:** Rust core notification runtime, MessageBus subscription logic,
  background polling logic, `NotificationAlertState` model, the `recent` vs `full` split
  in core.
- **Deep link coordinator is a separate `ObservableObject`**, not bolted onto
  `FireAppViewModel`, because the delegate needs to write to it before `FireAppViewModel`
  exists (cold start).

## File Change Summary

- `native/ios-app/App/FireAppViewModel.swift` -- Add `targetPostNumber` to
  `loadTopicDetail`; preserve anchor in MessageBus refresh; add `notificationFullList`
  properties driven by core `full`; sync full list on mark-read; add
  `loadNotificationFullPage`
- `native/ios-app/App/FireTopicDetailView.swift` -- Add `scrollToPostNumber` parameter;
  wrap in `ScrollViewReader`; pass anchor to `loadTopicDetail`; assign
  `.id(post.postNumber)` to rows; reset anchor on pull-to-refresh
- `native/ios-app/App/FireNotificationsView.swift` -- Expand notification type enum to 40+
  canonical names; extract unified `handleNotificationTap`; replace NavigationLink split
  with Button + navigationDestination; add "查看全部" link; complete display text/icons
- `native/ios-app/App/FireNavigationState.swift` -- New: `ObservableObject` with
  `selectedTab`, `pendingDeepLink`, `FireDeepLink`
- `native/ios-app/App/FireNotificationHistoryView.swift` -- New: paginated history view
  reading from core `full` state
- `native/ios-app/App/FireApp.swift` -- Create and inject `FireNavigationState` as
  environment object
- `native/ios-app/App/FireTabRoot.swift` -- Bind `TabView(selection:)`; consume
  `pendingDeepLink` to switch tab and push detail; guard behind session readiness
- `native/ios-app/App/FireAppDelegate.swift` -- Add `didReceive` handler; extract
  `topicId`/`postNumber` from `userInfo`; write to `FireNavigationState.pendingDeepLink`
- `native/ios-app/Fire.xcodeproj/project.pbxproj` -- Add `FireNavigationState.swift` and
  `FireNotificationHistoryView.swift` to build targets
