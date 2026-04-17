uniffi::setup_scaffolding!("fire_uniffi_user");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

pub use records::{
    BadgeState, FollowUserState, InviteCreateRequestState, InviteLinkDetailsState, InviteLinkState,
    ProfileSummaryReplyState, ProfileSummaryTopCategoryState, ProfileSummaryTopicState,
    ProfileSummaryUserReferenceState, UserActionState, UserProfileState, UserSummaryState,
    UserSummaryStatsState,
};

#[derive(uniffi::Object)]
pub struct FireUserHandle {
    shared: Arc<SharedFireCore>,
}

impl FireUserHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireUserHandle {
    pub async fn fetch_user_profile(
        &self,
        username: String,
    ) -> Result<UserProfileState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let users = run_on_ffi_runtime("fetch_followers", panic_state, async move {
            inner.fetch_followers(&username).await
        })
        .await?;
        Ok(users.into_iter().map(Into::into).collect())
    }

    pub async fn follow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("follow_user", panic_state, async move {
            inner.follow_user(&username).await
        })
        .await
    }

    pub async fn unfollow_user(&self, username: String) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("unfollow_user", panic_state, async move {
            inner.unfollow_user(&username).await
        })
        .await
    }

    pub async fn fetch_badge_detail(&self, badge_id: u64) -> Result<BadgeState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
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
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let invite = run_on_ffi_runtime("create_invite_link", panic_state, async move {
            inner.create_invite_link(input.into()).await
        })
        .await?;
        Ok(invite.into())
    }
}
