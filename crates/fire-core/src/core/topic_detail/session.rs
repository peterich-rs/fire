use tokio::sync::{mpsc, oneshot};

use super::*;
use crate::error::FireCoreError;

pub struct TopicDetailSession {
    pub(super) topic_id: u64,
    pub(super) owner_token: String,
    pub(super) tx: mpsc::UnboundedSender<Command>,
}

impl TopicDetailSession {
    pub fn topic_id(&self) -> u64 {
        self.topic_id
    }

    pub fn owner_token(&self) -> &str {
        &self.owner_token
    }

    pub fn release_owner(&self, owner_token: &str) {
        let _ = owner_token;
    }

    pub fn reload(
        &self,
        target_post_number: Option<u32>,
        force_load: bool,
        track_visit: bool,
        allow_suggested_unread_root: bool,
    ) {
        let _ = self.tx.send(Command::Reload {
            target_post_number,
            force_load,
            track_visit,
            allow_suggested_unread_root,
        });
    }

    pub fn load_more(&self) {
        let _ = self.tx.send(Command::LoadMore);
    }

    pub fn note_visible_posts(&self, post_numbers: Vec<u32>) {
        let _ = self.tx.send(Command::NoteVisible(post_numbers));
    }

    pub fn note_filtered_feed_tail(&self, item_count: u32, visible_max_item: Option<u32>) {
        let _ = self.tx.send(Command::NoteTail {
            item_count,
            visible_max_item,
        });
    }

    pub fn note_scroll_interaction(&self, active: bool) {
        let _ = self.tx.send(Command::NoteScroll(active));
    }

    pub fn acknowledge_scroll_target(&self, post_number: u32) {
        let _ = self.tx.send(Command::AckScroll(post_number));
    }

    pub fn clear_scroll_target(&self) {
        let _ = self.tx.send(Command::ClearScroll);
    }

    pub fn begin_reply_typing(&self) {
        let _ = self.tx.send(Command::BeginTyping);
    }

    pub fn end_reply_typing(&self) {
        let _ = self.tx.send(Command::EndTyping);
    }

    pub fn reload_ai_summary(&self, skip_age_check: bool) {
        let _ = self.tx.send(Command::ReloadAi { skip_age_check });
    }

    pub fn load_reply_context(&self, post_id: u64) {
        let _ = self.tx.send(Command::LoadReplyContext(post_id));
    }

    pub async fn prepare_edit(&self, post_id: u64) -> Result<String, FireCoreError> {
        self.roundtrip(|reply| Command::PrepareEdit { post_id, reply })
            .await
    }

    pub async fn ensure_flag_types(&self) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::EnsureFlags { reply }).await
    }

    pub async fn submit_reply(
        &self,
        raw: String,
        reply_to_post_number: Option<u32>,
        scroll_to_created: bool,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::SubmitReply {
            raw,
            reply_to_post_number,
            scroll_to_created,
            reply,
        })
        .await
    }

    pub async fn create_boost(&self, post_id: u64, raw: String) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::CreateBoost {
            post_id,
            raw,
            reply,
        })
        .await
    }

    pub async fn delete_boost(&self, post_id: u64, boost_id: u64) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::DeleteBoost {
            post_id,
            boost_id,
            reply,
        })
        .await
    }

    pub async fn update_post(
        &self,
        post_id: u64,
        raw: String,
        edit_reason: Option<String>,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::UpdatePost {
            post_id,
            raw,
            edit_reason,
            reply,
        })
        .await
    }

    pub async fn delete_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::DeletePost { post_id, reply })
            .await
    }

    pub async fn recover_post(&self, post_id: u64) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::RecoverPost { post_id, reply })
            .await
    }

    pub async fn flag_post(
        &self,
        post_id: u64,
        flag_type_id: u32,
        message: Option<String>,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::FlagPost {
            post_id,
            flag_type_id,
            message,
            reply,
        })
        .await
    }

    pub async fn set_liked(&self, post_id: u64, liked: bool) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::SetLiked {
            post_id,
            liked,
            reply,
        })
        .await
    }

    pub async fn toggle_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::ToggleReaction {
            post_id,
            reaction_id,
            reply,
        })
        .await
    }

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::VotePoll {
            post_id,
            poll_name,
            options,
            reply,
        })
        .await
    }

    pub async fn unvote_poll(&self, post_id: u64, poll_name: String) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::UnvotePoll {
            post_id,
            poll_name,
            reply,
        })
        .await
    }

    pub async fn vote_topic(&self, voted: bool) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::VoteTopic { voted, reply })
            .await
    }

    pub async fn accept_solution(&self, post_id: u64, accepted: bool) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::AcceptSolution {
            post_id,
            accepted,
            reply,
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
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::CreateBookmark {
            bookmarkable_id,
            bookmarkable_type,
            name,
            reminder_at,
            auto_delete_preference,
            reply,
        })
        .await
    }

    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::UpdateBookmark {
            bookmark_id,
            name,
            reminder_at,
            auto_delete_preference,
            reply,
        })
        .await
    }

    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::DeleteBookmark { bookmark_id, reply })
            .await
    }

    pub async fn set_notification_level(&self, level: i32) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::SetNotificationLevel { level, reply })
            .await
    }

    pub async fn update_topic(
        &self,
        title: String,
        category_id: u64,
        tags: Vec<String>,
    ) -> Result<(), FireCoreError> {
        self.roundtrip(|reply| Command::UpdateTopic {
            title,
            category_id,
            tags,
            reply,
        })
        .await
    }

    pub async fn report_timings(
        &self,
        topic_time_ms: u32,
        timings: Vec<fire_models::TopicTimingEntry>,
    ) -> Result<bool, FireCoreError> {
        self.roundtrip(|reply| Command::ReportTimings {
            topic_time_ms,
            timings,
            reply,
        })
        .await
    }

    pub async fn sync_for_test(&self) {
        let (tx, rx) = oneshot::channel();
        if self.tx.send(Command::Flush(tx)).is_err() {
            return;
        }
        let _ = rx.await;
    }

    async fn roundtrip<T, F>(&self, command: F) -> Result<T, FireCoreError>
    where
        T: Send + 'static,
        F: FnOnce(oneshot::Sender<Result<T, FireCoreError>>) -> Command,
    {
        let (tx, rx) = oneshot::channel();
        self.tx.send(command(tx)).map_err(|_| session_closed())?;
        rx.await.map_err(|_| session_closed())?
    }
}

fn session_closed() -> FireCoreError {
    FireCoreError::InvalidArgument {
        operation: "topic detail session",
        details: "session is closed".to_string(),
    }
}
