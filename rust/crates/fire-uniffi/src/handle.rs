use std::sync::Arc;

use fire_core::{
    monogram_for_username as shared_monogram_for_username,
    plain_text_from_html as shared_plain_text_from_html,
    preview_text_from_html as shared_preview_text_from_html, FireCore,
};
use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_messagebus::FireMessageBusHandle;
use fire_uniffi_notifications::FireNotificationsHandle;
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_session::FireSessionHandle;
use fire_uniffi_topics::{FireTopicsHandle, InviteCreateRequestState};
use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, PanicState, SharedFireCore};

use crate::state_user::{
    BadgeState, FollowUserState, InviteLinkState, UserActionState, UserProfileState,
    UserSummaryState,
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
    messagebus: Arc<FireMessageBusHandle>,
    notifications: Arc<FireNotificationsHandle>,
    search: Arc<FireSearchHandle>,
    session: Arc<FireSessionHandle>,
    topics: Arc<FireTopicsHandle>,
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
            messagebus: FireMessageBusHandle::from_shared(shared.clone()),
            notifications: FireNotificationsHandle::from_shared(shared.clone()),
            search: FireSearchHandle::from_shared(shared.clone()),
            session: FireSessionHandle::from_shared(shared.clone()),
            topics: FireTopicsHandle::from_shared(shared),
        })
    }

    pub fn diagnostics(&self) -> Arc<FireDiagnosticsHandle> {
        self.diagnostics.clone()
    }

    pub fn messagebus(&self) -> Arc<FireMessageBusHandle> {
        self.messagebus.clone()
    }

    pub fn notifications(&self) -> Arc<FireNotificationsHandle> {
        self.notifications.clone()
    }

    pub fn search(&self) -> Arc<FireSearchHandle> {
        self.search.clone()
    }

    pub fn session(&self) -> Arc<FireSessionHandle> {
        self.session.clone()
    }

    pub fn topics(&self) -> Arc<FireTopicsHandle> {
        self.topics.clone()
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
