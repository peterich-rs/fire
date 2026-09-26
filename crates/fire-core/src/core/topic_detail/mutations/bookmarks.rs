impl ActorState {
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
        self.publish(core);
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
        self.publish(core);
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
        self.publish(core);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

}
