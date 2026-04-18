# Redesign the iOS Profile Page ("我的")

## Breaking Change Notice

This redesign replaces the current `FireProfileView` diagnostic-oriented layout with a product-grade user profile. The existing session-info section and diagnostic actions move into a "developer tools" sub-page, preserving all current debug capabilities while removing them from the primary UX surface.

## Current Implementation Snapshot

The shipped iOS implementation now differs from the earliest proposal in a few important ways:

- The main profile tab is a grouped `List`-based overview page, not a single long `ScrollView` with a decorative gradient banner.
- Bookmarks moved above the activity feed so they remain visible without scrolling through long activity history.
- The profile tab shows only a short recent-activity preview. Full activity browsing moved into a dedicated `FireProfileActivityTimelineView` screen with segmented filtering.
- Developer tools and logout live behind the top-right gear menu instead of occupying permanent space at the bottom of the main profile page.
- Pull-to-refresh now reloads both profile/summary data and the user-action feed via `FireProfileViewModel.refreshAll()`.

## Feasibility Assessment

The Discourse backend already exposes all required data through well-documented endpoints: `GET /u/{username}.json` (identity, bio, trust level, flair, follow stats), `GET /u/{username}/summary.json` (activity stats, top topics/replies, badges), and `GET /user_actions.json` (activity feed). The Fluxdo Flutter reference client (`references/fluxdo/lib/models/user.dart`, `references/fluxdo/lib/pages/user_profile_page.dart`) proves these endpoints are stable and sufficient for a rich profile experience. The existing `FireTheme` design system provides a complete color palette and constant set. The Rust shared core (`fire-models`) currently lacks profile/badge types but adding them is straightforward serde work with no blockers.

Crate layering is clear: new API orchestration goes in `fire-core/src/core/users.rs` (following the pattern of `topics.rs`, `notifications.rs`, `search.rs`), payload parsing in `fire-core/src/user_payloads.rs`, and the UniFFI state adapter in `fire-uniffi/src/lib.rs`. On iOS, `FireSessionStore` (the existing actor wrapping `FireCoreHandle`) already exposes the pattern for adding new async methods that the ViewModel consumes. **Fully feasible.**

## Current Surface Inventory

- **`native/ios-app/App/FireProfileView.swift`** -- The main "我的" overview page. Contains: error banner, profile identity header, account shortcut rows, recent activity preview, and navigation into the full activity timeline.
- **`native/ios-app/App/FireProfileActivityTimelineView.swift`** -- Dedicated full activity screen. Hosts segmented filters (全部/话题/回复/被赞), pagination, error banner handling, and navigation into topic detail.
- **`native/ios-app/App/FireAppViewModel.swift`** -- Shared ViewModel. Exposes `session: SessionState`, `topicRows`, `errorMessage`, session lifecycle methods. `sessionStore: FireSessionStore?` and `sessionStoreValue()` are **private** (lines 152, 1956). No user-profile-specific API calls exist.
- **`native/ios-app/Sources/FireAppSession/FireSessionStore.swift`** -- The `actor` wrapping `FireCoreHandle` that is the iOS-side Rust entry point (line 65). All Rust API calls from the app go through this actor. New profile API methods will be added here.
- **`native/ios-app/App/SessionState+Helpers.swift`** -- Convenience extensions: `profileStatusTitle`, `profileDisplayName`, cookie mirroring.
- **`native/ios-app/App/FireTheme.swift`** -- Design system: accent/semantic/canvas/surface/text/border color tokens, corner radius constants.
- **`native/ios-app/App/FireComponents.swift`** -- Shared UI components. `FireAvatarView` (line 619) already supports `avatarTemplate` with `{size}` placeholder resolution, relative URL handling, and protocol-relative URL handling. No additional avatar work is needed.
- **`native/ios-app/App/FireDiagnosticsView.swift`** -- Diagnostic sub-page pushed from profile actions section.
- **`native/ios-app/App/FireTabRoot.swift`** -- TabView with 3 tabs; profile is tab index 2.
- **`rust/crates/fire-core/src/core/mod.rs`** -- `FireCore` aggregate. API orchestration lives in `core/topics.rs`, `core/notifications.rs`, `core/search.rs`, etc. New user profile orchestration goes in `core/users.rs` following the same pattern.
- **`rust/crates/fire-core/src/session_store.rs`** -- **Persistence helper only**: `PersistedSessionEnvelope`, `sanitize_snapshot_for_restore`, `write_atomic`. Not an API layer; must not receive profile fetch logic.
- **`rust/crates/fire-models/src/lib.rs`** -- Shared models. Has `TopicUser`, `SearchUser`, `TopicPost` etc. No `UserProfile`, `UserSummary`, `Badge`, or `UserAction` types.
- **`rust/crates/fire-uniffi/src/lib.rs`** -- UniFFI bridge. Holds `FireCoreHandle` wrapping `Arc<FireCore>`. Converts `fire_models` to `*State` records via `From` impls. All async methods follow the `run_on_ffi_runtime` pattern (line 2410+).
- **`docs/backend-api/05-users-search-and-notifications.md`** -- Documents user profile endpoints. `GET /u/{username}.json` returns `{ "user": User }` envelope (line 33).
- **`docs/backend-api/02-common-models.md`** -- Documents `User`, `UserSummary`, `Badge` JSON shapes.

## Design

### Key Design Decisions

1. **Dedicated profile ViewModel that receives a narrow service interface, not a direct `FireSessionStore` reference.**
   - Chosen: `FireProfileViewModel` owns profile-specific state and calls profile-fetching methods exposed through `FireAppViewModel` (which internally delegates to its private `sessionStore`). This matches how `FireAppViewModel` already mediates all Rust calls for topics, notifications, and search.
   - Rejected alternative A: Having `FireProfileViewModel` call `FireSessionStore` directly. This is not possible because `sessionStore` and `sessionStoreValue()` are private on `FireAppViewModel` (lines 152, 1956).
   - Rejected alternative B: Making `sessionStore` public or injecting a shared `FireSessionStore` at `FireTabRoot` level. This would break the current ownership model where `FireAppViewModel` is the single session mediator.
   - Why: Adding narrow wrapper methods to `FireAppViewModel` (e.g. `fetchUserProfile`, `fetchUserSummary`, `fetchUserActions`) keeps the existing architecture intact while enabling the new ViewModel. The methods are thin: they resolve the session store, call the Rust method, and return the result.

2. **Grouped overview page rather than a decorative banner layout.**
   - Chosen: A grouped `List` with a clean identity block, account shortcut rows, and a recent-activity preview.
   - Rejected: A long `ScrollView` with a decorative banner or hero treatment above the avatar.
   - Why: The GitHub Mobile-inspired direction values clarity over ornament. The grouped overview keeps the page flatter, denser, and easier to scan on both small and large phones.

3. **Trust level as a prominent visual element.**
   - Chosen: A colored pill/badge next to the username showing the trust level with a Discourse-aligned label (e.g. "领导者" for TL4, "老手" for TL3, "成员" for TL2, "基本" for TL1, "新人" for TL0).
   - Rejected: Hiding trust level in a detail sub-page.
   - Why: Trust level is the primary progression indicator on LinuxDo and a key motivator for community engagement. Making it visible on the profile reinforces the gamification loop.

4. **Session/debug info moves behind the gear menu instead of living in the main scroll body.**
   - Chosen: The top-right gear menu surfaces "Developer Tools" and logout actions while the main profile body remains user-facing.
   - Rejected: Removing session info entirely, or keeping it as a persistent bottom section in the main profile page.
   - Why: The debug info is valuable for development and support, but it should not compete with bookmarks, badges, or activity on the primary page.

5. **Phased data loading: bootstrap-local first, then network fetch.**
   - Chosen: On initial render, show what we already know from `SessionState` (username, user ID) in the header immediately, then fetch `/u/{username}.json` and `/u/{username}/summary.json` concurrently for full profile data. No offline cache is introduced in this phase; if the network fetch fails, the page shows the bootstrap-derived header with an error banner and a retry action.
   - Rejected: Blocking the whole page on network fetch.
   - Why: The profile tab is a frequent navigation target. Showing the cached identity immediately with a shimmer placeholder for stats/badges provides a responsive feel.

6. **Keep the self-profile overview action-oriented.**
   - Chosen: The main "我的" page exposes badges as a direct shortcut alongside bookmarks, history, drafts, invite links, and social lists. Public profiles still keep a wrapped badge section where the badges belong to the viewed user.
   - Rejected: Keeping a dedicated badge preview block on the self-profile overview.
   - Why: The self-profile overview is primarily an account hub. Surfacing badges as a first-level destination preserves reachability without competing with recent activity for vertical space.

7. **Activity separated into preview + dedicated timeline screen.**
   - Chosen: The main profile page shows only a short recent-activity preview, while `FireProfileActivityTimelineView` owns full filtering and pagination.
   - Rejected: Embedding the entire segmented activity timeline directly in the main profile page.
   - Why: Long activity lists were burying bookmarks and account actions. Splitting the experience restores first-screen clarity while still preserving full activity browsing.

8. **API response envelope parsing with dedicated raw types, not direct serde into shared models.**
   - Chosen: Each endpoint gets a raw/envelope parser in `fire-core/src/user_payloads.rs` that unwraps the response structure (e.g. `data["user"]` for `/u/{username}.json`, `data["user_summary"]` + top-level sideloads for `/summary.json`) before converting to `fire-models` types.
   - Rejected: Direct `serde::Deserialize` of the entire response into the shared model.
   - Why: Discourse endpoint responses have varying envelope structures. Fluxdo confirms `/u/{username}.json` wraps in `{"user": ...}` with fallback to bare object (`references/fluxdo/lib/services/discourse/_users.dart:45`). Summary responses sideload `topics` and `badges` at the root level, separate from the `user_summary` object. A dedicated parser layer handles these variations cleanly without polluting the shared model with envelope concerns.

9. **Lightweight `ProfileSummaryTopic` instead of reusing `TopicSummary`.**
   - Chosen: A dedicated `ProfileSummaryTopic` struct with only the fields present in `/summary.json` topic sideloads: id, title, slug, like_count, category_id, created_at.
   - Rejected: Reusing the existing `TopicSummary` (line 687 in `fire-models`).
   - Why: The existing `TopicSummary` is a topic-list model with 25+ fields (`posts_count`, `reply_count`, `views`, `excerpt`, `tags`, `posters`, read/unread state, etc.) that are absent from the summary sideload. Fluxdo uses a distinct lightweight model for this (`references/fluxdo/lib/models/user.dart:448`). Using `TopicSummary` would require making most fields optional or filling them with defaults, creating a confusing partial-initialization state.

### Target Screen Layout

```
+--------------------------------------------------+
|  Nav Bar: "我的"                          [gear]  |
+--------------------------------------------------+
|  [Avatar]  Display Name   [TL3]                  |
|            @username                              |
|            short bio                              |
|                                                    |
|  粉丝 / 关注 / 获赞                                |
|  加入时间 / 最近活跃 / 阅读时长 / 活跃分            |
|                                                    |
|  [我的书签] [浏览历史] [草稿箱] [我的勋章]          |
|  [邀请链接] [关注列表] [粉丝列表]                  |
|                                                    |
|  --- 最近动态 ---                                  |
|  [Activity 1]                                      |
|  [Activity 2]                                      |
|  [Activity 3]                                      |
|  [查看全部动态] -> dedicated timeline              |
+--------------------------------------------------+
```

### New Rust Types (`fire-models`)

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserProfile {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub trust_level: Option<u32>,
    pub bio_cooked: Option<String>,
    pub created_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub flair_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub profile_background_upload_url: Option<String>,
    pub card_background_upload_url: Option<String>,
    pub total_followers: Option<u32>,
    pub total_following: Option<u32>,
    pub can_follow: Option<bool>,
    pub is_followed: Option<bool>,
    pub gamification_score: Option<u32>,
    pub suspended_till: Option<String>,
    pub silenced_till: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSummaryStats {
    pub days_visited: u32,
    pub posts_read_count: u32,
    pub likes_received: u32,
    pub likes_given: u32,
    pub topic_count: u32,
    pub post_count: u32,
    pub time_read: u64,
    pub bookmark_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryTopic {
    pub id: u64,
    pub title: String,
    pub slug: Option<String>,
    pub like_count: u32,
    pub category_id: Option<u64>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryReply {
    pub id: u64,
    pub topic_id: u64,
    pub title: Option<String>,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryLink {
    pub url: String,
    pub title: Option<String>,
    pub clicks: u32,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryTopCategory {
    pub id: u64,
    pub name: Option<String>,
    pub topic_count: u32,
    pub post_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProfileSummaryUserReference {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
    pub count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserSummaryResponse {
    pub stats: UserSummaryStats,
    pub top_topics: Vec<ProfileSummaryTopic>,
    pub top_replies: Vec<ProfileSummaryReply>,
    pub top_links: Vec<ProfileSummaryLink>,
    pub top_categories: Vec<ProfileSummaryTopCategory>,
    pub most_replied_to_users: Vec<ProfileSummaryUserReference>,
    pub most_liked_by_users: Vec<ProfileSummaryUserReference>,
    pub most_liked_users: Vec<ProfileSummaryUserReference>,
    pub badges: Vec<Badge>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Badge {
    pub id: u64,
    pub name: String,
    pub description: Option<String>,
    pub badge_type_id: u32,
    pub image_url: Option<String>,
    pub icon: Option<String>,
    pub slug: Option<String>,
    pub grant_count: u32,
    pub long_description: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserAction {
    pub action_type: Option<i32>,
    pub topic_id: Option<u64>,
    pub post_id: Option<u64>,
    pub post_number: Option<u32>,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub username: Option<String>,
    pub acting_username: Option<String>,
    pub acting_avatar_template: Option<String>,
    pub category_id: Option<u64>,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserActionResponse {
    pub user_actions: Vec<UserAction>,
}
```

### New UniFFI Bridge Types (`fire-uniffi`)

```rust
#[derive(uniffi::Record, Debug, Clone)]
pub struct UserProfileState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub trust_level: u32,
    pub bio_cooked: Option<String>,
    pub created_at: Option<String>,
    pub last_seen_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub flair_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub profile_background_url: Option<String>,
    pub total_followers: u32,
    pub total_following: u32,
    pub gamification_score: Option<u32>,
    pub trust_level_label: String,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryState {
    pub stats: UserSummaryStatsState,
    pub top_topics: Vec<ProfileSummaryTopicState>,
    pub top_replies: Vec<ProfileSummaryReplyState>,
    pub top_categories: Vec<ProfileSummaryTopCategoryState>,
    pub most_liked_by_users: Vec<ProfileSummaryUserReferenceState>,
    pub badges: Vec<BadgeState>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserSummaryStatsState {
    pub days_visited: u32,
    pub likes_received: u32,
    pub likes_given: u32,
    pub topic_count: u32,
    pub post_count: u32,
    pub time_read_seconds: u64,
    pub bookmark_count: u32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopicState {
    pub id: u64,
    pub title: String,
    pub slug: Option<String>,
    pub like_count: u32,
    pub category_id: Option<u64>,
    pub created_at: Option<String>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryReplyState {
    pub id: u64,
    pub topic_id: u64,
    pub title: Option<String>,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub post_number: Option<u32>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryTopCategoryState {
    pub id: u64,
    pub name: Option<String>,
    pub topic_count: u32,
    pub post_count: u32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ProfileSummaryUserReferenceState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
    pub count: u32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BadgeState {
    pub id: u64,
    pub name: String,
    pub description: Option<String>,
    pub badge_type_id: u32,
    pub icon: Option<String>,
    pub image_url: Option<String>,
    pub slug: Option<String>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserActionState {
    pub action_type: i32,
    pub topic_id: Option<u64>,
    pub post_number: Option<u32>,
    pub title: Option<String>,
    pub slug: Option<String>,
    pub excerpt: Option<String>,
    pub category_id: Option<u64>,
    pub acting_username: Option<String>,
    pub acting_avatar_template: Option<String>,
    pub created_at: Option<String>,
}
```

### New Swift Types and ViewModel

```swift
// FireProfileViewModel.swift

@MainActor
final class FireProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfileState?
    @Published private(set) var summary: UserSummaryState?
    @Published private(set) var actions: [UserActionState] = []
    @Published private(set) var isLoadingProfile = false
    @Published private(set) var isLoadingActions = false
    @Published private(set) var hasLoadedActionsOnce = false
    @Published private(set) var selectedTab: ProfileTab = .all
    @Published private(set) var actionsOffset: Int = 0
    @Published private(set) var hasMoreActions = true
    @Published var errorMessage: String?
    @Published var actionsErrorMessage: String?

    enum ProfileTab: String, CaseIterable {
        case all      // filter "4,5" -- topics + replies combined
        case topics   // filter "4"   -- new topic actions only
        case replies  // filter "5"   -- reply actions only
        case liked    // filter "2"   -- was-liked actions (others liked my content)

        var actionFilter: String? {
            switch self {
            case .all:     return "4,5"
            case .topics:  return "4"
            case .replies: return "5"
            case .liked:   return "2"
            }
        }

        var title: String {
            switch self {
            case .all:     return "全部"
            case .topics:  return "话题"
            case .replies: return "回复"
            case .liked:   return "被赞"
            }
        }
    }

    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }
}
```

### User Action Type Reference (Discourse Constants)

| Constant | Value | Meaning | Used by tab |
|----------|-------|---------|-------------|
| like | 1 | I liked someone's content | -- (not used in v1) |
| wasLiked | 2 | Someone liked my content | "被赞" tab |
| newTopic | 4 | I created a topic | "话题" tab |
| reply | 5 | I replied to a topic | "回复" tab |
| 4,5 | -- | Combined topics + replies | "全部" tab |

Source: `references/fluxdo/lib/models/user_action.dart` constants, `references/fluxdo/lib/pages/user_profile_page.dart` tab filters `['summary', '4,5', '4', '5', '1', 'reactions']`.

### Trust Level Display Mapping

| trust_level | Label  | Color Token              |
|-------------|--------|--------------------------|
| 0           | 新人    | `FireTheme.tertiaryInk`  |
| 1           | 基本    | `FireTheme.subtleInk`    |
| 2           | 成员    | `FireTheme.success`      |
| 3           | 老手    | `FireTheme.accent`       |
| 4           | 领导者  | `FireTheme.warning`      |

### Badge Type Display Mapping

| badge_type_id | Tier   | Accent                   |
|---------------|--------|--------------------------|
| 1             | Gold   | `#FFD700` / warm gold    |
| 2             | Silver | `#C0C0C0` / cool grey    |
| 3             | Bronze | `#CD7F32` / warm bronze  |

### Interaction Specifications

| Element | Tap | Long Press | Scope |
|---------|-----|------------|-------|
| Avatar | Full-screen image preview | -- | v1 |
| Trust level pill | Info popover explaining the level | -- | v1 |
| Stats cell (关注/粉丝) | No-op | -- | future: navigate to follow/follower list |
| Badge chip | No-op | -- | future: navigate to badge detail page |
| "查看全部" badges | No-op | -- | future: navigate to full badge list page |
| Activity tab item | Switch tab content inline | -- | v1 |
| Activity row | Navigate to the corresponding topic/post | -- | v1 |
| Settings gear icon | No-op | -- | future: navigate to settings page |
| "我的书签" | No-op with "coming soon" toast | -- | future: bookmarks list (requires `GET /u/{username}/bookmarks.json`) |
| "开发者工具" | Push current diagnostics + session info page | -- | v1 |
| "退出登录" | Confirmation alert, then logout | -- | v1 |

### Future Scope (explicitly out of v1)

The following are shown in the UI as placeholders but are not wired to real data or navigation in this plan:

- **Badge detail page** -- tapping a badge chip navigates to a detail page showing grant date, description, who else earned it.
- **Full badge list page** -- "查看全部" navigates to a paginated badge list.
- **Follow/follower lists** -- tapping the 关注/粉丝 stat cells navigates to user lists.
- **Bookmarks page** -- "我的书签" navigates to a bookmark list backed by `GET /u/{username}/bookmarks.json`.
- **Settings page** -- gear icon navigates to app settings.
- **Offline caching** -- persisting profile/summary data for offline display. v1 uses bootstrap-derived data (username, user ID) as the only offline fallback; full profile requires a network fetch.

## Phased Implementation

### Phase 1: Add Rust Profile Models

**File: `rust/crates/fire-models/src/lib.rs`**
- Add `UserProfile` struct. All follow-plugin fields (`can_follow`, `is_followed`) and `trust_level` are `Option` to match Discourse's nullable behavior (confirmed by `references/fluxdo/lib/models/user.dart:220`).
- Add `UserSummaryStats` struct with: days_visited, posts_read_count, likes_received, likes_given, topic_count, post_count, time_read, bookmark_count.
- Add `ProfileSummaryTopic` (lightweight: id, title, slug, like_count, category_id, created_at) instead of reusing `TopicSummary`. The existing `TopicSummary` (line 687) is a 25-field topic-list model; the summary sideload has only 6 fields. Fluxdo confirms a distinct lightweight model (`references/fluxdo/lib/models/user.dart:448`).
- Add `ProfileSummaryReply` (id, topic_id, title, like_count, created_at, post_number).
- Add `ProfileSummaryLink` (url, title, clicks, topic_id, post_number).
- Add `ProfileSummaryTopCategory` (id, name, topic_count, post_count).
- Add `ProfileSummaryUserReference` (id, username, avatar_template, count) for most_replied_to / most_liked_by / most_liked user lists.
- Add `UserSummaryResponse` aggregating stats + all sub-lists + badges.
- Add `Badge` struct with: id, name, description, badge_type_id, image_url, icon, slug, grant_count, long_description.
- Add `UserAction` struct. `action_type` is `Option<i32>` per Fluxdo's nullable parsing.
- Add `UserActionResponse` wrapper struct.
- All structs derive `Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize`.

### Phase 2: Add API Orchestration in `fire-core`

**File: `rust/crates/fire-core/src/core/mod.rs`**
- Add `mod users;` declaration.

**File: `rust/crates/fire-core/src/core/users.rs`** (new file)
- Implement `impl FireCore` with three methods following the established pattern from `topics.rs` / `notifications.rs` / `search.rs`:

```rust
impl FireCore {
    pub async fn fetch_user_profile(
        &self,
        username: &str,
    ) -> Result<UserProfile, FireCoreError> {
        let path = format!("/u/{}.json", username);
        let traced = self.build_json_get_request(
            "fetch user profile", &path, vec![], &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(
            self, "fetch user profile", trace_id, response,
        ).await?;
        let value: Value = self.read_response_json(
            "fetch user profile", trace_id, response,
        ).await?;
        parse_user_profile_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user profile",
                source,
            }
        })
    }

    pub async fn fetch_user_summary(
        &self,
        username: &str,
    ) -> Result<UserSummaryResponse, FireCoreError> {
        let path = format!("/u/{}/summary.json", username);
        let traced = self.build_json_get_request(
            "fetch user summary", &path, vec![], &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(
            self, "fetch user summary", trace_id, response,
        ).await?;
        let value: Value = self.read_response_json(
            "fetch user summary", trace_id, response,
        ).await?;
        parse_user_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user summary",
                source,
            }
        })
    }

    pub async fn fetch_user_actions(
        &self,
        username: &str,
        offset: Option<u32>,
        filter: Option<&str>,
    ) -> Result<Vec<UserAction>, FireCoreError> {
        let mut params = vec![
            ("username", username.to_string()),
        ];
        if let Some(offset) = offset {
            params.push(("offset", offset.to_string()));
        }
        if let Some(filter) = filter {
            params.push(("filter", filter.to_string()));
        }
        let traced = self.build_json_get_request(
            "fetch user actions",
            "/user_actions.json",
            params,
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(
            self, "fetch user actions", trace_id, response,
        ).await?;
        let value: Value = self.read_response_json(
            "fetch user actions", trace_id, response,
        ).await?;
        parse_user_actions_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user actions",
                source,
            }
        })
    }
}
```

All three methods return **`fire_models`** types, not UniFFI state types.

**File: `rust/crates/fire-core/src/user_payloads.rs`** (new file)
- `parse_user_profile_value(value: Value) -> Result<UserProfile, serde_json::Error>`: Unwraps `value["user"]` envelope with fallback to bare object (matching `references/fluxdo/lib/services/discourse/_users.dart:45`), then deserializes into `UserProfile`.
- `parse_user_summary_value(value: Value) -> Result<UserSummaryResponse, serde_json::Error>`: Extracts `value["user_summary"]` for stats + inline arrays (replies, links, top_categories, most_replied_to_users, most_liked_by_users, most_liked_users), and sideloaded `value["topics"]` and `value["badges"]` from the response root.
- `parse_user_actions_value(value: Value) -> Result<Vec<UserAction>, serde_json::Error>`: Extracts `value["user_actions"]` array.

**File: `rust/crates/fire-core/src/lib.rs`**
- Add `mod user_payloads;` and re-export as needed.

### Phase 3: Add UniFFI Bridge Types and Methods

**File: `rust/crates/fire-uniffi/src/lib.rs`**
- Add `UserProfileState`, `UserSummaryState`, `UserSummaryStatsState`, `ProfileSummaryTopicState`, `ProfileSummaryReplyState`, `ProfileSummaryTopCategoryState`, `ProfileSummaryUserReferenceState`, `BadgeState`, `UserActionState` UniFFI records.
- Add `From<fire_models::UserProfile> for UserProfileState` with computed `trust_level_label` (defaulting `trust_level.unwrap_or(0)`) and `profile_background_url` preference logic.
- Add `From` impls for all other model-to-state conversions.
- Add `fetch_user_profile`, `fetch_user_summary`, `fetch_user_actions` methods on `FireCoreHandle` following the existing `run_on_ffi_runtime` + `.into()` pattern (matching line 2410+).

### Phase 4: Add iOS Session Store and ViewModel Wrapper Methods

**File: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`**
- Add three new public methods on the `FireSessionStore` actor:
  - `func fetchUserProfile(username: String) async throws -> UserProfileState`
  - `func fetchUserSummary(username: String) async throws -> UserSummaryState`
  - `func fetchUserActions(username: String, offset: UInt32?, filter: String?) async throws -> [UserActionState]`
- Each method delegates to `core.fetchUserProfile(...)` etc., matching the existing pattern for `fetchTopicList`, `fetchRecentNotifications`, etc.

**File: `native/ios-app/App/FireAppViewModel.swift`**
- Add three new **public** thin wrapper methods that resolve the private session store and delegate:

```swift
func fetchUserProfile(username: String) async throws -> UserProfileState {
    let sessionStore = try await sessionStoreValue()
    return try await sessionStore.fetchUserProfile(username: username)
}

func fetchUserSummary(username: String) async throws -> UserSummaryState {
    let sessionStore = try await sessionStoreValue()
    return try await sessionStore.fetchUserSummary(username: username)
}

func fetchUserActions(
    username: String,
    offset: UInt32?,
    filter: String?
) async throws -> [UserActionState] {
    let sessionStore = try await sessionStoreValue()
    return try await sessionStore.fetchUserActions(
        username: username,
        offset: offset,
        filter: filter
    )
}
```

These methods are intentionally thin: they don't modify any `@Published` state on `FireAppViewModel`. They exist solely to bridge the private `sessionStore` to `FireProfileViewModel`.

### Phase 5: Create Swift Profile ViewModel

**File: `native/ios-app/App/FireProfileViewModel.swift`** (new file)
- Create `@MainActor final class FireProfileViewModel: ObservableObject`.
- Holds a reference to `FireAppViewModel` (passed at init) for session state access and the profile API wrapper methods.
- Published properties: `profile: UserProfileState?`, `summary: UserSummaryState?`, `actions: [UserActionState]`, `isLoadingProfile: Bool`, `isLoadingActions: Bool`, `selectedTab: ProfileTab`, `errorMessage: String?`, `hasMoreActions: Bool`.
- Define `ProfileTab` enum: `.all` (filter "4,5"), `.topics` (filter "4"), `.replies` (filter "5"), `.liked` (filter "2"). Display names: "全部", "话题", "回复", "被赞".
- Implement `loadProfile()`: read `username` from `appViewModel.session.bootstrap.currentUsername`, fetch profile and summary concurrently using `async let` via the `appViewModel.fetchUserProfile(...)` / `appViewModel.fetchUserSummary(...)` wrappers.
- Implement `loadActions(reset:)`: fetch user actions with current tab's filter and offset via `appViewModel.fetchUserActions(...)`, append or replace results while preserving the previous successful timeline during tab switches and refresh retries.
- Implement `selectTab(_:)`: update selected tab and trigger `loadActions(reset: true)` without clearing the existing action rows first.

### Phase 6: Redesign FireProfileView

**File: `native/ios-app/App/FireProfileView.swift`** (rewrite)
- Replace the body with a `NavigationStack` containing a grouped `List`.
- **Profile Header**: plain identity block with avatar, display name, `@username`, trust-level pill, bio, social stats, and metadata entries for joined date / last active / reading time / gamification score.
- **Account shortcuts**: keep key destinations directly under the header, including bookmarks, history, drafts, badges, invite links, following, and followers.
- **Recent Activity Preview**: only the first few action rows render on the main page. A trailing `NavigationLink` opens `FireProfileActivityTimelineView` for the complete activity history.
- **Toolbar menu**: the top-right gear now opens developer tools and logout actions.
- **Error handling**: keep profile-level failures in the page banner, but localize activity failures inside the preview section and timeline. Initial activity failures use a blocking retry state; later failures keep stale rows visible and show a non-blocking banner.
- **Refresh behavior**: pull-to-refresh calls `refreshAll()` so summary and activity stay in sync.

**File: `native/ios-app/App/FireProfileTrustLevelPill.swift`** (new file)
- A small SwiftUI component: rounded capsule with trust level label and color.
- Accepts `trustLevel: UInt32`, maps to label string and `FireTheme` color per the design decision table.

**File: `native/ios-app/App/FireProfileStatsRow.swift`** (new file)
- Reusable 3-column stats display component.
- Accepts an array of `(value: String, label: String)` tuples.
- Uses `FireTheme.ink` for values, `FireTheme.subtleInk` for labels, `FireTheme.divider` between columns.

**File: `native/ios-app/App/FireProfileBadgeChip.swift`** (new file)
- Single badge chip view: icon/image + name text in a capsule shape.
- Tinted by badge tier (gold/silver/bronze).
- Sized to content with `FireTheme.smallCornerRadius` rounding.

**File: `native/ios-app/App/FireProfileActivityRow.swift`** (new file)
- Renders a single `UserActionState`: action icon, event label, title, excerpt snippet, and relative time.
- Used both in the overview-page preview and the dedicated full timeline screen.

**File: `native/ios-app/App/FireProfileActivityTimelineView.swift`** (new file)
- Hosts the full segmented activity experience.
- Owns the segmented filter UI, infinite scroll pagination, and navigation into topic detail.

### Phase 7: Extract Developer Tools View

**File: `native/ios-app/App/FireDeveloperToolsView.swift`** (new file)
- Move the current `sessionSection` content from `FireProfileView` into this view.
- Move the current "诊断工具", "刷新 Bootstrap", "恢复会话" actions here.
- Keep the `LabeledContent` readiness indicators.
- This view is pushed from the "开发者工具" row in the new profile.
- Accepts `FireAppViewModel` as the data source.

### Phase 8: Update Tab Root and Navigation

**File: `native/ios-app/App/FireTabRoot.swift`**
- In the profile tab, instantiate `FireProfileViewModel(appViewModel: viewModel)`.
- Pass both to `FireProfileView`.
- Trigger `profileViewModel.loadProfile()` when the profile tab appears (via `.task`).

### Phase 9: Verification

**Rust layer:**
- `cargo build --workspace` succeeds.
- Add unit tests in `rust/crates/fire-core/src/user_payloads.rs`:
  - `test_parse_user_profile_unwraps_user_envelope`: parse `{"user": {...}}` envelope.
  - `test_parse_user_profile_bare_fallback`: parse bare `{...}` without envelope.
  - `test_parse_user_profile_nullable_follow_fields`: `can_follow` / `is_followed` absent or null.
  - `test_parse_user_summary_sideload_structure`: `topics` and `badges` from root, stats from `user_summary`.
  - `test_parse_user_actions_array`: parse `{"user_actions": [...]}`.
- Run `cargo test --workspace`.

**iOS layer:**
- Build the iOS app target; confirm zero compiler errors.
- Run existing unit tests (`FireTopicPresentationTests`, `FireSessionSecurityTests`).
- Add `FireProfileViewModelTests`:
  - `test_load_profile_sets_profile_and_summary`: mock `FireAppViewModel`, verify published state updates.
  - `test_select_tab_reloads_actions_with_correct_filter`: verify filter string for each tab.
  - `test_load_actions_appends_on_pagination`: verify offset increments and array append.
- Verify the developer tools sub-page retains all current diagnostic capabilities.
- Verify logout flow still works from the new location.
- Confirm dark mode appearance uses correct `FireTheme` tokens.
- Test scroll performance with many badges and activity items.

## Architectural Notes

- **No semver impact**: This is an app-internal change. The UniFFI boundary adds new types but doesn't modify existing ones.
- **`FireAppViewModel` receives three new thin wrapper methods** (`fetchUserProfile`, `fetchUserSummary`, `fetchUserActions`) that bridge its private `sessionStore` to the profile ViewModel. All existing published state and lifecycle remain unchanged.
- **`FireSessionStore` receives three new public methods** matching the `FireCoreHandle` methods. This follows the established pattern for topics, notifications, and search.
- **`session_store.rs` is NOT changed**. It remains a persistence helper (snapshot sanitization, atomic write, legacy migration). API orchestration goes in `core/users.rs`.
- **`FireDiagnosticsView` is NOT changed**. It continues to work the same way, just accessed from the developer tools page instead of directly from the profile.
- **`FireAvatarView` is NOT changed**. It already supports `avatarTemplate` with `{size}` placeholder resolution, relative URL handling, and protocol-relative URL handling (confirmed at `native/ios-app/App/FireComponents.swift:619`). The profile page just passes a non-nil `avatarTemplate` from the API response.
- **Network calls use the existing openwire infrastructure** via `FireCore`'s `build_json_get_request` / `execute_request` spine. No new HTTP client is introduced.
- **Response envelope parsing**: `/u/{username}.json` wraps the user object in `{"user": ...}` (documented at `docs/backend-api/05-users-search-and-notifications.md:33`, confirmed by `references/fluxdo/lib/services/discourse/_users.dart:45`). The parser unwraps this with a fallback to bare object. `/summary.json` nests stats under `user_summary` but sideloads `topics` and `badges` at the response root.
- **Activity filtering uses Discourse `user_actions` action type constants**: `1` = I liked, `2` = someone liked my content (was_liked), `4` = new topic, `5` = reply. The "被赞" tab uses filter `2` (was_liked), not `1` (my likes). Source: `references/fluxdo/lib/models/user_action.dart`, `references/fluxdo/lib/pages/user_profile_page.dart:74`.
- **Badge images**: Discourse badges may have an `image_url` (absolute) or an `icon` (Font Awesome class name like `fa-certificate`). The Swift badge chip component should handle both, falling back to a generic badge SF Symbol when neither is available.
- **No Android changes** are included in this plan. The Rust model additions benefit both platforms, but the UI work is iOS-only.

## File Change Summary

- `rust/crates/fire-models/src/lib.rs` -- Add `UserProfile`, `UserSummaryStats`, `ProfileSummaryTopic`, `ProfileSummaryReply`, `ProfileSummaryLink`, `ProfileSummaryTopCategory`, `ProfileSummaryUserReference`, `UserSummaryResponse`, `Badge`, `UserAction`, `UserActionResponse` structs
- `rust/crates/fire-core/src/core/mod.rs` -- Add `mod users;` declaration
- `rust/crates/fire-core/src/core/users.rs` -- New file: `impl FireCore` with `fetch_user_profile`, `fetch_user_summary`, `fetch_user_actions` returning `fire_models` types
- `rust/crates/fire-core/src/user_payloads.rs` -- New file: envelope parsers `parse_user_profile_value`, `parse_user_summary_value`, `parse_user_actions_value` with unit tests
- `rust/crates/fire-core/src/lib.rs` -- Add `mod user_payloads;`
- `rust/crates/fire-uniffi/src/lib.rs` -- Add `UserProfileState`, `UserSummaryState`, `UserSummaryStatsState`, `ProfileSummaryTopicState`, `ProfileSummaryReplyState`, `ProfileSummaryTopCategoryState`, `ProfileSummaryUserReferenceState`, `BadgeState`, `UserActionState` records, `From` impls, and `FireCoreHandle` methods
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- Add `fetchUserProfile`, `fetchUserSummary`, `fetchUserActions` public methods
- `native/ios-app/App/FireAppViewModel.swift` -- Add three thin public wrapper methods for profile API calls (no changes to existing published state or lifecycle)
- `native/ios-app/App/FireProfileView.swift` -- Full rewrite: grouped overview page with header, account shortcut rows, and recent activity preview
- `native/ios-app/App/FireProfileViewModel.swift` -- New file: dedicated profile ViewModel with profile/summary/actions state management, holds `FireAppViewModel` reference
- `native/ios-app/App/FireProfileTrustLevelPill.swift` -- New file: trust level capsule badge component
- `native/ios-app/App/FireProfileStatsRow.swift` -- New file: 3-column stats display component
- `native/ios-app/App/FireProfileBadgeChip.swift` -- New file: single badge chip component with tier tinting
- `native/ios-app/App/FireProfileActivityRow.swift` -- New file: user action list row component
- `native/ios-app/App/FireProfileActivityTimelineView.swift` -- New file: dedicated full activity timeline screen
- `native/ios-app/App/FireDeveloperToolsView.swift` -- New file: extracted session info and diagnostic actions from old profile view
- `native/ios-app/App/FireTabRoot.swift` -- Instantiate `FireProfileViewModel`, pass to `FireProfileView`, trigger load on appear
- `rust/crates/fire-core/src/session_store.rs` -- Unchanged (persistence helper only; API orchestration goes in `core/users.rs`)
- `native/ios-app/App/SessionState+Helpers.swift` -- Unchanged (helpers still used by developer tools view)
- `native/ios-app/App/FireDiagnosticsView.swift` -- Unchanged (accessed from developer tools instead of directly from profile)
- `native/ios-app/App/FireComponents.swift` -- Unchanged (`FireAvatarView` already supports `avatarTemplate` resolution)
- `native/ios-app/App/FireTheme.swift` -- Unchanged (existing tokens are sufficient; verified against the design)
