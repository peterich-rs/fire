use tracing::{debug, info, warn};

use super::super::{
    network::{expect_success, FireChallengePresentation},
    FireCore,
};
use super::runtime::{
    apply_full_page, apply_recent_page, ensure_notification_session, normalized_limit,
    notification_cache_scope_key,
};
use super::{DEFAULT_FULL_LIMIT, DEFAULT_RECENT_LIMIT};
use crate::{error::FireCoreError, notification_payloads::parse_notification_list_response_value};
use fire_models::NotificationListResponse;
use serde_json::Value;

impl FireCore {
    pub async fn fetch_recent_notifications(
        &self,
        limit: Option<u32>,
    ) -> Result<NotificationListResponse, FireCoreError> {
        ensure_notification_session(self)?;
        let limit = normalized_limit(limit, DEFAULT_RECENT_LIMIT);
        info!(limit, "fetching recent notifications");
        let cache_scope_key = notification_cache_scope_key("recent", limit, None);

        let traced = self
            .build_json_get_request(
                "fetch recent notifications",
                "/notifications",
                vec![
                    ("recent", "true".to_string()),
                    ("limit", limit.to_string()),
                    ("bump_last_seen_reviewable", "true".to_string()),
                ],
                &[],
            )?
            .with_challenge_presentation(FireChallengePresentation::Background);
        let (trace_id, response) = match self.execute_request(traced).await {
            Ok(response) => response,
            Err(error @ FireCoreError::Network { .. }) => {
                if let Some(cached) = self.read_cached_notification_list(&cache_scope_key)? {
                    warn!("recent notification network fetch failed; returning cached page");
                    let mut runtime = self
                        .notifications
                        .lock()
                        .expect("notification runtime lock poisoned");
                    apply_recent_page(&mut runtime, &cached);
                    return Ok(cached);
                }
                return Err(error);
            }
            Err(error) => return Err(error),
        };
        let response =
            expect_success(self, "fetch recent notifications", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch recent notifications", trace_id, response)
            .await?;
        let page = parse_notification_list_response_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch recent notifications",
                source,
            }
        })?;
        {
            let mut runtime = self
                .notifications
                .lock()
                .expect("notification runtime lock poisoned");
            apply_recent_page(&mut runtime, &page);
        }
        self.write_cached_notification_list(&cache_scope_key, &page);
        debug!(
            notification_count = page.notifications.len(),
            seen_notification_id = ?page.seen_notification_id,
            "recent notifications fetched successfully"
        );
        Ok(page)
    }

    pub async fn fetch_notifications(
        &self,
        limit: Option<u32>,
        offset: Option<u32>,
    ) -> Result<NotificationListResponse, FireCoreError> {
        ensure_notification_session(self)?;
        let limit = normalized_limit(limit, DEFAULT_FULL_LIMIT);
        let offset = offset.filter(|value| *value > 0);
        info!(limit, offset = ?offset, "fetching notifications page");
        let cache_scope_key = notification_cache_scope_key("full", limit, offset);

        let mut query_params = vec![("limit", limit.to_string())];
        if let Some(offset) = offset {
            query_params.push(("offset", offset.to_string()));
        }

        let traced = self
            .build_json_get_request("fetch notifications", "/notifications", query_params, &[])?
            .with_challenge_presentation(FireChallengePresentation::Foreground);
        let (trace_id, response) = match self.execute_request(traced).await {
            Ok(response) => response,
            Err(error @ FireCoreError::Network { .. }) => {
                if let Some(cached) = self.read_cached_notification_list(&cache_scope_key)? {
                    warn!(
                        offset = ?offset,
                        "notification page network fetch failed; returning cached page"
                    );
                    let mut runtime = self
                        .notifications
                        .lock()
                        .expect("notification runtime lock poisoned");
                    apply_full_page(&mut runtime, &cached, offset.unwrap_or(0));
                    return Ok(cached);
                }
                return Err(error);
            }
            Err(error) => return Err(error),
        };
        let response = expect_success(self, "fetch notifications", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch notifications", trace_id, response)
            .await?;
        let page = parse_notification_list_response_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch notifications",
                source,
            }
        })?;
        {
            let mut runtime = self
                .notifications
                .lock()
                .expect("notification runtime lock poisoned");
            apply_full_page(&mut runtime, &page, offset.unwrap_or(0));
        }
        self.write_cached_notification_list(&cache_scope_key, &page);
        debug!(
            notification_count = page.notifications.len(),
            next_offset = ?page.next_offset,
            total_rows_notifications = page.total_rows_notifications,
            "notifications page fetched successfully"
        );
        Ok(page)
    }

    fn read_cached_notification_list(
        &self,
        scope_key: &str,
    ) -> Result<Option<NotificationListResponse>, FireCoreError> {
        let auth_scope_hash = self.current_auth_scope_hash();
        let payload = {
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            store.notification_list_cache_read(&auth_scope_hash, scope_key)?
        };

        let Some(payload) = payload else {
            return Ok(None);
        };

        let mut cached: NotificationListResponse =
            serde_json::from_str(&payload).map_err(|source| {
                FireCoreError::ResponseDeserialize {
                    operation: "cached notification list",
                    source,
                }
            })?;
        cached.is_cached = true;
        Ok(Some(cached))
    }

    fn write_cached_notification_list(&self, scope_key: &str, response: &NotificationListResponse) {
        let auth_scope_hash = self.current_auth_scope_hash();
        let mut cached = response.clone();
        cached.is_cached = false;
        let payload = match serde_json::to_string(&cached) {
            Ok(payload) => payload,
            Err(error) => {
                warn!(error = %error, "failed to serialize notification list cache payload");
                return;
            }
        };
        let result = self
            .shared_store
            .lock()
            .expect("shared store mutex poisoned")
            .notification_list_cache_write(&auth_scope_hash, scope_key, &payload);
        if let Err(error) = result {
            warn!(error = %error, "failed to write notification list cache");
        }
    }
}
