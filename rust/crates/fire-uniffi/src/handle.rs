use std::{
    panic::{self, AssertUnwindSafe},
    sync::Arc,
};

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    plain_text_from_html as shared_plain_text_from_html,
    preview_text_from_html as shared_preview_text_from_html, FireCore, FireCoreError,
};
use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_notifications::FireNotificationsHandle;
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_types::{
    ffi_runtime, run_on_ffi_runtime, FireUniFfiError, PanicState, SharedFireCore, TopicListState,
};
use crate::state_messagebus::{
    MessageBusClientModeState, MessageBusEventHandler, MessageBusSubscriptionState,
    NotificationAlertPollResultState, TopicPresenceState,
};
use crate::state_session::{
    BootstrapState, CookieState, LoginSyncState, PlatformCookieState, SessionState,
};
use crate::state_topic_detail::{
    InviteCreateRequestState, PollState, PostReactionUpdateState, PostUpdateRequestState,
    PrivateMessageCreateRequestState, ResolvedUploadUrlState, TopicCreateRequestState,
    TopicDetailQueryState, TopicDetailState, TopicPostState, TopicReplyRequestState,
    TopicTimingsRequestState, TopicUpdateRequestState, UploadImageRequestState, UploadResultState,
};
use crate::state_topic_list::TopicListQueryState;
use crate::state_user::{
    BadgeState, FollowUserState, InviteLinkState, UserActionState, UserProfileState,
    UserSummaryState, VoteResponseState, VotedUserState,
};

#[uniffi::export]
pub fn plain_text_from_html(raw_html: String) -> String {
    shared_plain_text_from_html(&raw_html)
}

#[uniffi::export]
pub fn preview_text_from_html(raw_html: Option<String>) -> Option<String> {
    shared_preview_text_from_html(raw_html.as_deref())
}

#[uniffi::export]
pub fn monogram_for_username(username: String) -> String {
    shared_monogram_for_username(&username)
}

#[derive(uniffi::Object)]
pub struct FireAppCore {
    inner: Arc<FireCore>,
    pub(crate) panic_state: Arc<PanicState>,
    diagnostics: Arc<FireDiagnosticsHandle>,
    notifications: Arc<FireNotificationsHandle>,
    search: Arc<FireSearchHandle>,
}

#[uniffi::export]
impl FireAppCore {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        let shared = Arc::new(SharedFireCore::bootstrap(base_url, workspace_path)?);
        Ok(Self {
            inner: shared.core.clone(),
            panic_state: shared.panic_state.clone(),
            diagnostics: FireDiagnosticsHandle::from_shared(shared.clone()),
            notifications: FireNotificationsHandle::from_shared(shared.clone()),
            search: FireSearchHandle::from_shared(shared),
        })
    }

    pub fn diagnostics(&self) -> Arc<FireDiagnosticsHandle> {
        self.diagnostics.clone()
    }

    pub fn notifications(&self) -> Arc<FireNotificationsHandle> {
        self.notifications.clone()
    }

    pub fn search(&self) -> Arc<FireSearchHandle> {
        self.search.clone()
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

    pub fn export_redacted_session_json(&self) -> Result<String, FireUniFfiError> {
        self.run_fallible("export_redacted_session_json", |inner| {
            inner.export_redacted_session_json()
        })
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

    pub fn save_redacted_session_to_path(&self, path: String) -> Result<(), FireUniFfiError> {
        self.run_fallible("save_redacted_session_to_path", move |inner| {
            inner.save_redacted_session_to_path(path)
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

    pub fn subscribe_channel(
        &self,
        subscription: MessageBusSubscriptionState,
    ) -> Result<(), FireUniFfiError> {
        self.run_fallible("subscribe_channel", move |inner| {
            inner.subscribe_message_bus_channel(subscription.into())
        })
    }

    pub fn unsubscribe_channel(
        &self,
        owner_token: String,
        channel: String,
    ) -> Result<(), FireUniFfiError> {
        self.run_fallible("unsubscribe_channel", move |inner| {
            inner.unsubscribe_message_bus_channel(owner_token, channel)
        })
    }

    pub fn stop_message_bus(&self, clear_subscriptions: bool) -> Result<(), FireUniFfiError> {
        self.run_infallible("stop_message_bus", move |inner| {
            inner.stop_message_bus(clear_subscriptions)
        })
    }

    pub async fn start_message_bus(
        &self,
        mode: MessageBusClientModeState,
        handler: Arc<dyn MessageBusEventHandler>,
    ) -> Result<String, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let (event_sender, mut event_receiver) = tokio::sync::mpsc::unbounded_channel();
        let client_id = run_on_ffi_runtime("start_message_bus", panic_state, async move {
            inner.start_message_bus(mode.into(), event_sender).await
        })
        .await?;

        ffi_runtime().spawn(async move {
            while let Some(event) = event_receiver.recv().await {
                handler.on_message_bus_event(event.into());
            }
        });

        Ok(client_id)
    }

    pub fn topic_reply_presence_state(
        &self,
        topic_id: u64,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        self.run_infallible("topic_reply_presence_state", move |inner| {
            inner.topic_reply_presence_state(topic_id).into()
        })
    }

    pub async fn bootstrap_topic_reply_presence(
        &self,
        topic_id: u64,
        owner_token: String,
    ) -> Result<TopicPresenceState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let presence =
            run_on_ffi_runtime("bootstrap_topic_reply_presence", panic_state, async move {
                inner
                    .bootstrap_topic_reply_presence(topic_id, owner_token)
                    .await
            })
            .await?;
        Ok(presence.into())
    }

    pub async fn update_topic_reply_presence(
        &self,
        topic_id: u64,
        active: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("update_topic_reply_presence", panic_state, async move {
            inner.update_topic_reply_presence(topic_id, active).await
        })
        .await
    }

    pub async fn poll_notification_alert_once(
        &self,
        last_message_id: i64,
    ) -> Result<NotificationAlertPollResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response =
            run_on_ffi_runtime("poll_notification_alert_once", panic_state, async move {
                inner.poll_notification_alert_once(last_message_id).await
            })
            .await?;
        Ok(response.into())
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

    pub async fn fetch_topic_detail_initial(
        &self,
        query: TopicDetailQueryState,
    ) -> Result<TopicDetailState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_detail_initial", panic_state, async move {
            inner.fetch_topic_detail_initial(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_posts(
        &self,
        topic_id: u64,
        post_ids: Vec<u64>,
    ) -> Result<Vec<TopicPostState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_posts", panic_state, async move {
            inner.fetch_topic_posts(topic_id, post_ids).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
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

    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_post", panic_state, async move {
            inner.fetch_post(post_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn update_post(
        &self,
        input: PostUpdateRequestState,
    ) -> Result<TopicPostState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("update_post", panic_state, async move {
            inner.update_post(input.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn create_topic(
        &self,
        input: TopicCreateRequestState,
    ) -> Result<u64, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("create_topic", panic_state, async move {
            inner.create_topic(input.into()).await
        })
        .await
    }

    pub async fn create_private_message(
        &self,
        input: PrivateMessageCreateRequestState,
    ) -> Result<u64, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("create_private_message", panic_state, async move {
            inner.create_private_message(input.into()).await
        })
        .await
    }

    pub async fn update_topic(
        &self,
        input: TopicUpdateRequestState,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("update_topic", panic_state, async move {
            inner.update_topic(input.into()).await
        })
        .await
    }

    pub async fn upload_image(
        &self,
        input: UploadImageRequestState,
    ) -> Result<UploadResultState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("upload_image", panic_state, async move {
            inner
                .upload_image(&input.file_name, input.mime_type.as_deref(), input.bytes)
                .await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn lookup_upload_urls(
        &self,
        short_urls: Vec<String>,
    ) -> Result<Vec<ResolvedUploadUrlState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("lookup_upload_urls", panic_state, async move {
            inner.lookup_upload_urls(short_urls).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
    }

    pub async fn report_topic_timings(
        &self,
        input: TopicTimingsRequestState,
    ) -> Result<bool, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let accepted = run_on_ffi_runtime("report_topic_timings", panic_state, async move {
            inner.report_topic_timings(input.into()).await
        })
        .await?;
        Ok(accepted)
    }

    pub async fn like_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("like_post", panic_state, async move {
            inner.like_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn unlike_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdateState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unlike_post", panic_state, async move {
            inner.unlike_post(post_id).await
        })
        .await?;
        Ok(response.map(Into::into))
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

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("vote_poll", panic_state, async move {
            inner.vote_poll(post_id, &poll_name, options).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_poll(
        &self,
        post_id: u64,
        poll_name: String,
    ) -> Result<PollState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unvote_poll", panic_state, async move {
            inner.unvote_poll(post_id, &poll_name).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn vote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("vote_topic", panic_state, async move {
            inner.vote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn unvote_topic(&self, topic_id: u64) -> Result<VoteResponseState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("unvote_topic", panic_state, async move {
            inner.unvote_topic(topic_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_topic_voters(
        &self,
        topic_id: u64,
    ) -> Result<Vec<VotedUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let response = run_on_ffi_runtime("fetch_topic_voters", panic_state, async move {
            inner.fetch_topic_voters(topic_id).await
        })
        .await?;
        Ok(response.into_iter().map(Into::into).collect())
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

    pub fn apply_platform_cookies(
        &self,
        cookies: Vec<PlatformCookieState>,
    ) -> Result<SessionState, FireUniFfiError> {
        self.run_infallible("apply_platform_cookies", move |inner| {
            SessionState::from_snapshot(
                inner.apply_platform_cookies(cookies.into_iter().map(Into::into).collect()),
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

    pub async fn fetch_user_profile(
        &self,
        username: String,
    ) -> Result<UserProfileState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let profile = run_on_ffi_runtime("fetch_user_profile", panic_state, async move {
            inner.fetch_user_profile(&username).await
        })
        .await?;
        Ok(profile.into())
    }

    pub async fn fetch_user_summary(
        &self,
        username: String,
    ) -> Result<UserSummaryState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let summary = run_on_ffi_runtime("fetch_user_summary", panic_state, async move {
            inner.fetch_user_summary(&username).await
        })
        .await?;
        Ok(summary.into())
    }

    pub async fn fetch_following(
        &self,
        username: String,
    ) -> Result<Vec<FollowUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let users = run_on_ffi_runtime("fetch_following", panic_state, async move {
            inner.fetch_following(&username).await
        })
        .await?;
        Ok(users.into_iter().map(Into::into).collect())
    }

    pub async fn fetch_followers(
        &self,
        username: String,
    ) -> Result<Vec<FollowUserState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let users = run_on_ffi_runtime("fetch_followers", panic_state, async move {
            inner.fetch_followers(&username).await
        })
        .await?;
        Ok(users.into_iter().map(Into::into).collect())
    }

    pub async fn follow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("follow_user", panic_state, async move {
            inner.follow_user(&username).await
        })
        .await
    }

    pub async fn unfollow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        run_on_ffi_runtime("unfollow_user", panic_state, async move {
            inner.unfollow_user(&username).await
        })
        .await
    }

    pub async fn fetch_badge_detail(&self, badge_id: u64) -> Result<BadgeState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let badge = run_on_ffi_runtime("fetch_badge_detail", panic_state, async move {
            inner.fetch_badge_detail(badge_id).await
        })
        .await?;
        Ok(badge.into())
    }

    pub async fn fetch_user_actions(
        &self,
        username: String,
        offset: Option<u32>,
        filter: Option<String>,
    ) -> Result<Vec<UserActionState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let actions = run_on_ffi_runtime("fetch_user_actions", panic_state, async move {
            inner
                .fetch_user_actions(&username, offset, filter.as_deref())
                .await
        })
        .await?;
        Ok(actions.into_iter().map(Into::into).collect())
    }

    pub async fn fetch_pending_invites(
        &self,
        username: String,
    ) -> Result<Vec<InviteLinkState>, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let invites = run_on_ffi_runtime("fetch_pending_invites", panic_state, async move {
            inner.fetch_pending_invites(&username).await
        })
        .await?;
        Ok(invites.into_iter().map(Into::into).collect())
    }

    pub async fn create_invite_link(
        &self,
        input: InviteCreateRequestState,
    ) -> Result<InviteLinkState, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let panic_state = Arc::clone(&self.panic_state);
        let invite = run_on_ffi_runtime("create_invite_link", panic_state, async move {
            inner.create_invite_link(input.into()).await
        })
        .await?;
        Ok(invite.into())
    }
}

impl FireAppCore {
    pub(crate) fn run_fallible<T, F>(
        &self,
        operation: &'static str,
        f: F,
    ) -> Result<T, FireUniFfiError>
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

    pub(crate) fn run_infallible<T, F>(
        &self,
        operation: &'static str,
        f: F,
    ) -> Result<T, FireUniFfiError>
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
