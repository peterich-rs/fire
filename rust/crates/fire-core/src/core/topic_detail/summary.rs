use super::super::topic_detail_project::project_history_rows;
use super::super::FireCore;
use super::*;
use crate::error::FireCoreError;

impl ActorState {
    pub(super) async fn maybe_fetch_summary(&mut self, core: &FireCore) {
        let summarizable = self
            .header
            .as_ref()
            .is_some_and(|header| header.summarizable);
        if summarizable && self.summary.is_none() && !self.summary_loading {
            self.fetch_summary(core, false).await;
        }
    }

    pub(super) async fn fetch_summary(&mut self, core: &FireCore, skip_age_check: bool) {
        self.summary_loading = true;
        self.summary_error = None;
        self.publish(core, false);
        match core
            .fetch_topic_ai_summary(self.topic_id, skip_age_check)
            .await
        {
            Ok(summary) => {
                self.summary = summary;
                self.summary_loading = false;
                self.summary_error = None;
            }
            Err(error) => {
                self.summary_loading = false;
                self.summary_error = Some(error.to_string());
            }
        }
        self.publish(core, false);
    }

    pub(super) async fn prepare_edit(
        &self,
        core: &FireCore,
        post_id: u64,
    ) -> Result<String, FireCoreError> {
        if let Some(Some(raw)) =
            core.with_topic_source_session_mut(self.topic_id, None, |session| {
                session
                    .post(post_id)
                    .and_then(|post| post.raw.clone())
                    .filter(|raw| !raw.is_empty())
            })
        {
            return Ok(raw);
        }
        let post = core.fetch_post(post_id).await?;
        let raw = post.raw.clone().unwrap_or_default();
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.merge_posts(std::iter::once(post));
        });
        Ok(raw)
    }

    pub(super) async fn ensure_flags(&mut self, core: &FireCore) -> Result<(), FireCoreError> {
        if !self.flag_types.is_empty() {
            return Ok(());
        }
        self.flag_types = core.fetch_post_action_types().await?;
        self.publish(core, false);
        Ok(())
    }

    pub(super) async fn load_reply_context(&mut self, core: &FireCore, post_id: u64) {
        self.loading_reply_context.insert(post_id);
        self.publish(core, false);
        let root_number = core
            .with_topic_source_session_mut(self.topic_id, None, |session| {
                session.post(post_id).map(|post| post.post_number)
            })
            .flatten()
            .unwrap_or(0);
        let reply_ids = core.fetch_post_reply_ids(post_id).await.unwrap_or_default();
        let mut replies = Vec::new();
        for chunk in reply_ids.chunks(TOPIC_DETAIL_REPLY_CONTEXT_BATCH) {
            if let Ok(posts) = core.fetch_topic_posts(self.topic_id, chunk.to_vec()).await {
                replies.extend(posts);
            }
        }
        let history = core
            .fetch_post_reply_history(post_id)
            .await
            .unwrap_or_default();
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.merge_posts(replies.iter().cloned());
            session.recompute_loaded_state();
        });
        let chrome = self.projection_chrome(core);
        self.reply_context = Some(fire_models::TopicDetailReplyContext {
            root_post_id: post_id,
            appended_post_ids: replies.iter().map(|post| post.id).collect(),
            history_rows: project_history_rows(&history, root_number, &chrome),
        });
        self.loading_reply_context.remove(&post_id);
        self.publish(core, true);
    }
}
