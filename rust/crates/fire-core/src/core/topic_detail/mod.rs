use std::{
    collections::{HashMap, HashSet},
    ops::Range,
    sync::Arc,
    time::Duration,
};

use fire_models::{
    PostActionType, TopicAiSummary, TopicDetailLoadError, TopicDetailPhase, TopicDetailUiSnapshot,
    TopicHeader, TopicPost, TopicPresenceUser,
};
use tokio::sync::oneshot;

use crate::error::FireCoreError;

pub const TOPIC_DETAIL_INITIAL_BATCH: u16 = 40;
pub const TOPIC_DETAIL_LOAD_MORE_BATCH: u16 = 40;
pub const TOPIC_DETAIL_MAX_AUTO_BATCHES: u8 = 3;
pub const TOPIC_DETAIL_MAX_AUTO_POSTS: u16 = 120;
pub const TOPIC_DETAIL_PREFETCH_THRESHOLD: u32 = 10;
pub const TOPIC_DETAIL_FORWARD_EXPANSION: u32 = 60;
pub const TOPIC_DETAIL_HYDRATION_PAGE: usize = 30;
pub const TOPIC_DETAIL_HYDRATION_ITERS: u8 = 8;
pub const TOPIC_DETAIL_VISIBLE_DEBOUNCE: Duration = Duration::from_millis(120);
pub const TOPIC_DETAIL_LIST_TAIL_THRESHOLD: u32 = 5;
pub const TOPIC_DETAIL_REPLY_CONTEXT_BATCH: usize = 20;
pub const TOPIC_DETAIL_REFRESH_DEBOUNCE: Duration = Duration::from_millis(1500);
pub const TOPIC_DETAIL_PRESENCE_HEARTBEAT: Duration = Duration::from_secs(30);
pub const TOPIC_DETAIL_REQUEST_TIMEOUT: Duration = Duration::from_secs(30);
const TOPIC_DETAIL_MAX_WINDOW: usize = 200;
const HEART_REACTION_ID: &str = "heart";

pub struct TopicDetailOpenRequest {
    pub topic_id: u64,
    pub owner_token: String,
    pub slug_hint: Option<String>,
    pub target_post_number: Option<u32>,
    pub bypass_cache: bool,
    pub force_load: bool,
    pub track_visit: bool,
    pub allow_suggested_unread_root: bool,
}

pub trait TopicDetailObserver: Send + Sync {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshot);
}

enum DeferredRefresh {
    None,
    Pending,
    Ready(Box<TopicDetailUiSnapshot>),
}

struct TopicWindow {
    requested: Range<usize>,
    anchor: Option<u32>,
}

struct ActorState {
    topic_id: u64,
    owners: HashMap<String, Arc<dyn TopicDetailObserver>>,
    slug_hint: Option<String>,
    generation: u64,
    collection_revision: u64,
    chrome_revision: u64,
    sidecar_revision: u64,
    interaction_revision: u64,
    phase: TopicDetailPhase,
    load_error: Option<TopicDetailLoadError>,
    notice: Option<fire_models::TopicDetailNotice>,
    scroll_target: Option<u32>,
    scroll_exhausted: bool,
    window: TopicWindow,
    scroll_active: bool,
    deferred: DeferredRefresh,
    defer_publish: bool,
    refresh_inflight: bool,
    loading_more: bool,
    load_more_error: Option<String>,
    summary: Option<TopicAiSummary>,
    summary_loading: bool,
    summary_error: Option<String>,
    typing_users: Vec<TopicPresenceUser>,
    submitting: bool,
    mutating: HashSet<u64>,
    loading_reply_context: HashSet<u64>,
    reply_context: Option<fire_models::TopicDetailReplyContext>,
    flag_types: Vec<PostActionType>,
    rollback: HashMap<u64, TopicPost>,
    inflight_posts: HashMap<u64, TopicPost>,
    http_epoch: u64,
    visible_generation: u64,
    refresh_generation: u64,
    pending_visible: Vec<u32>,
    track_visit: bool,
    published: Option<TopicDetailUiSnapshot>,
    header: Option<TopicHeader>,
    bus_listener_id: Option<u64>,
    bus_subscribed: bool,
    typing: bool,
    alive: bool,
}

enum Command {
    SyncOwners {
        owners: HashMap<String, Arc<dyn TopicDetailObserver>>,
        open: Option<TopicDetailOpenRequest>,
    },
    Shutdown,
    CancelHttp,
    Reload {
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
    },
    LoadMore,
    NoteVisible(Vec<u32>),
    VisibleFired(u64),
    NoteTail {
        item_count: u32,
        visible_max_item: Option<u32>,
    },
    NoteScroll(bool),
    AckScroll(u32),
    ClearScroll,
    BeginTyping,
    EndTyping,
    PresenceHeartbeat,
    BusRefresh,
    RefreshFired(u64),
    BusStarted,
    RefreshPresence,
    ReloadAi {
        skip_age_check: bool,
    },
    LoadReplyContext(u64),
    PrepareEdit {
        post_id: u64,
        reply: oneshot::Sender<Result<String, FireCoreError>>,
    },
    EnsureFlags {
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    SubmitReply {
        raw: String,
        reply_to_post_number: Option<u32>,
        scroll_to_created: bool,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    CreateBoost {
        post_id: u64,
        raw: String,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    DeleteBoost {
        post_id: u64,
        boost_id: u64,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    UpdatePost {
        post_id: u64,
        raw: String,
        edit_reason: Option<String>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    DeletePost {
        post_id: u64,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    RecoverPost {
        post_id: u64,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    FlagPost {
        post_id: u64,
        flag_type_id: u32,
        message: Option<String>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    SetLiked {
        post_id: u64,
        liked: bool,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    ToggleReaction {
        post_id: u64,
        reaction_id: String,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    VotePoll {
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    UnvotePoll {
        post_id: u64,
        poll_name: String,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    VoteTopic {
        voted: bool,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    AcceptSolution {
        post_id: u64,
        accepted: bool,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    CreateBookmark {
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    UpdateBookmark {
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    DeleteBookmark {
        bookmark_id: u64,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    SetNotificationLevel {
        level: i32,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    UpdateTopic {
        title: String,
        category_id: u64,
        tags: Vec<String>,
        reply: oneshot::Sender<Result<(), FireCoreError>>,
    },
    ReportTimings {
        topic_time_ms: u32,
        timings: Vec<fire_models::TopicTimingEntry>,
        reply: oneshot::Sender<Result<bool, FireCoreError>>,
    },
    LoginReload {
        track_visit: bool,
    },
    Flush(oneshot::Sender<()>),
}

mod actor;
mod bus;
mod load;
mod mutations;
mod publish;
mod reactions;
mod registry;
mod session;
mod summary;
mod window;

pub use registry::TopicDetailSessionRegistry;
pub use session::TopicDetailSession;

#[cfg(test)]
mod tests;
