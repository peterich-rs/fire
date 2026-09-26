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
        self.publish(core);
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
                self.publish(core);
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
        self.publish(core);
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
        self.publish(core);
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

}
