impl FireCore {
    pub async fn create_topic(&self, input: TopicCreateRequest) -> Result<u64, FireCoreError> {
        info!(
            category_id = input.category_id,
            tags_count = input.tags.len(),
            title_len = input.title.len(),
            raw_len = input.raw.len(),
            "creating topic"
        );

        let mut fields = vec![
            ("title", input.title),
            ("raw", input.raw),
            ("category", input.category_id.to_string()),
            ("archetype", "regular".to_string()),
        ];
        for tag in input
            .tags
            .into_iter()
            .filter(|value| !value.trim().is_empty())
        {
            fields.push(("tags[]", tag));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create topic", || {
                self.build_form_request(
                    "create topic",
                    Method::POST,
                    "/posts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create topic", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("create topic", trace_id, response)
            .await?;
        let result = parse_create_topic_response(raw);
        match &result {
            Ok(topic_id) => info!(topic_id, "topic created successfully"),
            Err(error) => warn!(error = %error, "topic creation failed during response parsing"),
        }
        result
    }

}
