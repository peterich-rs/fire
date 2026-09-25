impl ActorState {
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

}
