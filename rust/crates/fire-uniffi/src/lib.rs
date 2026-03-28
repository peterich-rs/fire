use std::{
    future::Future,
    sync::{Arc, OnceLock},
};

use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{
    BootstrapArtifacts, CookieSnapshot, LoginPhase, LoginSyncInput, PlatformCookie,
    SessionReadiness, SessionSnapshot, TopicDetail, TopicDetailCreatedBy, TopicDetailMeta,
    TopicDetailQuery, TopicListKind, TopicListQuery, TopicListResponse, TopicPost, TopicPostStream,
    TopicPoster, TopicReaction, TopicSummary, TopicUser,
};
use tokio::runtime::{Builder, Runtime};

uniffi::setup_scaffolding!("fire_uniffi");

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
}

impl SessionState {
    fn from_snapshot(snapshot: SessionSnapshot) -> Self {
        let readiness = snapshot.readiness();
        let login_phase = snapshot.login_phase();
        Self {
            has_login_session: snapshot.cookies.has_login_session(),
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
    pub tags: Vec<String>,
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
            tags: value.tags,
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
pub struct TopicListState {
    pub topics: Vec<TopicSummaryState>,
    pub users: Vec<TopicUserState>,
    pub more_topics_url: Option<String>,
}

impl From<TopicListResponse> for TopicListState {
    fn from(value: TopicListResponse) -> Self {
        Self {
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            more_topics_url: value.more_topics_url,
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
}

impl From<TopicReaction> for TopicReactionState {
    fn from(value: TopicReaction) -> Self {
        Self {
            id: value.id,
            kind: value.kind,
            count: value.count,
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
    pub tags: Vec<String>,
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
            tags: value.tags,
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
            details: value.details.into(),
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
            FireCoreError::HttpStatus {
                operation,
                status,
                body,
            } => Self::HttpStatus {
                operation: operation.to_string(),
                status,
                body,
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
            | FireCoreError::PersistIo { path, source } => Self::Storage {
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
            FireCoreError::PersistSerialize(source) | FireCoreError::PersistDeserialize(source) => {
                Self::Serialization {
                    details: source.to_string(),
                }
            }
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
}

#[uniffi::export]
impl FireCoreHandle {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        let inner = FireCore::new(FireCoreConfig {
            base_url: base_url.unwrap_or_else(|| "https://linux.do".to_string()),
            workspace_path,
        })?;
        Ok(Self {
            inner: Arc::new(inner),
        })
    }

    pub fn base_url(&self) -> String {
        self.inner.base_url().to_string()
    }

    pub fn workspace_path(&self) -> Option<String> {
        self.inner
            .workspace_path()
            .map(|path| path.display().to_string())
    }

    pub fn resolve_workspace_path(&self, relative_path: String) -> Result<String, FireUniFfiError> {
        self.inner
            .resolve_workspace_path(relative_path)
            .map(|path| path.display().to_string())
            .map_err(Into::into)
    }

    pub fn flush_logs(&self, sync: bool) {
        self.inner.flush_logs(sync);
    }

    pub fn has_login_session(&self) -> bool {
        self.inner.has_login_session()
    }

    pub fn snapshot(&self) -> SessionState {
        SessionState::from_snapshot(self.inner.snapshot())
    }

    pub fn export_session_json(&self) -> Result<String, FireUniFfiError> {
        self.inner.export_session_json().map_err(Into::into)
    }

    pub fn restore_session_json(&self, json: String) -> Result<SessionState, FireUniFfiError> {
        let snapshot = self.inner.restore_session_json(json)?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn save_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.inner.save_session_to_path(path).map_err(Into::into)
    }

    pub fn load_session_from_path(&self, path: String) -> Result<SessionState, FireUniFfiError> {
        let snapshot = self.inner.load_session_from_path(path)?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub fn clear_session_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.inner.clear_session_path(path).map_err(Into::into)
    }

    pub async fn fetch_topic_list(
        &self,
        query: TopicListQueryState,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let response =
            run_on_ffi_runtime(async move { inner.fetch_topic_list(query.into()).await }).await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_detail(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let response =
            run_on_ffi_runtime(async move { inner.fetch_topic_detail(query.into()).await }).await?;
        Ok(response.into())
    }

    pub fn apply_cookies(&self, cookies: CookieState) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_cookies(cookies.into()))
    }

    pub fn apply_bootstrap(&self, bootstrap: BootstrapState) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_bootstrap(bootstrap.into()))
    }

    pub fn apply_csrf_token(&self, csrf_token: String) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_csrf_token(csrf_token))
    }

    pub fn clear_csrf_token(&self) -> SessionState {
        SessionState::from_snapshot(self.inner.clear_csrf_token())
    }

    pub fn apply_home_html(&self, html: String) -> SessionState {
        SessionState::from_snapshot(self.inner.apply_home_html(html))
    }

    pub fn sync_login_context(&self, context: LoginSyncState) -> SessionState {
        SessionState::from_snapshot(self.inner.sync_login_context(context.into()))
    }

    pub fn logout_local(&self, preserve_cf_clearance: bool) -> SessionState {
        SessionState::from_snapshot(self.inner.logout_local(preserve_cf_clearance))
    }

    pub async fn refresh_bootstrap(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let snapshot = run_on_ffi_runtime(async move { inner.refresh_bootstrap().await }).await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn refresh_csrf_token(&self) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let snapshot = run_on_ffi_runtime(async move { inner.refresh_csrf_token().await }).await?;
        Ok(SessionState::from_snapshot(snapshot))
    }

    pub async fn logout_remote(
        &self,
        preserve_cf_clearance: bool,
    ) -> Result<SessionState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let snapshot =
            run_on_ffi_runtime(async move { inner.logout_remote(preserve_cf_clearance).await })
                .await?;
        Ok(SessionState::from_snapshot(snapshot))
    }
}

async fn run_on_ffi_runtime<T, Fut>(future: Fut) -> Result<T, FireUniFfiError>
where
    T: Send + 'static,
    Fut: Future<Output = Result<T, FireCoreError>> + Send + 'static,
{
    ffi_runtime()
        .spawn(future)
        .await
        .map_err(|error| FireUniFfiError::Runtime {
            details: error.to_string(),
        })?
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
        let value = ffi_runtime()
            .block_on(run_on_ffi_runtime(async { Ok::<_, FireCoreError>(42_u8) }))
            .expect("ffi runtime should resolve async work");

        assert_eq!(value, 42);
    }
}
