impl ActorState {
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
        self.publish(core);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }

}
