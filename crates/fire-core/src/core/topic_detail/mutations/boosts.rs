impl ActorState {
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

}
