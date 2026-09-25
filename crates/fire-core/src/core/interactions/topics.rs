use fire_models::TopicUpdateRequest;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use crate::error::FireCoreError;
use http::Method;

impl FireCore {
    pub async fn update_topic(&self, input: TopicUpdateRequest) -> Result<(), FireCoreError> {
        info!(
            topic_id = input.topic_id,
            category_id = input.category_id,
            tags_count = input.tags.len(),
            title_len = input.title.len(),
            "updating topic"
        );

        let path = format!("/t/-/{}.json", input.topic_id);
        let mut fields = vec![
            ("title", input.title),
            ("category_id", input.category_id.to_string()),
        ];
        for tag in input
            .tags
            .into_iter()
            .filter(|value| !value.trim().is_empty())
        {
            fields.push(("tags[]", tag));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("update topic", || {
                self.build_form_request("update topic", Method::PUT, &path, fields.clone(), true)
            })
            .await?;
        let response = expect_success(self, "update topic", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
