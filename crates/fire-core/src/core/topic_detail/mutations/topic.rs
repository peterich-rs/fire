impl ActorState {
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
        self.publish(core);
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
        self.publish(core);
        self.load_http(core, tx, None, false, false, false, false)
            .await;
        Ok(())
    }
}
