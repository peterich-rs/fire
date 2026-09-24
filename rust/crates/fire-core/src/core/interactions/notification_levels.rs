use tracing::info;

use super::super::{network::expect_success, FireCore};
use crate::error::FireCoreError;
use http::Method;

impl FireCore {
    pub async fn set_topic_notification_level(
        &self,
        topic_id: u64,
        notification_level: i32,
    ) -> Result<(), FireCoreError> {
        info!(
            topic_id,
            notification_level, "setting topic notification level"
        );
        let path = format!("/t/{topic_id}/notifications");
        let fields = vec![("notification_level", notification_level.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("set topic notification level", || {
                self.build_form_request(
                    "set topic notification level",
                    Method::POST,
                    &path,
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response =
            expect_success(self, "set topic notification level", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn set_category_notification_level(
        &self,
        category_id: u64,
        notification_level: i32,
    ) -> Result<(), FireCoreError> {
        info!(
            category_id,
            notification_level, "setting category notification level"
        );
        let path = format!("/category/{category_id}/notifications");
        let fields = vec![("notification_level", notification_level.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("set category notification level", || {
                self.build_form_request(
                    "set category notification level",
                    Method::POST,
                    &path,
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response =
            expect_success(self, "set category notification level", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
