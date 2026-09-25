use fire_models::NotificationState;
use http::Method;
use openwire::RequestBody;
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::runtime::{
    ensure_notification_session, mark_all_notifications_read_locked, mark_notification_read_locked,
    seed_notification_counters_if_missing,
};
use crate::error::FireCoreError;

impl FireCore {
    pub async fn mark_notification_read(
        &self,
        notification_id: u64,
    ) -> Result<NotificationState, FireCoreError> {
        ensure_notification_session(self)?;
        let snapshot = self.snapshot();
        info!(notification_id, "marking notification as read");
        let request_body = format!(r#"{{"id":{notification_id}}}"#);

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("mark notification read", || {
                self.build_api_request_with_body(
                    "mark notification read",
                    Method::PUT,
                    "/notifications/mark-read",
                    Some("application/json"),
                    RequestBody::from(request_body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "mark notification read", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        {
            let mut runtime = self
                .notifications
                .lock()
                .expect("notification runtime lock poisoned");
            seed_notification_counters_if_missing(&mut runtime, &snapshot);
            mark_notification_read_locked(&mut runtime, notification_id);
        }
        Ok(self.notification_state())
    }

    pub async fn mark_all_notifications_read(&self) -> Result<NotificationState, FireCoreError> {
        ensure_notification_session(self)?;
        let snapshot = self.snapshot();
        info!("marking all notifications as read");

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("mark all notifications read", || {
                self.build_api_request(
                    "mark all notifications read",
                    Method::PUT,
                    "/notifications/mark-read",
                    true,
                )
            })
            .await?;
        let response =
            expect_success(self, "mark all notifications read", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        {
            let mut runtime = self
                .notifications
                .lock()
                .expect("notification runtime lock poisoned");
            seed_notification_counters_if_missing(&mut runtime, &snapshot);
            mark_all_notifications_read_locked(&mut runtime);
        }
        Ok(self.notification_state())
    }
}
