# Restructure Developer Tools Page and Convert Private Messages to IM Chat

Two independent features delivered in sequence: Phase A flattens the developer tools navigation and decomposes a 2033-line monolith; Phase B converts private messaging from post-reply style to Telegram-style IM chat. Phase A merges first; Phase B starts from a separate branch after Phase A lands.

## Feasibility Assessment

**Phase A (Developer Page):** Fully feasible. The entire change is a Swift-side navigation and file decomposition refactor. All views in `FireDiagnosticsView.swift` are `private struct`s that can be extracted to standalone files by removing the `private` modifier. The shared `FireDiagnosticsViewModel` already owns all state; lifting it to the parent view is a one-line `@StateObject` move. No Rust or UniFFI changes are needed. The unauthenticated entry point (`FireOnboardingView.swift`, line 117) is a single NavigationLink destination swap.

**Phase B (Chat IM):** Fully feasible. The existing `FireTopicDetailStore` already provides topic loading, reply submission, MessageBus real-time updates, typing presence, and pagination -- all reusable without modification. Content rendering tools already exist: `plainTextFromHtml(rawHtml:)` (Rust UniFFI function) and `FireTopicPresentation.imageAttachments(from:baseURLString:)` (Swift helper). The dual-endpoint merge (inbox + sent) is a client-side operation using existing `fetchPrivateMessages(kind:page:)`. No Rust or backend changes are needed.

## Current Surface Inventory

### Developer Tools (Phase A)

- `native/ios-app/App/FireDeveloperToolsView.swift` -- first-level page: session info section (account status, login stage, Base URL, Bootstrap, site metadata, CSRF, API permissions) + actions section (diagnostics NavigationLink, refresh bootstrap, restore session)
- `native/ios-app/App/FireDiagnosticsView.swift` (2033 lines) -- second-level monolith containing:
  - Lines 5-138: `FireDiagnosticsTextWindow`, `FireDiagnosticsPagedTextDocument`, `FireDiagnosticsShareRequest` (data models)
  - Lines 140-605: `FireDiagnosticsViewModel` (shared ViewModel for all diagnostic features)
  - Lines 609-1144: `FireDiagnosticsView` (main dashboard with 5 cards: network, logs, APM, push, export)
  - Lines 1148-1263: `FireNetworkTracesListView`, `FireRequestTraceRow` (network list, private)
  - Lines 1267-1801: `FireRequestTraceDetailView` (4-tab request inspector, private)
  - Lines 1805-1941: `FireLogFilesListView`, `FireDiagnosticsLogView` (log viewer, private)
  - Lines 1943-1971: `FireDiagnosticsTextView` (UIViewRepresentable, private)
  - Lines 1975-2016: `FireDiagnosticsPresentation` (formatting helpers, private)
  - Lines 2018-2033: `FireActivityShareSheet` (UIViewControllerRepresentable, private)
- `native/ios-app/App/FireOnboardingView.swift` (line 117-121) -- unauthenticated entry: NavigationLink to `FireDiagnosticsView`
- `native/ios-app/App/FireProfileView.swift` (line 294) -- authenticated entry: NavigationLink to `FireDeveloperToolsView`
- `native/ios-app/Sources/FireAppSession/APM/` -- APM module: `FireAPMManager.swift`, `FireAPMModels.swift`, `FireAPMEventStore.swift`, `FireAPMMainThreadStallMonitor.swift`, `FireAPMResourceSampler.swift`

### Private Messages (Phase B)

- `native/ios-app/App/FirePrivateMessagesView.swift` -- inbox/sent segmented picker + conversation list
- `native/ios-app/App/FirePrivateMessagesViewModel.swift` -- list state management, pagination, deduplication via `deduplicatedRows`/`deduplicatedUsers`
- `native/ios-app/App/FireTopicDetailView.swift` -- reused for PM thread display (post-reply style); detects PM via `isPrivateMessageThread` / `archetype == "private_message"`
- `native/ios-app/App/Stores/FireTopicDetailStore.swift` -- data store for topic detail: loading, reply submission, MessageBus subscription, typing presence, pagination
- `native/ios-app/App/FireComposerView.swift` -- message composition; supports `.privateMessage` and `.advancedReply(isPrivateMessage: true)` routes
- `native/ios-app/App/FireTopicPresentation.swift` -- `plainTextFromHtml` usage, `imageAttachments(from:baseURLString:)`, `isPrivateMessageArchetype()`, timestamp formatting
- `native/ios-app/App/FireProfileView.swift` (line 156) -- NavigationLink to `FirePrivateMessagesView`
- `rust/crates/fire-models/src/topic.rs` -- `TopicListKind::PrivateMessagesInbox`, `TopicListKind::PrivateMessagesSent`
- `rust/crates/fire-models/src/topic_detail.rs` -- `PrivateMessageCreateRequest`, `DraftData`
- `rust/crates/fire-uniffi-types/src/records/topic_list.rs` -- `TopicListKindState`, `TopicRowState`, `TopicParticipantState` (shared across `fire-uniffi-topics`, `fire-uniffi-search`, and the `FireAppCore` facade after the UniFFI multi-namespace split; see `docs/architecture/uniffi-multi-namespace-split.md`)

## Design

### Phase A: Developer Tools -- Flatten to Single-Level Navigation

Target structure:

```
Profile Tab -> Menu -> FireDeveloperToolsView (6 NavigationLinks + action buttons)
                         |-> Account Status (FireAccountStatusView)
                         |-> Network (FireNetworkDiagnosticsView -> FireNetworkTraceDetailView)
                         |-> Logs (FireLogDiagnosticsView)
                         |-> APM (FireAPMDiagnosticsView)
                         |-> Push Diagnostics (FirePushDiagnosticsView)
                         |-> Export (FireExportDiagnosticsView)
```

Each NavigationLink row displays a summary preview:

| Item | SF Symbol | Preview Content |
|------|-----------|-----------------|
| Account Status | `person.circle` | Status dot + username or "not logged in", subtitle: login stage |
| Network | `network` | Total requests, succeeded, failed, avg latency |
| Logs | `doc.text` | File count, total size |
| APM | `chart.bar` | CPU %, memory footprint, crash/stall counts |
| Push Diagnostics | `bell` | Authorization status, registration state |
| Export | `square.and.arrow.up` | Truncated session ID |

Key design decisions:

1. **Single shared ViewModel** instead of per-section ViewModels. `FireDiagnosticsViewModel` is created as `@StateObject` at the top-level `FireDeveloperToolsView` and passed via `@ObservedObject` to each child. Alternative rejected: per-section ViewModels would mean duplicate Rust FFI calls and no shared cache across sections.

2. **Extract to `DeveloperTools/` subdirectory** instead of keeping flat in `App/`. Alternative rejected: leaving 10+ files flat in `App/` (which already has 30+ files) would worsen discoverability. The new directory mirrors existing patterns like `App/Stores/`, `App/Push/`.

3. **Access level promotion from `private` to `internal`** for all extracted types. Alternative rejected: making them `public` would over-expose implementation details; `internal` is sufficient since all consumers are within the same module.

4. **`.sheet(item:)` on `FireExportDiagnosticsView`** instead of the top-level view. Alternative rejected: placing it on the top-level would require passing share request state through all child views. Only the export page triggers shares.

5. **Unauthenticated entry points to new `FireDeveloperToolsView`** instead of keeping the direct jump to diagnostics. Alternative rejected: a direct jump to the old `FireDiagnosticsView` would bypass the new structure and lose access to account status and actions.

### Phase B: Private Messages -- Telegram-Style IM Chat

Target structure:

```
Profile -> Chat -> FireChatView [Tab: Conversations | Contacts]
                     |-> Tab Conversations: FireChatConversationListView
                     |     |-> FireChatDetailView (bubble-style chat)
                     |-> Tab Contacts: FireChatContactListView
                           |-> FireChatDetailView or new conversation
```

Key design decisions:

1. **Unified conversation list** (merge inbox + sent, deduplicate by `topic.id`) instead of keeping the inbox/sent segmented picker. Alternative rejected: separate inbox/sent tabs do not match IM mental models; users expect a single chronological list of all conversations.

2. **Contacts derived from PM participants** instead of a global user directory. Data source: extract unique `TopicParticipantState` from all PM topics, resolve against `TopicUserState` for avatars, filter out current user. Alternative rejected: a full user directory would require additional API calls and is beyond the current scope.

3. **Reuse `FireTopicDetailStore` unchanged** for chat detail data operations instead of building a new store. The store already provides `loadTopicDetail`, `submitReply`, `maintainTopicDetailSubscription`, `beginTopicReplyPresence`, and `preloadTopicPostsIfNeeded`. Only the rendering layer changes. Alternative rejected: a new dedicated store would duplicate all existing logic for no benefit.

4. **`plainTextFromHtml` + `imageAttachments` for content rendering** instead of inline HTML rendering (WKWebView) or full HTML-to-AttributedString. Alternative rejected: WKWebView in chat bubbles has severe performance and sizing issues; full AttributedString conversion is complex. Plain text + image attachments matches the Telegram approach.

5. **New `FireChatDetailView` rather than modifying `FireTopicDetailView`** to add a bubble mode. Alternative rejected: mixing forum-style and chat-style rendering in one view would create excessive conditional branching and coupling. Forum topics continue using `FireTopicDetailView` unchanged.

6. **Group PM detection via `participants.count > 2`** (including self). In group PMs, received bubbles show sender avatar + username above the bubble. In 1-on-1, these are omitted. Alternative rejected: always showing avatars wastes space in 1-on-1 conversations.

Chat bubble layout:

```swift
// Received message (left-aligned):
HStack(alignment: .bottom) {
    if isGroupChat { FireAvatarView(size: 28) }
    VStack(alignment: .leading) {
        if isGroupChat { Text(senderUsername).font(.caption) }
        Text(plainText)
            .padding(12)
            .background(Color(.secondarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        ForEach(images) { image in /* AsyncImage in rounded rect */ }
        Text(timestamp).font(.caption2).foregroundStyle(.tertiary)
    }
    Spacer(minLength: UIScreen.main.bounds.width * 0.25)
}

// Sent message (right-aligned):
HStack(alignment: .bottom) {
    Spacer(minLength: UIScreen.main.bounds.width * 0.25)
    VStack(alignment: .trailing) {
        Text(plainText)
            .padding(12)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        ForEach(images) { image in /* AsyncImage in rounded rect */ }
        Text(timestamp).font(.caption2).foregroundStyle(.tertiary)
    }
}
```

Conversation list data merge:

```swift
// FireChatConversationListViewModel
func load() async {
    async let inboxResult = fetchPrivateMessages(.privateMessagesInbox, nil)
    async let sentResult = fetchPrivateMessages(.privateMessagesSent, nil)
    let (inbox, sent) = try await (inboxResult, sentResult)

    var seen = Set<UInt64>()
    var merged: [TopicRowState] = []
    for row in (inbox.rows + sent.rows)
        .sorted(by: { $0.activityTimestampUnixMs > $1.activityTimestampUnixMs }) {
        if seen.insert(row.topic.id).inserted {
            merged.append(row)
        }
    }
    self.rows = merged
    // Extract contacts: unique participants across all topics, excluding self
}
```

## Phased Implementation

### Phase 1: Extract ViewModel and shared utilities

**File: `native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift`** (new, ~470 lines)

- Extract from `FireDiagnosticsView.swift` lines 5-605
- Contains: `FireDiagnosticsTextWindow`, `FireDiagnosticsPagedTextDocument`, `FireDiagnosticsShareRequest`, `FireDiagnosticsViewModel`
- Remove `private` access modifier from all types (promote to `internal`)

**File: `native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift`** (new, ~100 lines)

- Extract from `FireDiagnosticsView.swift` lines 1943-2033
- Contains: `FireDiagnosticsPresentation` (lines 1975-2016), `FireDiagnosticsTextView` (lines 1943-1971), `FireActivityShareSheet` (lines 2018-2033)
- Extract `miniStat` helper as a reusable `View` struct (currently inlined in multiple cards)
- Remove `private` access modifiers

Build must succeed after this phase. The original `FireDiagnosticsView.swift` still exists and compiles -- it just has duplicate types that will be removed in Phase 3.

### Phase 2: Extract section detail views

**File: `native/ios-app/App/DeveloperTools/FireAccountStatusView.swift`** (new, ~100 lines)

- Extract `sessionSection` from `FireDeveloperToolsView.swift` lines 33-104
- Takes `@ObservedObject var viewModel: FireAppViewModel`
- Displays: account status dot, login stage, Base URL, Bootstrap, site metadata, site settings, CSRF, API permissions

**File: `native/ios-app/App/DeveloperTools/FireNetworkDiagnosticsView.swift`** (new, ~130 lines)

- Extract from `FireDiagnosticsView.swift` lines 1148-1263
- Contains: `FireNetworkTracesListView`, `FireRequestTraceRow`
- Takes `@ObservedObject var diagnosticsViewModel: FireDiagnosticsViewModel`
- Manages `startTraceAutoRefresh` / `stopTraceAutoRefresh` lifecycle

**File: `native/ios-app/App/DeveloperTools/FireNetworkTraceDetailView.swift`** (new, ~540 lines)

- Extract from `FireDiagnosticsView.swift` lines 1267-1801
- Contains: `FireRequestTraceDetailView` with 4 tabs (Overview, Request, Response, Timeline)
- Takes `@ObservedObject var diagnosticsViewModel: FireDiagnosticsViewModel` and `traceID: UInt64`

**File: `native/ios-app/App/DeveloperTools/FireLogDiagnosticsView.swift`** (new, ~150 lines)

- Extract from `FireDiagnosticsView.swift` lines 1805-1941
- Contains: `FireLogFilesListView`, `FireDiagnosticsLogView`
- Takes `@ObservedObject var diagnosticsViewModel: FireDiagnosticsViewModel`

**File: `native/ios-app/App/DeveloperTools/FireAPMDiagnosticsView.swift`** (new, ~80 lines)

- Extract from `FireDiagnosticsView.swift` `apmCard` content (lines 887-946)
- Promoted from inline card to standalone detail page
- Shows: CPU %, memory, crash count, stall count, recent APM events list
- Takes `@ObservedObject var diagnosticsViewModel: FireDiagnosticsViewModel`

**File: `native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift`** (new, ~90 lines)

- Extract from `FireDiagnosticsView.swift` `pushCard` content (lines 948-1025)
- Shows: authorization status, registration state, device token, error messages, action buttons
- Takes `@ObservedObject var pushCoordinator: FirePushRegistrationCoordinator`
- Reads `@Environment(\.scenePhase)` directly

**File: `native/ios-app/App/DeveloperTools/FireExportDiagnosticsView.swift`** (new, ~200 lines)

- Extract from `FireDiagnosticsView.swift` `supportBundleCard` content (lines 755-1119)
- Includes export action tiles, format badges, metadata views
- Owns `.sheet(item: $diagnosticsViewModel.shareRequest)` for share presentation
- Reads `@Environment(\.scenePhase)` directly
- Takes `@ObservedObject var diagnosticsViewModel: FireDiagnosticsViewModel`

### Phase 3: Build new top-level view and swap entry points

**File: `native/ios-app/App/DeveloperTools/FireDeveloperToolsView.swift`** (new, ~150 lines)

- Owns `@StateObject private var diagnosticsViewModel = FireDiagnosticsViewModel(...)`
- `List` with `.insetGrouped` style, 6 NavigationLink items with summary preview rows
- Bottom section: "Refresh Bootstrap" and "Restore Session" buttons (preserved from old file)
- `.task` modifier calls `diagnosticsViewModel.refresh()` and `pushCoordinator.refreshAuthorizationStatus()`
- `.navigationTitle("Developer Tools")`, `.navigationBarTitleDisplayMode(.inline)`

**File: `native/ios-app/App/FireOnboardingView.swift`** (modify, lines 117-121)

- Change NavigationLink destination from `FireDiagnosticsView(viewModel: viewModel)` to `FireDeveloperToolsView(viewModel: viewModel)`

**File: `native/ios-app/App/FireProfileView.swift`** -- unchanged. Already points to `FireDeveloperToolsView` (line 294). Audited; no changes needed.

**File: `native/ios-app/App/FireDeveloperToolsView.swift`** -- delete. Replaced by `DeveloperTools/FireDeveloperToolsView.swift`.

**File: `native/ios-app/App/FireDiagnosticsView.swift`** -- delete. All content redistributed to `DeveloperTools/` files.

### Phase 4: Build chat bubble and input components

**File: `native/ios-app/App/Chat/FireChatBubbleView.swift`** (new, ~120 lines)

- Takes: `post: TopicPostState`, `isSentByCurrentUser: Bool`, `isGroupChat: Bool`, `baseURLString: String`
- Renders plain text via `plainTextFromHtml(rawHtml: post.cooked)`
- Renders images via `FireTopicPresentation.imageAttachments(from: post.cooked, baseURLString:)`
- Left-aligned gray bubble for received, right-aligned accent-colored bubble for sent
- In group chat: shows sender avatar (28pt) and username above received bubbles
- Timestamp below bubble via `FireTopicPresentation.compactTimestamp`
- Max width constrained to 75% of screen width

**File: `native/ios-app/App/Chat/FireChatInputBar.swift`** (new, ~100 lines)

- Multi-line `TextField` with `.axis(.vertical)`, max 4 lines
- Send button (`arrow.up.circle.fill`), disabled when text length < `minPersonalMessagePostLength`
- Advanced composer button (`square.and.pencil`) opens `FireComposerView` with `.advancedReply(isPrivateMessage: true)`
- Typing presence strip (reuses `FireTypingPresenceStrip` pattern from `FireTopicDetailView`)
- `@FocusState` for keyboard management

### Phase 5: Build chat detail view

**File: `native/ios-app/App/Chat/FireChatDetailView.swift`** (new, ~300 lines)

- Takes: `topicRow: TopicRowState`, `@EnvironmentObject var topicDetailStore: FireTopicDetailStore`
- On appear: `topicDetailStore.loadTopicDetail(topicId:)`
- Renders posts from `topicDetailStore.topicDetails[topicId]?.postStream.posts`, sorted by `postNumber` ascending
- `ScrollView` + `LazyVStack` + `ScrollViewReader`, auto-scroll to bottom on initial load
- Input bar pinned via `.safeAreaInset(edge: .bottom)` containing `FireChatInputBar`
- On send: `topicDetailStore.submitReply(topicId:raw:replyToPostNumber: nil)`
- Lifecycle: `beginTopicDetailLifecycle` / `endTopicDetailLifecycle` in `.onAppear` / `.onDisappear`
- Real-time: `maintainTopicDetailSubscription(topicId:ownerToken:)` in `.task`
- Typing: `beginTopicReplyPresence` / `endTopicReplyPresence` tied to input focus
- Pagination: `preloadTopicPostsIfNeeded` on scroll-up
- Determines `isGroupChat` from `participants.count > 2`
- Determines `isSentByCurrentUser` by comparing `post.username` to `bootstrap.currentUsername`

### Phase 6: Build conversation list and contacts

**File: `native/ios-app/App/Chat/FireChatConversationListViewModel.swift`** (new, ~200 lines)

- Dual-endpoint fetch: `async let` for inbox and sent in parallel
- Merge: combine rows, sort by `activityTimestampUnixMs` descending, deduplicate by `topic.id`
- Pagination: independent `nextPageInbox` and `nextPageSent` cursors
- Contact extraction: unique `TopicParticipantState` from all topics, resolve avatars via `users`, exclude current user, deduplicate by `userId`
- Generation-based staleness protection (same pattern as `FirePrivateMessagesViewModel`)

**File: `native/ios-app/App/Chat/FireChatConversationListView.swift`** (new, ~120 lines)

- Each row: avatar (single or stacked for group), contact name (or comma-joined group names), last message preview text, relative timestamp
- Group PM row: overlapping avatar circles (`HStack(spacing: -8)`)
- NavigationLink to `FireChatDetailView`
- Pull-to-refresh, load-more on scroll to bottom

**File: `native/ios-app/App/Chat/FireChatContactListView.swift`** (new, ~80 lines)

- List of contacts from `viewModel.contacts`
- Each row: avatar + username
- Tap behavior: if existing conversation found in `viewModel.rows`, navigate to `FireChatDetailView`; otherwise open `FireComposerView` with `.privateMessage(recipients: [username])`

### Phase 7: Build top-level chat view and swap entry point

**File: `native/ios-app/App/Chat/FireChatView.swift`** (new, ~80 lines)

- Two-tab container using `Picker` (segmented style): "Conversations" / "Contacts"
- Owns `@StateObject` of `FireChatConversationListViewModel`
- Toolbar button for new message (opens `FireComposerView` with `.privateMessage`)
- `.navigationTitle("Messages")`

**File: `native/ios-app/App/FireProfileView.swift`** (modify, line 156)

- Change NavigationLink destination from `FirePrivateMessagesView(viewModel: viewModel)` to `FireChatView(viewModel: viewModel)`

**File: `native/ios-app/App/FirePrivateMessagesView.swift`** -- unchanged, kept for reference. Can be deleted once Phase B is verified and merged.

**File: `native/ios-app/App/FirePrivateMessagesViewModel.swift`** -- unchanged, kept for reference. Can be deleted once Phase B is verified and merged.

### Phase 8: Verify

Phase A verification:
- Xcode build succeeds with no warnings
- Profile -> Developer Tools: 6 items visible with summary previews
- Each item navigates to correct detail page; all features identical to pre-refactor
- Unauthenticated flow: Onboarding -> ant icon -> new Developer Tools page
- Network trace list/detail with 4 tabs functional
- Log file list/viewer functional
- APM real-time data displays correctly
- Push diagnostics action buttons work
- Export (Rust snapshot + APM bundle) works

Phase B verification:
- Xcode build succeeds with no warnings
- Conversation list: inbox + sent merged, sorted by time, no duplicates
- Contact list: all historical PM users listed, tap navigates or creates new conversation
- Chat detail: bubbles left/right aligned correctly, plain text + images render
- Send message: input bar send + advanced editor send both work
- MessageBus: incoming messages appear as new bubbles in real time
- Group PM: stacked avatars, sender username above received bubbles
- Typing presence: indicator shows when other user is typing
- Pagination: scroll up loads older messages
- Old `FirePrivateMessagesView` no longer referenced from navigation

## Architectural Notes

- **No Rust changes in either phase.** All modifications are Swift-side navigation, layout, and rendering. UniFFI bindings, models, and API orchestration remain untouched. Post the `fire-uniffi` multi-namespace split, every record referenced here (`TopicRowState`, `TopicPostState`, `TopicParticipantState`, `NotificationCenterState`, `LogFileSummaryState`, `NetworkTraceSummaryState`, etc.) is emitted from a per-domain crate (`fire-uniffi-types`, `fire-uniffi-diagnostics`, `fire-uniffi-notifications`, ...) into `Generated/FireUniFfi/*.swift`, but the type identifiers are unchanged and compile into the same Swift target — no `import` changes are required in Phase A or Phase B code.
- **No backend API changes.** Phase B works within existing Discourse PM endpoints (`/topics/private-messages/{username}.json`, `/topics/private-messages-sent/{username}.json`).
- **`FireTopicDetailStore` is not modified.** Phase B reuses it via `@EnvironmentObject` for all data operations. The store already handles PM topics identically to forum topics. `loadTopicDetail(topicId:targetPostNumber:force:)` now carries the anchor-aware timeline plumbing introduced by the topic detail anchor timeline feature (`topicDetailTargetPostNumbers`, `topicWindowStates`, `activeAnchorPostNumber`). Phase B calls `loadTopicDetail(topicId:)` without an anchor — the store loads Discourse's default post window for the topic, and `FireChatDetailView` does the client-side "scroll to latest" via a `ScrollViewReader` after the posts are sorted by `postNumber` ascending.
- **`FireTopicDetailView` is not modified.** Forum post rendering continues unchanged. Phase B creates a parallel rendering path for PM topics only.
- **`FireComposerView` is not modified.** Existing route types (`.privateMessage`, `.advancedReply(isPrivateMessage: true)`) are sufficient.
- **Xcode project file (`*.pbxproj`)** may need file reference updates for new/deleted files. Build verification after each phase catches this.
- **`@StateObject` lifecycle improvement in Phase A.** Moving `FireDiagnosticsViewModel` from `FireDiagnosticsView` to `FireDeveloperToolsView` means the ViewModel persists while navigating between section detail pages, preserving cached data.
- **Phase A and Phase B are fully independent.** Phase B does not depend on Phase A files. They are sequenced for branch hygiene, not technical dependency.

## File Change Summary

Phase A:
- `native/ios-app/App/DeveloperTools/FireAccountStatusView.swift` -- new; account status detail extracted from old `FireDeveloperToolsView`
- `native/ios-app/App/DeveloperTools/FireAPMDiagnosticsView.swift` -- new; APM detail extracted from `FireDiagnosticsView` apmCard
- `native/ios-app/App/DeveloperTools/FireDeveloperToolsView.swift` -- new; restructured first-level page with 6 NavigationLinks
- `native/ios-app/App/DeveloperTools/FireDiagnosticsShared.swift` -- new; shared presentation helpers, text view, share sheet, miniStat
- `native/ios-app/App/DeveloperTools/FireDiagnosticsViewModel.swift` -- new; ViewModel + data models extracted from FireDiagnosticsView
- `native/ios-app/App/DeveloperTools/FireExportDiagnosticsView.swift` -- new; export functionality extracted from FireDiagnosticsView supportBundleCard
- `native/ios-app/App/DeveloperTools/FireLogDiagnosticsView.swift` -- new; log file list + viewer extracted from FireDiagnosticsView
- `native/ios-app/App/DeveloperTools/FireNetworkDiagnosticsView.swift` -- new; network trace list + row extracted from FireDiagnosticsView
- `native/ios-app/App/DeveloperTools/FireNetworkTraceDetailView.swift` -- new; 4-tab request detail extracted from FireDiagnosticsView
- `native/ios-app/App/DeveloperTools/FirePushDiagnosticsView.swift` -- new; push diagnostics extracted from FireDiagnosticsView pushCard
- `native/ios-app/App/FireDeveloperToolsView.swift` -- delete; replaced by DeveloperTools/FireDeveloperToolsView.swift
- `native/ios-app/App/FireDiagnosticsView.swift` -- delete; all content redistributed to DeveloperTools/ files
- `native/ios-app/App/FireOnboardingView.swift` -- modify line 118; swap NavigationLink destination to new FireDeveloperToolsView

Phase B:
- `native/ios-app/App/Chat/FireChatBubbleView.swift` -- new; Telegram-style chat bubble component
- `native/ios-app/App/Chat/FireChatContactListView.swift` -- new; contact list derived from PM participants
- `native/ios-app/App/Chat/FireChatConversationListView.swift` -- new; unified conversation list with merged inbox + sent
- `native/ios-app/App/Chat/FireChatConversationListViewModel.swift` -- new; dual-endpoint fetch, merge, dedup, contact extraction
- `native/ios-app/App/Chat/FireChatDetailView.swift` -- new; Telegram-style chat detail with bubbles and bottom input bar
- `native/ios-app/App/Chat/FireChatInputBar.swift` -- new; multiline input bar with send and advanced composer buttons
- `native/ios-app/App/Chat/FireChatView.swift` -- new; two-tab container (Conversations / Contacts)
- `native/ios-app/App/FireProfileView.swift` -- modify line 156; swap NavigationLink destination to FireChatView
