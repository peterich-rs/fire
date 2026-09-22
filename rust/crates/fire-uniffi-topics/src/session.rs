use std::panic::{self, AssertUnwindSafe};
use std::sync::Arc;

use fire_core::TopicDetailObserver as CoreTopicDetailObserver;
use fire_models::TopicDetailUiSnapshot;
use fire_uniffi_types::{ffi_runtime, run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

use crate::records::TopicTimingEntryState;
use crate::ui_records::{TopicDetailOpenRequestState, TopicDetailUiSnapshotState};
use crate::FireTopicsHandle;

struct FfiTopicDetailObserver {
    inner: Arc<dyn TopicDetailObserver>,
}

impl CoreTopicDetailObserver for FfiTopicDetailObserver {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshot) {
        let projected = TopicDetailUiSnapshotState::from_core(snapshot);
        let inner = Arc::clone(&self.inner);
        let _ = panic::catch_unwind(AssertUnwindSafe(|| inner.on_snapshot(projected)));
    }
}

#[uniffi::export(with_foreign)]
pub trait TopicDetailObserver: Send + Sync {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshotState);
}

#[derive(uniffi::Object)]
pub struct TopicDetailSessionHandle {
    shared: Arc<SharedFireCore>,
    inner: Arc<fire_core::TopicDetailSession>,
    topic_id: u64,
    owner_token: String,
}

#[uniffi::export]
impl FireTopicsHandle {
    pub fn cancel_topic_detail_http(&self) {
        self.shared.core.cancel_topic_detail_http();
    }

    pub fn close_all_topic_detail_sessions(&self) {
        self.shared.core.close_all_topic_detail_sessions();
    }

    pub fn open_topic_detail(
        &self,
        request: TopicDetailOpenRequestState,
        observer: Arc<dyn TopicDetailObserver>,
    ) -> Result<Arc<TopicDetailSessionHandle>, FireUniFfiError> {
        let topic_id = request.topic_id;
        let owner_token = request.owner_token.clone();
        let core = Arc::clone(&self.shared.core);
        let request = request.into_core();
        let observer = Arc::new(FfiTopicDetailObserver { inner: observer });
        let (tx, rx) = std::sync::mpsc::sync_channel(1);
        ffi_runtime().spawn(async move {
            let session = core.open_topic_detail(request, observer);
            let _ = tx.send(session);
        });
        let inner = rx.recv().map_err(|_| FireUniFfiError::Runtime {
            details: "failed to open topic detail session".to_string(),
        })?;
        Ok(Arc::new(TopicDetailSessionHandle {
            shared: Arc::clone(&self.shared),
            inner,
            topic_id,
            owner_token,
        }))
    }
}

#[uniffi::export]
impl TopicDetailSessionHandle {
    pub fn release(&self) {
        self.shared
            .core
            .release_topic_detail_owner(self.topic_id, &self.owner_token);
    }

    pub fn reload(
        &self,
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
    ) {
        self.inner.reload(
            target_post_number,
            force_load,
            track_visit,
            allow_suggested_unread_root,
        );
    }

    pub fn load_more(&self) {
        self.inner.load_more();
    }

    pub fn note_visible_posts(&self, post_numbers: Vec<u32>) {
        self.inner.note_visible_posts(post_numbers);
    }

    pub fn note_filtered_feed_tail(&self, item_count: u32, visible_max_item: Option<u32>) {
        self.inner
            .note_filtered_feed_tail(item_count, visible_max_item);
    }

    pub fn note_scroll_interaction(&self, active: bool) {
        self.inner.note_scroll_interaction(active);
    }

    pub fn acknowledge_scroll_target(&self, post_number: u32) {
        self.inner.acknowledge_scroll_target(post_number);
    }

    pub fn clear_scroll_target(&self) {
        self.inner.clear_scroll_target();
    }

    pub fn begin_reply_typing(&self) {
        self.inner.begin_reply_typing();
    }

    pub fn end_reply_typing(&self) {
        self.inner.end_reply_typing();
    }

    pub fn reload_ai_summary(&self, skip_age_check: bool) {
        self.inner.reload_ai_summary(skip_age_check);
    }

    pub fn load_reply_context(&self, post_id: u64) {
        self.inner.load_reply_context(post_id);
    }

    pub async fn prepare_edit(&self, post_id: u64) -> Result<String, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "prepare_edit",
            Arc::clone(&self.shared.panic_state),
            async move { inner.prepare_edit(post_id).await },
        )
        .await
    }

    pub async fn submit_reply(
        &self,
        raw: String,
        reply_to_post_number: Option<u32>,
        scroll_to_created: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "submit_reply",
            Arc::clone(&self.shared.panic_state),
            async move {
                inner
                    .submit_reply(raw, reply_to_post_number, scroll_to_created)
                    .await
            },
        )
        .await
    }

    pub async fn create_boost(&self, post_id: u64, raw: String) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "create_boost",
            Arc::clone(&self.shared.panic_state),
            async move { inner.create_boost(post_id, raw).await },
        )
        .await
    }

    pub async fn delete_boost(&self, post_id: u64, boost_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "delete_boost",
            Arc::clone(&self.shared.panic_state),
            async move { inner.delete_boost(post_id, boost_id).await },
        )
        .await
    }

    pub async fn update_post(
        &self,
        post_id: u64,
        raw: String,
        edit_reason: Option<String>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "update_post",
            Arc::clone(&self.shared.panic_state),
            async move { inner.update_post(post_id, raw, edit_reason).await },
        )
        .await
    }

    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "delete_post",
            Arc::clone(&self.shared.panic_state),
            async move { inner.delete_post(post_id).await },
        )
        .await
    }

    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "recover_post",
            Arc::clone(&self.shared.panic_state),
            async move { inner.recover_post(post_id).await },
        )
        .await
    }

    pub async fn flag_post(
        &self,
        post_id: u64,
        flag_type_id: u32,
        message: Option<String>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "flag_post",
            Arc::clone(&self.shared.panic_state),
            async move { inner.flag_post(post_id, flag_type_id, message).await },
        )
        .await
    }

    pub async fn ensure_flag_types(&self) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "ensure_flag_types",
            Arc::clone(&self.shared.panic_state),
            async move { inner.ensure_flag_types().await },
        )
        .await
    }

    pub async fn set_liked(&self, post_id: u64, liked: bool) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "set_liked",
            Arc::clone(&self.shared.panic_state),
            async move { inner.set_liked(post_id, liked).await },
        )
        .await
    }

    pub async fn toggle_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "toggle_reaction",
            Arc::clone(&self.shared.panic_state),
            async move { inner.toggle_reaction(post_id, reaction_id).await },
        )
        .await
    }

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "vote_poll",
            Arc::clone(&self.shared.panic_state),
            async move { inner.vote_poll(post_id, poll_name, options).await },
        )
        .await
    }

    pub async fn unvote_poll(
        &self,
        post_id: u64,
        poll_name: String,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "unvote_poll",
            Arc::clone(&self.shared.panic_state),
            async move { inner.unvote_poll(post_id, poll_name).await },
        )
        .await
    }

    pub async fn vote_topic(&self, voted: bool) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "vote_topic",
            Arc::clone(&self.shared.panic_state),
            async move { inner.vote_topic(voted).await },
        )
        .await
    }

    pub async fn accept_solution(
        &self,
        post_id: u64,
        accepted: bool,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "accept_solution",
            Arc::clone(&self.shared.panic_state),
            async move { inner.accept_solution(post_id, accepted).await },
        )
        .await
    }

    pub async fn create_bookmark(
        &self,
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "create_bookmark",
            Arc::clone(&self.shared.panic_state),
            async move {
                inner
                    .create_bookmark(
                        bookmarkable_id,
                        bookmarkable_type,
                        name,
                        reminder_at,
                        auto_delete_preference,
                    )
                    .await
            },
        )
        .await
    }

    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "update_bookmark",
            Arc::clone(&self.shared.panic_state),
            async move {
                inner
                    .update_bookmark(bookmark_id, name, reminder_at, auto_delete_preference)
                    .await
            },
        )
        .await
    }

    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "delete_bookmark",
            Arc::clone(&self.shared.panic_state),
            async move { inner.delete_bookmark(bookmark_id).await },
        )
        .await
    }

    pub async fn set_notification_level(&self, level: i32) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "set_notification_level",
            Arc::clone(&self.shared.panic_state),
            async move { inner.set_notification_level(level).await },
        )
        .await
    }

    pub async fn update_topic(
        &self,
        title: String,
        category_id: u64,
        tags: Vec<String>,
    ) -> Result<(), FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        run_on_ffi_runtime(
            "update_topic",
            Arc::clone(&self.shared.panic_state),
            async move { inner.update_topic(title, category_id, tags).await },
        )
        .await
    }

    pub async fn report_timings(
        &self,
        topic_time_ms: u32,
        timings: Vec<TopicTimingEntryState>,
    ) -> Result<bool, FireUniFfiError> {
        let inner = Arc::clone(&self.inner);
        let timings = timings
            .into_iter()
            .map(fire_models::TopicTimingEntry::from)
            .collect();
        run_on_ffi_runtime(
            "report_timings",
            Arc::clone(&self.shared.panic_state),
            async move { inner.report_timings(topic_time_ms, timings).await },
        )
        .await
    }
}
