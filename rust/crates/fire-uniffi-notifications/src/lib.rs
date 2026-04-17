uniffi::setup_scaffolding!("fire_uniffi_notifications");

use std::sync::Arc;

use fire_uniffi_types::{
    run_infallible, run_on_ffi_runtime, DraftDataState, DraftListResponseState, DraftState,
    FireUniFfiError, SharedFireCore, TopicListState,
};

pub mod records;

pub use records::{
    NotificationCenterState, NotificationCountersState, NotificationDataState,
    NotificationItemState, NotificationListState,
};

#[derive(uniffi::Object)]
pub struct FireNotificationsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireNotificationsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireNotificationsHandle {
    pub fn notification_state(&self) -> Result<NotificationCenterState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "notification_state",
            |inner| inner.notification_state().into(),
        )
    }

    pub async fn fetch_recent_notifications(
        &self,
        limit: Option<u32>,
    ) -> Result<NotificationListState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_recent_notifications", panic_state, async move {
            inner.fetch_recent_notifications(limit).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_notifications(
        &self,
        limit: Option<u32>,
        offset: Option<u32>,
    ) -> Result<NotificationListState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_notifications", panic_state, async move {
            inner.fetch_notifications(limit, offset).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn mark_notification_read(
        &self,
        notification_id: u64,
    ) -> Result<NotificationCenterState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("mark_notification_read", panic_state, async move {
            inner.mark_notification_read(notification_id).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn mark_all_notifications_read(
        &self,
    ) -> Result<NotificationCenterState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("mark_all_notifications_read", panic_state, async move {
            inner.mark_all_notifications_read().await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_bookmarks(
        &self,
        username: String,
        page: Option<u32>,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_bookmarks", panic_state, async move {
            inner.fetch_bookmarks(&username, page).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_read_history(
        &self,
        page: Option<u32>,
    ) -> Result<TopicListState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_read_history", panic_state, async move {
            inner.fetch_read_history(page).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_drafts(
        &self,
        offset: Option<u32>,
        limit: Option<u32>,
    ) -> Result<DraftListResponseState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_drafts", panic_state, async move {
            inner.fetch_drafts(offset, limit).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn fetch_draft(
        &self,
        draft_key: String,
    ) -> Result<Option<DraftState>, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("fetch_draft", panic_state, async move {
            inner.fetch_draft(&draft_key).await
        })
        .await?;
        Ok(response.map(Into::into))
    }

    pub async fn save_draft(
        &self,
        draft_key: String,
        data: DraftDataState,
        sequence: u32,
    ) -> Result<u32, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("save_draft", panic_state, async move {
            inner.save_draft(&draft_key, data.into(), sequence).await
        })
        .await
    }

    pub async fn delete_draft(
        &self,
        draft_key: String,
        sequence: Option<u32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("delete_draft", panic_state, async move {
            inner.delete_draft(&draft_key, sequence).await
        })
        .await
    }

    pub async fn create_bookmark(
        &self,
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<u64, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("create_bookmark", panic_state, async move {
            inner
                .create_bookmark(
                    bookmarkable_id,
                    &bookmarkable_type,
                    name.as_deref(),
                    reminder_at.as_deref(),
                    auto_delete_preference,
                )
                .await
        })
        .await
    }

    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("update_bookmark", panic_state, async move {
            inner
                .update_bookmark(bookmark_id, name, reminder_at, auto_delete_preference)
                .await
        })
        .await
    }

    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("delete_bookmark", panic_state, async move {
            inner.delete_bookmark(bookmark_id).await
        })
        .await
    }

    pub async fn set_topic_notification_level(
        &self,
        topic_id: u64,
        notification_level: i32,
    ) -> Result<(), FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        run_on_ffi_runtime("set_topic_notification_level", panic_state, async move {
            inner
                .set_topic_notification_level(topic_id, notification_level)
                .await
        })
        .await
    }
}
