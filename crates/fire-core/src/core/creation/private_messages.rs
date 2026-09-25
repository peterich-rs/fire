impl FireCore {
    pub async fn create_private_message(
        &self,
        input: PrivateMessageCreateRequest,
    ) -> Result<u64, FireCoreError> {
        info!(
            recipients_count = input.target_recipients.len(),
            title_len = input.title.len(),
            raw_len = input.raw.len(),
            "creating private message"
        );

        let mut fields = vec![
            ("title", input.title),
            ("raw", input.raw),
            ("archetype", "private_message".to_string()),
            ("target_recipients", input.target_recipients.join(",")),
        ];
        fields.retain(|(_, value)| !value.trim().is_empty());

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create private message", || {
                self.build_form_request(
                    "create private message",
                    Method::POST,
                    "/posts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create private message", trace_id, response).await?;
        let raw: Value = self
            .read_response_json("create private message", trace_id, response)
            .await?;
        let result = parse_create_topic_response(raw);
        match &result {
            Ok(topic_id) => info!(topic_id, "private message created successfully"),
            Err(error) => warn!(
                error = %error,
                "private message creation failed during response parsing"
            ),
        }
        result
    }
}
