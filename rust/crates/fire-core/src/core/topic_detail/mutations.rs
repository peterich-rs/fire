use fire_models::{TopicReplyRequest, TopicUpdateRequest};
use tokio::sync::mpsc;

use super::super::FireCore;
use super::*;
use crate::error::FireCoreError;

impl ActorState {
    pub(super) async fn submit_reply(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        raw: String,
        reply_to_post_number: Option<u32>,
        scroll_to_created: bool,
    ) -> Result<(), FireCoreError> {
        if raw.trim().is_empty() {
            return Err(FireCoreError::InvalidArgument {
                operation: "submit reply",
                details: "reply body is empty".to_string(),
            });
        }
        self.submitting = true;
        self.publish(core, false);
        let created = core
            .create_reply(TopicReplyRequest {
                topic_id: self.topic_id,
                raw,
                reply_to_post_number,
            })
            .await;
        self.submitting = false;
        let post = match created {
            Ok(post) => post,
            Err(error) => {
                self.publish(core, false);
                return Err(error);
            }
        };
        let post_number = post.post_number;
        let previous_len = core
            .with_topic_source_session_mut(self.topic_id, None, |session| session.raw_stream_len())
            .unwrap_or(0);
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let is_new = session.append_stream_post(post);
            if is_new {
                let stream_len = u32::try_from(session.raw_stream_len()).unwrap_or(u32::MAX);
                let header = session.header_mut();
                header.posts_count = header.posts_count.saturating_add(1).max(stream_len);
                header.reply_count = header
                    .reply_count
                    .saturating_add(1)
                    .max(header.posts_count.saturating_sub(1));
                header.highest_post_number = header.highest_post_number.max(post_number);
                header.last_read_post_number =
                    Some(header.last_read_post_number.unwrap_or(0).max(post_number));
            }
        });
        if self.window.requested.end >= previous_len {
            self.window.requested.end = self.window.requested.end.saturating_add(1);
        }
        if scroll_to_created {
            self.scroll_target = Some(post_number);
            self.scroll_exhausted = false;
        }
        self.capture_header(core);
        self.publish(core, true);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn create_boost(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        raw: String,
    ) -> Result<(), FireCoreError> {
        let boost = core.create_boost(post_id, raw).await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if let Some(post) = session.post_mut(post_id) {
                if !post.boosts.iter().any(|existing| existing.id == boost.id) {
                    post.boosts.push(boost);
                }
                post.can_boost = false;
            }
        });
        self.publish(core, true);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn delete_boost(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        boost_id: u64,
    ) -> Result<(), FireCoreError> {
        core.delete_boost(boost_id).await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if let Some(post) = session.post_mut(post_id) {
                post.boosts.retain(|boost| boost.id != boost_id);
            }
        });
        self.publish(core, true);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn update_post(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        raw: String,
        edit_reason: Option<String>,
    ) -> Result<(), FireCoreError> {
        let updated = core
            .update_post(fire_models::PostUpdateRequest {
                post_id,
                raw,
                edit_reason,
            })
            .await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.merge_posts(std::iter::once(updated));
        });
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn delete_post(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
    ) -> Result<(), FireCoreError> {
        core.delete_post(post_id).await?;
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn recover_post(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
    ) -> Result<(), FireCoreError> {
        core.recover_post(post_id).await?;
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn flag_post(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        flag_type_id: u32,
        message: Option<String>,
    ) -> Result<(), FireCoreError> {
        core.flag_post(fire_models::PostFlagRequest {
            post_id,
            flag_type_id,
            message,
        })
        .await?;
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn vote_poll(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        poll_name: String,
        options: Vec<String>,
    ) -> Result<(), FireCoreError> {
        let poll = core.vote_poll(post_id, &poll_name, options).await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if let Some(post) = session.post_mut(post_id) {
                if let Some(slot) = post.polls.iter_mut().find(|item| item.name == poll.name) {
                    *slot = poll;
                }
            }
        });
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn unvote_poll(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        poll_name: String,
    ) -> Result<(), FireCoreError> {
        let poll = core.unvote_poll(post_id, &poll_name).await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if let Some(post) = session.post_mut(post_id) {
                if let Some(slot) = post.polls.iter_mut().find(|item| item.name == poll.name) {
                    *slot = poll;
                }
            }
        });
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn vote_topic(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        voted: bool,
    ) -> Result<(), FireCoreError> {
        let response = if voted {
            core.vote_topic(self.topic_id).await?
        } else {
            core.unvote_topic(self.topic_id).await?
        };
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let header = session.header_mut();
            header.vote_count = response.vote_count;
            header.can_vote = response.can_vote;
            header.user_voted = voted;
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn accept_solution(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        post_id: u64,
        accepted: bool,
    ) -> Result<(), FireCoreError> {
        if accepted {
            core.accept_solution(post_id).await?;
        } else {
            core.unaccept_solution(post_id).await?;
        }
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub(super) async fn create_bookmark(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        bookmarkable_id: u64,
        bookmarkable_type: String,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError> {
        let bookmark_id = core
            .create_bookmark(
                bookmarkable_id,
                &bookmarkable_type,
                name.as_deref(),
                reminder_at.as_deref(),
                auto_delete_preference,
            )
            .await?;
        let is_topic = bookmarkable_type.eq_ignore_ascii_case("Topic");
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if is_topic {
                let header = session.header_mut();
                header.bookmarked = true;
                header.bookmark_id = Some(bookmark_id);
                header.bookmark_name = name.clone();
                header.bookmark_reminder_at = reminder_at.clone();
            } else if let Some(post) = session.post_mut(bookmarkable_id) {
                post.bookmarked = true;
                post.bookmark_id = Some(bookmark_id);
                post.bookmark_name = name.clone();
                post.bookmark_reminder_at = reminder_at.clone();
            }
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn update_bookmark(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError> {
        core.update_bookmark(
            bookmark_id,
            name.clone(),
            reminder_at.clone(),
            auto_delete_preference,
        )
        .await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if session.header().bookmark_id == Some(bookmark_id) {
                let header = session.header_mut();
                header.bookmark_name = name.clone();
                header.bookmark_reminder_at = reminder_at.clone();
            }
            let post_ids = session
                .raw_stream_ids()
                .iter()
                .copied()
                .filter(|post_id| {
                    session
                        .post(*post_id)
                        .is_some_and(|post| post.bookmark_id == Some(bookmark_id))
                })
                .collect::<Vec<_>>();
            for post_id in post_ids {
                if let Some(post) = session.post_mut(post_id) {
                    post.bookmark_name = name.clone();
                    post.bookmark_reminder_at = reminder_at.clone();
                }
            }
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn delete_bookmark(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        bookmark_id: u64,
    ) -> Result<(), FireCoreError> {
        core.delete_bookmark(bookmark_id).await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if session.header().bookmark_id == Some(bookmark_id) {
                let header = session.header_mut();
                header.bookmarked = false;
                header.bookmark_id = None;
                header.bookmark_name = None;
                header.bookmark_reminder_at = None;
            }
            let post_ids = session
                .raw_stream_ids()
                .iter()
                .copied()
                .filter(|post_id| {
                    session
                        .post(*post_id)
                        .is_some_and(|post| post.bookmark_id == Some(bookmark_id))
                })
                .collect::<Vec<_>>();
            for post_id in post_ids {
                if let Some(post) = session.post_mut(post_id) {
                    post.bookmarked = false;
                    post.bookmark_id = None;
                    post.bookmark_name = None;
                    post.bookmark_reminder_at = None;
                }
            }
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn set_notification_level(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        level: i32,
    ) -> Result<(), FireCoreError> {
        core.set_topic_notification_level(self.topic_id, level)
            .await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.header_mut().details.notification_level = Some(level);
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

    pub(super) async fn update_topic(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        title: String,
        category_id: u64,
        tags: Vec<String>,
    ) -> Result<(), FireCoreError> {
        core.update_topic(TopicUpdateRequest {
            topic_id: self.topic_id,
            title: title.clone(),
            category_id,
            tags: tags.clone(),
        })
        .await?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let header = session.header_mut();
            header.title = title;
            header.category_id = Some(category_id);
            header.tags = tags
                .into_iter()
                .map(|name| fire_models::TopicTag {
                    id: None,
                    name,
                    slug: None,
                })
                .collect();
        });
        self.capture_header(core);
        self.publish(core, false);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }
}
