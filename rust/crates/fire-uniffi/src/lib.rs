use std::{
    any::Any,
    backtrace::Backtrace,
    future::Future,
    panic::{self, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, OnceLock,
    },
};

use fire_core::{
    FireCore, FireCoreConfig, FireCoreError, FireLogFileDetail, FireLogFileSummary,
    NetworkTraceDetail, NetworkTraceEvent, NetworkTraceHeader, NetworkTraceOutcome,
    NetworkTraceSummary,
};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginPhase, LoginSyncInput, PlatformCookie,
    PostReactionUpdate, SessionReadiness, SessionSnapshot, TopicCategory, TopicDetail,
    TopicDetailCreatedBy, TopicDetailMeta, TopicDetailQuery, TopicListKind, TopicListQuery,
    TopicListResponse, TopicPost, TopicPostStream, TopicPoster, TopicReaction, TopicReplyRequest,
    TopicRow, TopicSummary, TopicTag, TopicThread, TopicThreadReply, TopicThreadSection, TopicUser,
};
use futures_util::FutureExt;
use tokio::runtime::{Builder, Runtime};
use tracing::error;

uniffi::setup_scaffolding!("fire_uniffi");

#[derive(Default)]
struct PanicState {
    poisoned: AtomicBool,
    last_panic: Mutex<Option<String>>,
}

impl PanicState {
    fn ensure_healthy(&self, operation: &'static str) -> Result<(), FireUniFfiError> {
        if !self.poisoned.load(Ordering::SeqCst) {
            return Ok(());
        }

        let previous = self
            .last_panic
            .lock()
            .ok()
            .and_then(|guard| guard.clone())
            .unwrap_or_else(|| "unknown panic".to_string());
        Err(FireUniFfiError::Internal {
            details: format!(
                "fire core handle is poisoned by a previous panic ({previous}); recreate the handle before calling {operation}"
            ),
        })
    }

    fn capture_panic(
        &self,
        operation: &'static str,
        payload: &(dyn Any + Send),
    ) -> FireUniFfiError {
        let report = CapturedPanic::from_payload(operation, payload);
        report.log();
        self.poisoned.store(true, Ordering::SeqCst);
        if let Ok(mut last_panic) = self.last_panic.lock() {
            *last_panic = Some(report.summary());
        }
        FireUniFfiError::Internal {
            details: report.user_message(),
        }
    }
}

struct CapturedPanic {
    operation: &'static str,
    message: String,
    backtrace: String,
}

impl CapturedPanic {
    fn from_payload(operation: &'static str, payload: &(dyn Any + Send)) -> Self {
        Self {
            operation,
            message: panic_payload_to_string(payload),
            backtrace: Backtrace::force_capture().to_string(),
        }
    }

    fn summary(&self) -> String {
        format!("{} panicked: {}", self.operation, self.message)
    }

    fn user_message(&self) -> String {
        self.summary()
    }

    fn log(&self) {
        error!(
            operation = self.operation,
            panic_message = %self.message,
            backtrace = %self.backtrace,
            "caught panic across fire-uniffi boundary"
        );
        eprintln!(
            "fire-uniffi caught panic in {}: {}\nbacktrace:\n{}",
            self.operation, self.message, self.backtrace
        );
    }
}

fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "non-string panic payload".to_string()
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PlatformCookieState {
    pub name: String,
    pub value: String,
    pub domain: Option<String>,
    pub path: Option<String>,
}

impl From<PlatformCookie> for PlatformCookieState {
    fn from(value: PlatformCookie) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
        }
    }
}

impl From<PlatformCookieState> for PlatformCookie {
    fn from(value: PlatformCookieState) -> Self {
        Self {
            name: value.name,
            value: value.value,
            domain: value.domain,
            path: value.path,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookieState {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
}

impl From<CookieSnapshot> for CookieState {
    fn from(value: CookieSnapshot) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
        }
    }
}

impl From<CookieState> for CookieSnapshot {
    fn from(value: CookieState) -> Self {
        Self {
            t_token: value.t_token,
            forum_session: value.forum_session,
            cf_clearance: value.cf_clearance,
            csrf_token: value.csrf_token,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicCategoryState {
    pub id: u64,
    pub name: String,
    pub slug: String,
    pub parent_category_id: Option<u64>,
    pub color_hex: Option<String>,
    pub text_color_hex: Option<String>,
}

impl From<TopicCategory> for TopicCategoryState {
    fn from(value: TopicCategory) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
        }
    }
}

impl From<TopicCategoryState> for TopicCategory {
    fn from(value: TopicCategoryState) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BootstrapState {
    pub base_url: String,
    pub discourse_base_uri: Option<String>,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub long_polling_base_url: Option<String>,
    pub turnstile_sitekey: Option<String>,
    pub topic_tracking_state_meta: Option<String>,
    pub preloaded_json: Option<String>,
    pub has_preloaded_data: bool,
    pub categories: Vec<TopicCategoryState>,
    pub enabled_reaction_ids: Vec<String>,
    pub min_post_length: u32,
}

impl From<BootstrapArtifacts> for BootstrapState {
    fn from(value: BootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            categories: value.categories.into_iter().map(Into::into).collect(),
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
        }
    }
}

impl From<BootstrapState> for BootstrapArtifacts {
    fn from(value: BootstrapState) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            categories: value.categories.into_iter().map(Into::into).collect(),
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LoginSyncState {
    pub current_url: Option<String>,
    pub username: Option<String>,
    pub csrf_token: Option<String>,
    pub home_html: Option<String>,
    pub cookies: Vec<PlatformCookieState>,
}

impl From<LoginSyncInput> for LoginSyncState {
    fn from(value: LoginSyncInput) -> Self {
        Self {
            current_url: value.current_url,
            username: value.username,
            csrf_token: value.csrf_token,
            home_html: value.home_html,
            cookies: value.cookies.into_iter().map(Into::into).collect(),
        }
    }
}

impl From<LoginSyncState> for LoginSyncInput {
    fn from(value: LoginSyncState) -> Self {
        Self {
            current_url: value.current_url,
            username: value.username,
            csrf_token: value.csrf_token,
            home_html: value.home_html,
            cookies: value.cookies.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum LoginPhaseState {
    Anonymous,
    CookiesCaptured,
    BootstrapCaptured,
    Ready,
}

impl From<LoginPhase> for LoginPhaseState {
    fn from(value: LoginPhase) -> Self {
        match value {
            LoginPhase::Anonymous => Self::Anonymous,
            LoginPhase::CookiesCaptured => Self::CookiesCaptured,
            LoginPhase::BootstrapCaptured => Self::BootstrapCaptured,
            LoginPhase::Ready => Self::Ready,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionReadinessState {
    pub has_login_cookie: bool,
    pub has_forum_session: bool,
    pub has_cloudflare_clearance: bool,
    pub has_csrf_token: bool,
    pub has_current_user: bool,
    pub has_preloaded_data: bool,
    pub has_shared_session_key: bool,
    pub can_read_authenticated_api: bool,
    pub can_write_authenticated_api: bool,
    pub can_open_message_bus: bool,
}

impl From<SessionReadiness> for SessionReadinessState {
    fn from(value: SessionReadiness) -> Self {
        Self {
            has_login_cookie: value.has_login_cookie,
            has_forum_session: value.has_forum_session,
            has_cloudflare_clearance: value.has_cloudflare_clearance,
            has_csrf_token: value.has_csrf_token,
            has_current_user: value.has_current_user,
            has_preloaded_data: value.has_preloaded_data,
            has_shared_session_key: value.has_shared_session_key,
            can_read_authenticated_api: value.can_read_authenticated_api,
            can_write_authenticated_api: value.can_write_authenticated_api,
            can_open_message_bus: value.can_open_message_bus,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SessionState {
    pub cookies: CookieState,
    pub bootstrap: BootstrapState,
    pub readiness: SessionReadinessState,
    pub login_phase: LoginPhaseState,
    pub has_login_session: bool,
    pub profile_display_name: String,
    pub login_phase_label: String,
}

impl SessionState {
    fn from_snapshot(snapshot: SessionSnapshot) -> Self {
        let readiness = snapshot.readiness();
        let login_phase = snapshot.login_phase();
        Self {
            has_login_session: snapshot.cookies.has_login_session(),
            profile_display_name: snapshot.profile_display_name(),
            login_phase_label: snapshot.login_phase_label(),
            cookies: snapshot.cookies.into(),
            bootstrap: snapshot.bootstrap.into(),
            readiness: readiness.into(),
            login_phase: login_phase.into(),
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum TopicListKindState {
    Latest,
    New,
    Unread,
    Unseen,
    Hot,
    Top,
}

impl From<TopicListKind> for TopicListKindState {
    fn from(value: TopicListKind) -> Self {
        match value {
            TopicListKind::Latest => Self::Latest,
            TopicListKind::New => Self::New,
            TopicListKind::Unread => Self::Unread,
            TopicListKind::Unseen => Self::Unseen,
            TopicListKind::Hot => Self::Hot,
            TopicListKind::Top => Self::Top,
        }
    }
}

impl From<TopicListKindState> for TopicListKind {
    fn from(value: TopicListKindState) -> Self {
        match value {
            TopicListKindState::Latest => Self::Latest,
            TopicListKindState::New => Self::New,
            TopicListKindState::Unread => Self::Unread,
            TopicListKindState::Unseen => Self::Unseen,
            TopicListKindState::Hot => Self::Hot,
            TopicListKindState::Top => Self::Top,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListQueryState {
    pub kind: TopicListKindState,
    pub page: Option<u32>,
    pub topic_ids: Vec<u64>,
    pub order: Option<String>,
    pub ascending: Option<bool>,
}

impl From<TopicListQuery> for TopicListQueryState {
    fn from(value: TopicListQuery) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
        }
    }
}

impl From<TopicListQueryState> for TopicListQuery {
    fn from(value: TopicListQueryState) -> Self {
        Self {
            kind: value.kind.into(),
            page: value.page,
            topic_ids: value.topic_ids,
            order: value.order,
            ascending: value.ascending,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicUserState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicUser> for TopicUserState {
    fn from(value: TopicUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPosterState {
    pub user_id: u64,
    pub description: Option<String>,
    pub extras: Option<String>,
}

impl From<TopicPoster> for TopicPosterState {
    fn from(value: TopicPoster) -> Self {
        Self {
            user_id: value.user_id,
            description: value.description,
            extras: value.extras,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTagState {
    pub id: Option<u64>,
    pub name: String,
    pub slug: Option<String>,
}

impl From<TopicTag> for TopicTagState {
    fn from(value: TopicTag) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicSummaryState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub reply_count: u32,
    pub views: u32,
    pub like_count: u32,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
    pub last_posted_at: Option<String>,
    pub last_poster_username: Option<String>,
    pub category_id: Option<u64>,
    pub pinned: bool,
    pub visible: bool,
    pub closed: bool,
    pub archived: bool,
    pub tags: Vec<TopicTagState>,
    pub posters: Vec<TopicPosterState>,
    pub unseen: bool,
    pub unread_posts: u32,
    pub new_posts: u32,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub has_accepted_answer: bool,
    pub can_have_answer: bool,
}

impl From<TopicSummary> for TopicSummaryState {
    fn from(value: TopicSummary) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            reply_count: value.reply_count,
            views: value.views,
            like_count: value.like_count,
            excerpt: value.excerpt,
            created_at: value.created_at,
            last_posted_at: value.last_posted_at,
            last_poster_username: value.last_poster_username,
            category_id: value.category_id,
            pinned: value.pinned,
            visible: value.visible,
            closed: value.closed,
            archived: value.archived,
            tags: value.tags.into_iter().map(Into::into).collect(),
            posters: value.posters.into_iter().map(Into::into).collect(),
            unseen: value.unseen,
            unread_posts: value.unread_posts,
            new_posts: value.new_posts,
            last_read_post_number: value.last_read_post_number,
            highest_post_number: value.highest_post_number,
            has_accepted_answer: value.has_accepted_answer,
            can_have_answer: value.can_have_answer,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicRowState {
    pub topic: TopicSummaryState,
    pub excerpt_text: Option<String>,
    pub original_poster_username: Option<String>,
    pub original_poster_avatar_template: Option<String>,
    pub tag_names: Vec<String>,
    pub created_timestamp_unix_ms: Option<u64>,
    pub activity_timestamp_unix_ms: Option<u64>,
    pub last_poster_username: Option<String>,
}

impl From<TopicRow> for TopicRowState {
    fn from(value: TopicRow) -> Self {
        Self {
            topic: value.topic.into(),
            excerpt_text: value.excerpt_text,
            original_poster_username: value.original_poster_username,
            original_poster_avatar_template: value.original_poster_avatar_template,
            tag_names: value.tag_names,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            activity_timestamp_unix_ms: value.activity_timestamp_unix_ms,
            last_poster_username: value.last_poster_username,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicListState {
    pub topics: Vec<TopicSummaryState>,
    pub users: Vec<TopicUserState>,
    pub rows: Vec<TopicRowState>,
    pub more_topics_url: Option<String>,
    pub next_page: Option<u32>,
}

impl From<TopicListResponse> for TopicListState {
    fn from(value: TopicListResponse) -> Self {
        Self {
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            rows: value.rows.into_iter().map(Into::into).collect(),
            more_topics_url: value.more_topics_url,
            next_page: value.next_page,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailQueryState {
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub track_visit: bool,
    pub filter: Option<String>,
    pub username_filters: Option<String>,
    pub filter_top_level_replies: bool,
}

impl From<TopicDetailQuery> for TopicDetailQueryState {
    fn from(value: TopicDetailQuery) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

impl From<TopicDetailQueryState> for TopicDetailQuery {
    fn from(value: TopicDetailQueryState) -> Self {
        Self {
            topic_id: value.topic_id,
            post_number: value.post_number,
            track_visit: value.track_visit,
            filter: value.filter,
            username_filters: value.username_filters,
            filter_top_level_replies: value.filter_top_level_replies,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReactionState {
    pub id: String,
    pub kind: Option<String>,
    pub count: u32,
    pub can_undo: Option<bool>,
}

impl From<TopicReaction> for TopicReactionState {
    fn from(value: TopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
            can_undo: value.can_undo,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicReplyRequestState {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
}

impl From<TopicReplyRequestState> for TopicReplyRequest {
    fn from(value: TopicReplyRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            raw: value.raw,
            reply_to_post_number: value.reply_to_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct PostReactionUpdateState {
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
}

impl From<PostReactionUpdate> for PostReactionUpdateState {
    fn from(value: PostReactionUpdate) -> Self {
        Self {
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub cooked: String,
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub reactions: Vec<TopicReactionState>,
    pub current_user_reaction: Option<TopicReactionState>,
    pub accepted_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

impl From<TopicPost> for TopicPostState {
    fn from(value: TopicPost) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            cooked: value.cooked,
            post_number: value.post_number,
            post_type: value.post_type,
            created_at: value.created_at,
            updated_at: value.updated_at,
            like_count: value.like_count,
            reply_count: value.reply_count,
            reply_to_post_number: value.reply_to_post_number,
            bookmarked: value.bookmarked,
            bookmark_id: value.bookmark_id,
            reactions: value.reactions.into_iter().map(Into::into).collect(),
            current_user_reaction: value.current_user_reaction.map(Into::into),
            accepted_answer: value.accepted_answer,
            can_edit: value.can_edit,
            can_delete: value.can_delete,
            can_recover: value.can_recover,
            hidden: value.hidden,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicPostStreamState {
    pub posts: Vec<TopicPostState>,
    pub stream: Vec<u64>,
}

impl From<TopicPostStream> for TopicPostStreamState {
    fn from(value: TopicPostStream) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            stream: value.stream,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadReplyState {
    pub post_number: u32,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
}

impl From<TopicThreadReply> for TopicThreadReplyState {
    fn from(value: TopicThreadReply) -> Self {
        Self {
            post_number: value.post_number,
            depth: value.depth,
            parent_post_number: value.parent_post_number,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadSectionState {
    pub anchor_post_number: u32,
    pub replies: Vec<TopicThreadReplyState>,
}

impl From<TopicThreadSection> for TopicThreadSectionState {
    fn from(value: TopicThreadSection) -> Self {
        Self {
            anchor_post_number: value.anchor_post_number,
            replies: value.replies.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicThreadState {
    pub original_post_number: Option<u32>,
    pub reply_sections: Vec<TopicThreadSectionState>,
}

impl From<TopicThread> for TopicThreadState {
    fn from(value: TopicThread) -> Self {
        Self {
            original_post_number: value.original_post_number,
            reply_sections: value.reply_sections.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailCreatedByState {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

impl From<TopicDetailCreatedBy> for TopicDetailCreatedByState {
    fn from(value: TopicDetailCreatedBy) -> Self {
        Self {
            id: value.id,
            username: value.username,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailMetaState {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedByState>,
}

impl From<TopicDetailMeta> for TopicDetailMetaState {
    fn from(value: TopicDetailMeta) -> Self {
        Self {
            notification_level: value.notification_level,
            can_edit: value.can_edit,
            created_by: value.created_by.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicDetailState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTagState>,
    pub views: u32,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub post_stream: TopicPostStreamState,
    pub thread: TopicThreadState,
    pub details: TopicDetailMetaState,
}

impl From<TopicDetail> for TopicDetailState {
    fn from(value: TopicDetail) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            posts_count: value.posts_count,
            category_id: value.category_id,
            tags: value.tags.into_iter().map(Into::into).collect(),
            views: value.views,
            like_count: value.like_count,
            created_at: value.created_at,
            last_read_post_number: value.last_read_post_number,
            bookmarks: value.bookmarks,
            accepted_answer: value.accepted_answer,
            has_accepted_answer: value.has_accepted_answer,
            can_vote: value.can_vote,
            vote_count: value.vote_count,
            user_voted: value.user_voted,
            summarizable: value.summarizable,
            has_cached_summary: value.has_cached_summary,
            has_summary: value.has_summary,
            archetype: value.archetype,
            post_stream: value.post_stream.into(),
            thread: value.thread.into(),
            details: value.details.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileSummaryState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
}

impl From<FireLogFileSummary> for LogFileSummaryState {
    fn from(value: FireLogFileSummary) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LogFileDetailState {
    pub relative_path: String,
    pub file_name: String,
    pub size_bytes: u64,
    pub modified_at_unix_ms: u64,
    pub contents: String,
    pub is_truncated: bool,
}

impl From<FireLogFileDetail> for LogFileDetailState {
    fn from(value: FireLogFileDetail) -> Self {
        Self {
            relative_path: value.relative_path,
            file_name: value.file_name,
            size_bytes: value.size_bytes,
            modified_at_unix_ms: value.modified_at_unix_ms,
            contents: value.contents,
            is_truncated: value.is_truncated,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum NetworkTraceOutcomeState {
    InProgress,
    Succeeded,
    Failed,
}

impl From<NetworkTraceOutcome> for NetworkTraceOutcomeState {
    fn from(value: NetworkTraceOutcome) -> Self {
        match value {
            NetworkTraceOutcome::InProgress => Self::InProgress,
            NetworkTraceOutcome::Succeeded => Self::Succeeded,
            NetworkTraceOutcome::Failed => Self::Failed,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceHeaderState {
    pub name: String,
    pub value: String,
}

impl From<NetworkTraceHeader> for NetworkTraceHeaderState {
    fn from(value: NetworkTraceHeader) -> Self {
        Self {
            name: value.name,
            value: value.value,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceEventState {
    pub sequence: u32,
    pub timestamp_unix_ms: u64,
    pub phase: String,
    pub summary: String,
    pub details: Option<String>,
}

impl From<NetworkTraceEvent> for NetworkTraceEventState {
    fn from(value: NetworkTraceEvent) -> Self {
        Self {
            sequence: value.sequence,
            timestamp_unix_ms: value.timestamp_unix_ms,
            phase: value.phase,
            summary: value.summary,
            details: value.details,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceSummaryState {
    pub id: u64,
    pub call_id: Option<u64>,
    pub operation: String,
    pub method: String,
    pub url: String,
    pub started_at_unix_ms: u64,
    pub finished_at_unix_ms: Option<u64>,
    pub duration_ms: Option<u64>,
    pub outcome: NetworkTraceOutcomeState,
    pub status_code: Option<u16>,
    pub error_message: Option<String>,
    pub response_content_type: Option<String>,
    pub response_body_truncated: bool,
}

impl From<NetworkTraceSummary> for NetworkTraceSummaryState {
    fn from(value: NetworkTraceSummary) -> Self {
        Self {
            id: value.id,
            call_id: value.call_id,
            operation: value.operation,
            method: value.method,
            url: value.url,
            started_at_unix_ms: value.started_at_unix_ms,
            finished_at_unix_ms: value.finished_at_unix_ms,
            duration_ms: value.duration_ms,
            outcome: value.outcome.into(),
            status_code: value.status_code,
            error_message: value.error_message,
            response_content_type: value.response_content_type,
            response_body_truncated: value.response_body_truncated,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct NetworkTraceDetailState {
    pub summary: NetworkTraceSummaryState,
    pub request_headers: Vec<NetworkTraceHeaderState>,
    pub response_headers: Vec<NetworkTraceHeaderState>,
    pub response_body: Option<String>,
    pub response_body_truncated: bool,
    pub response_body_bytes: Option<u64>,
    pub events: Vec<NetworkTraceEventState>,
}

impl From<NetworkTraceDetail> for NetworkTraceDetailState {
    fn from(value: NetworkTraceDetail) -> Self {
        Self {
            summary: NetworkTraceSummaryState {
                id: value.id,
                call_id: value.call_id,
                operation: value.operation,
                method: value.method,
                url: value.url,
                started_at_unix_ms: value.started_at_unix_ms,
                finished_at_unix_ms: value.finished_at_unix_ms,
                duration_ms: value.duration_ms,
                outcome: value.outcome.into(),
                status_code: value.status_code,
                error_message: value.error_message,
                response_content_type: value.response_content_type,
                response_body_truncated: value.response_body_truncated,
            },
            request_headers: value.request_headers.into_iter().map(Into::into).collect(),
            response_headers: value.response_headers.into_iter().map(Into::into).collect(),
            response_body: value.response_body,
            response_body_truncated: value.response_body_truncated,
            response_body_bytes: value.response_body_bytes,
            events: value.events.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Error, thiserror::Error, Debug)]
pub enum FireUniFfiError {
    #[error("configuration error: {details}")]
    Configuration { details: String },
    #[error("validation error: {details}")]
    Validation { details: String },
    #[error("authentication error: {details}")]
    Authentication { details: String },
    #[error("network error: {details}")]
    Network { details: String },
    #[error("request requires Cloudflare challenge verification")]
    CloudflareChallenge,
    #[error("{operation} failed with HTTP {status}: {body}")]
    HttpStatus {
        operation: String,
        status: u16,
        body: String,
    },
    #[error("storage error: {details}")]
    Storage { details: String },
    #[error("serialization error: {details}")]
    Serialization { details: String },
    #[error("runtime error: {details}")]
    Runtime { details: String },
    #[error("internal error: {details}")]
    Internal { details: String },
}

impl From<FireCoreError> for FireUniFfiError {
    fn from(value: FireCoreError) -> Self {
        match value {
            FireCoreError::InvalidUrl(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::RequestBuild(source) => Self::Internal {
                details: source.to_string(),
            },
            FireCoreError::ClientBuild { source } | FireCoreError::Network { source } => {
                Self::Network {
                    details: source.to_string(),
                }
            }
            FireCoreError::Logger(source) => Self::Configuration {
                details: source.to_string(),
            },
            FireCoreError::CloudflareChallenge { .. } => Self::CloudflareChallenge,
            FireCoreError::HttpStatus {
                operation,
                status,
                body,
            } => Self::HttpStatus {
                operation: operation.to_string(),
                status,
                body,
            },
            FireCoreError::ResponseDeserialize { source, .. } => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::MissingCurrentUsername => Self::Authentication {
                details: "logout requires a current username".to_string(),
            },
            FireCoreError::MissingLoginSession => Self::Authentication {
                details: "request requires a login session".to_string(),
            },
            FireCoreError::MissingCsrfToken => Self::Authentication {
                details: "request requires a csrf token".to_string(),
            },
            FireCoreError::PostEnqueued { pending_count } => Self::Validation {
                details: format!("post is pending review (pending_count={pending_count})"),
            },
            FireCoreError::MissingWorkspacePath => Self::Configuration {
                details: "fire workspace path is not configured".to_string(),
            },
            FireCoreError::InvalidWorkspaceRelativePath { path } => Self::Validation {
                details: format!(
                    "workspace relative path must stay under the configured root: {}",
                    path.display()
                ),
            },
            FireCoreError::WorkspaceIo { path, source }
            | FireCoreError::PersistIo { path, source }
            | FireCoreError::DiagnosticsIo { path, source } => Self::Storage {
                details: format!("{}: {}", path.display(), source),
            },
            FireCoreError::LoggerWorkspaceMismatch { expected, found } => Self::Configuration {
                details: format!(
                    "logger workspace mismatch: expected {}, found {}",
                    expected.display(),
                    found.display()
                ),
            },
            FireCoreError::InvalidCsrfResponse => Self::Validation {
                details: "csrf response did not contain a usable token".to_string(),
            },
            FireCoreError::PersistSerialize(source)
            | FireCoreError::PersistDeserialize(source)
            | FireCoreError::DiagnosticsSerialize(source)
            | FireCoreError::DiagnosticsDeserialize(source) => Self::Serialization {
                details: source.to_string(),
            },
            FireCoreError::DiagnosticsTraceNotFound { trace_id } => Self::Validation {
                details: format!("network request trace not found: {trace_id}"),
            },
            FireCoreError::PersistVersionMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session uses unsupported version {found}, expected {expected}"
                ),
            },
            FireCoreError::PersistBaseUrlMismatch { expected, found } => Self::Validation {
                details: format!(
                    "persisted session base url mismatch: expected {expected}, found {found}"
                ),
            },
        }
    }
}

#[derive(uniffi::Object)]
pub struct FireCoreHandle {
    inner: Arc<FireCore>,
    panic_state: Arc<PanicState>,
}

#[uniffi::export]
impl FireCoreHandle {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        constructor_guard("constructor.new", || {
            Ok(Self {
                inner: Arc::new(FireCore::new(FireCoreConfig {
                    base_url: base_url.unwrap_or_else(|| "https://linux.do".to_string()),
                    workspace_path,
                })?),
                panic_state: Arc::new(PanicState::default()),
            })
        })
    }

    pub fn base_url(&self) -> Result<String, FireUniFfiError> {
        self.run_infallible("base_url", |inner| inner.base_url().to_string())
    }

    pub fn workspace_path(&self) -> Result<Option<String>, FireUniFfiError> {
        self.run_infallible("workspace_path", |inner| {
            inner
                .workspace_path()
                .map(|path| path.display().to_string())
        })
    }

    pub fn resolve_workspace_path(&self, relative_path: String) -> Result<String, FireUniFfiError> {
        self.run_fallible("resolve_workspace_path", move |inner| {
            inner
                .resolve_workspace_path(relative_path)
                .map(|path| path.display().to_string())
        })
    }

    pub fn flush_logs(&self, sync: bool) -> Result<(), FireUniFfiError> {
        self.run_infallible("flush_logs", move |inner| inner.flush_logs(sync))
    }

    pub fn list_log_files(&self) -> Result<Vec<LogFileSummaryState>, FireUniFfiError> {
        self.run_fallible("list_log_files", |inner| {
            inner
                .list_log_files()
                .map(|items| items.into_iter().map(Into::into).collect())
        })
    }

    pub fn read_log_file(
        &self,
        relative_path: String,
    ) -> Result<LogFileDetailState, FireUniFfiError> {
        self.run_fallible("read_log_file", move |inner| {
            inner.read_log_file(relative_path).map(Into::into)
        })
    }

    pub fn list_network_traces(
        &self,
        limit: u64,
    ) -> Result<Vec<NetworkTraceSummaryState>, FireUniFfiError> {
        self.run_infallible("list_network_traces", move |inner| {
            let limit = usize::try_from(limit).unwrap_or(usize::MAX);
            inner
                .list_network_traces(limit)
                .into_iter()
                .map(Into::into)
                .collect()
        })
    }

    pub fn network_trace_detail(
        &self,
        trace_id: u64,
    ) -> Result<Option<NetworkTraceDetailState>, FireUniFfiError> {
        self.run_infallible("network_trace_detail", move |inner| {
            inner.network_trace_detail(trace_id).map(Into::into)
        })
    }

    pub fn has_login_session(&self) -> Result<bool, FireUniFfiError> {
        self.run_infallible("has_login_session", |inner| inner.has_login_session())
    }

    pub fn snapshot(&self) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("snapshot", |inner| {
            SessionState::from_snapshot(inner.snapshot())
        })
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        self.run_fallible("export_session_json", |inner| inner.export_session_json())
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        self.run_fallible("restore_session_json", move |inner| {
            inner
                .restore_session_json(json)
                .map(SessionState::from_snapshot)
        })
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("save_session_to_path", move |inner| {
            inner.save_session_to_path(path)
        })
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        self.run_fallible("load_session_from_path", move |inner| {
            inner
                .load_session_from_path(path)
                .map(SessionState::from_snapshot)
        })
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("clear_session_path", move |inner| {
            inner.clear_session_path(path)
        })
    }

    pub async fn fetch_topic_list(
        &self,
        query: TopicListQueryState,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_list", panic_state, async move {
            inner.fetch_topic_list(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_detail", panic_state, async move {
            inner.fetch_topic_detail(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn create_reply(
        &self,
        input: TopicReplyRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("create_reply", panic_state, async move {
            inner.create_reply(input.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn like_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("like_post", panic_state, async move {
            inner.like_post(post_id).await
        })
        .await?;
        Ok(())
    }

    pub async fn unlike_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("unlike_post", panic_state, async move {
            inner.unlike_post(post_id).await
        })
        .await?;
        Ok(())
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdateState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("toggle_post_reaction", panic_state, async move {
            inner.toggle_post_reaction(post_id, reaction_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_cookies", move |inner| {
            SessionState::from_snapshot(inner.apply_cookies(cookies.into()))
        })
    }

    pub fn merge_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("merge_platform_cookies", move |inner| {
            SessionState::from_snapshot(
                inner.merge_platform_cookies(cookies.into_iter().map(Into::into).collect()),
            )
        })
    }

    pub fn apply_bootstrap(
        &self,
        bootstrap: BootstrapState,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_bootstrap", move |inner| {
            SessionState::from_snapshot(inner.apply_bootstrap(bootstrap.into()))
        })
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_csrf_token", move |inner| {
            SessionState::from_snapshot(inner.apply_csrf_token(csrf_token))
        })
    }

    pub fn clear_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("clear_csrf_token", |inner| {
            SessionState::from_snapshot(inner.clear_csrf_token())
        })
    }

    pub fn apply_home_html(&self, html: String) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_home_html", move |inner| {
            SessionState::from_snapshot(inner.apply_home_html(html))
        })
    }

    pub fn sync_login_context(
        &self,
        context: LoginSyncState,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("sync_login_context", move |inner| {
            SessionState::from_snapshot(inner.sync_login_context(context.into()))
        })
    }

    pub fn logout_local(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("logout_local", move |inner| {
            SessionState::from_snapshot(inner.logout_local(preserve_cf_clearance))
        })
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_bootstrap", panic_state, async move {
            inner.refresh_bootstrap().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_bootstrap_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_bootstrap_if_needed", panic_state, async move {
            inner.refresh_bootstrap_if_needed().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("refresh_csrf_token", panic_state, async move {
            inner.refresh_csrf_token().await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token_if_needed(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot =
            run_on_ffi_runtime("refresh_csrf_token_if_needed", panic_state, async move {
                inner.refresh_csrf_token_if_needed().await
            })
            .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let snapshot = run_on_ffi_runtime("logout_remote", panic_state, async move {
            inner.logout_remote(preserve_cf_clearance).await
        })
        .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
}

impl FireCoreHandle {
    fn run_fallible<T, F>(&self, operation: &'static str, f: F) -> Result<T, FireUniFfiError>
    where
        F: FnOnce(&FireCore) -> Result<T, FireCoreError>,
    {
        self.panic_state.ensure_healthy(operation)?;
        match panic::catch_unwind(AssertUnwindSafe(|| f(self.inner.as_ref()))) {
            Ok(Ok(value)) => Ok(value),
            Ok(Err(error)) => Err(error.into()),
            Err(payload) => Err(self.panic_state.capture_panic(operation, payload.as_ref())),
        }
    }

    fn run_infallible<T, F>(&self, operation: &'static str, f: F) -> Result<T, FireUniFfiError>
    where
        F: FnOnce(&FireCore) -> T,
    {
        self.panic_state.ensure_healthy(operation)?;
        match panic::catch_unwind(AssertUnwindSafe(|| f(self.inner.as_ref()))) {
            Ok(value) => Ok(value),
            Err(payload) => Err(self.panic_state.capture_panic(operation, payload.as_ref())),
        }
    }
}

fn constructor_guard<T, F>(operation: &'static str, f: F) -> Result<T, FireUniFfiError>
where
    F: FnOnce() -> Result<T, FireCoreError>,
{
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(payload) => {
            let report = CapturedPanic::from_payload(operation, payload.as_ref());
            report.log();
            Err(FireUniFfiError::Internal {
                details: report.user_message(),
            })
        }
    }
}

async fn run_on_ffi_runtime<T, Fut>(
    operation: &'static str,
    panic_state: Arc<PanicState>,
    future: Fut,
) -> Result<T, FireUniFfiError>
where
    T: Send + 'static,
    Fut: Future<Output = Result<T, FireCoreError>> + Send + 'static,
{
    panic_state.ensure_healthy(operation)?;
    ffi_runtime()
        .spawn(AssertUnwindSafe(future).catch_unwind())
        .await
        .map_err(|error| FireUniFfiError::Runtime {
            details: error.to_string(),
        })?
        .map_err(|payload| panic_state.capture_panic(operation, payload.as_ref()))?
        .map_err(Into::into)
}

fn ffi_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to create ffi runtime")
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{io, path::PathBuf};

    #[test]
    fn maps_http_status_errors_without_flattening() {
        let error = FireUniFfiError::from(FireCoreError::HttpStatus {
            operation: "fetch topic list",
            status: 429,
            body: "slow down".to_string(),
        });

        assert!(matches!(
            error,
            FireUniFfiError::HttpStatus {
                operation,
                status: 429,
                body,
            } if operation == "fetch topic list" && body == "slow down"
        ));
    }

    #[test]
    fn maps_cloudflare_challenge_errors_to_dedicated_variant() {
        let error = FireUniFfiError::from(FireCoreError::CloudflareChallenge {
            operation: "create reply",
        });

        assert!(matches!(error, FireUniFfiError::CloudflareChallenge));
    }

    #[test]
    fn maps_storage_errors_to_storage_variant() {
        let error = FireUniFfiError::from(FireCoreError::PersistIo {
            path: PathBuf::from("/tmp/session.json"),
            source: io::Error::new(io::ErrorKind::PermissionDenied, "denied"),
        });

        assert!(matches!(
            error,
            FireUniFfiError::Storage { details }
                if details.contains("/tmp/session.json") && details.contains("denied")
        ));
    }

    #[test]
    fn runs_async_work_on_ffi_runtime() {
        let panic_state = Arc::new(PanicState::default());
        let value = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_success",
                Arc::clone(&panic_state),
                async { Ok::<_, FireCoreError>(42_u8) },
            ))
            .expect("ffi runtime should resolve async work");

        assert_eq!(value, 42);
    }

    #[test]
    fn converts_sync_panic_to_internal_error_and_poisoned_handle() {
        let handle = FireCoreHandle::new(None, None).expect("constructor should succeed");

        let error = handle
            .run_infallible("test_sync_panic", |_| {
                panic!("boom");
            })
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details } if details.contains("test_sync_panic panicked: boom")
        ));
        assert!(matches!(
            handle.panic_state.ensure_healthy("snapshot"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_sync_panic panicked: boom")
        ));
    }

    #[test]
    fn converts_async_panic_to_internal_error_and_poisoned_handle() {
        let panic_state = Arc::new(PanicState::default());

        let error = ffi_runtime()
            .block_on(run_on_ffi_runtime(
                "test_async_panic",
                Arc::clone(&panic_state),
                async {
                    panic!("async boom");
                    #[allow(unreachable_code)]
                    Ok::<(), FireCoreError>(())
                },
            ))
            .expect_err("panic should map to an internal error");

        assert!(matches!(
            error,
            FireUniFfiError::Internal { details }
                if details.contains("test_async_panic panicked: async boom")
        ));
        assert!(matches!(
            panic_state.ensure_healthy("fetch_topic_list"),
            Err(FireUniFfiError::Internal { details })
                if details.contains("poisoned by a previous panic")
                    && details.contains("test_async_panic panicked: async boom")
        ));
    }
}
