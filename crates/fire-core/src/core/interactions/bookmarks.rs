use serde_json::{json, Value};
use tracing::info;

use super::super::{network::expect_success, FireCore};
use super::parse::parse_bookmark_id;
use crate::error::FireCoreError;
use http::Method;

impl FireCore {
    pub async fn create_bookmark(
        &self,
        bookmarkable_id: u64,
        bookmarkable_type: &str,
        name: Option<&str>,
        reminder_at: Option<&str>,
        auto_delete_preference: Option<i32>,
    ) -> Result<u64, FireCoreError> {
        info!(
            bookmarkable_id,
            bookmarkable_type,
            has_name = name.is_some(),
            has_reminder = reminder_at.is_some(),
            "creating bookmark"
        );

        let mut fields = vec![
            ("bookmarkable_id", bookmarkable_id.to_string()),
            ("bookmarkable_type", bookmarkable_type.to_string()),
        ];
        if let Some(name) = name.filter(|value| !value.trim().is_empty()) {
            fields.push(("name", name.to_string()));
        }
        if let Some(reminder_at) = reminder_at.filter(|value| !value.trim().is_empty()) {
            fields.push(("reminder_at", reminder_at.to_string()));
        }
        if let Some(auto_delete_preference) = auto_delete_preference {
            fields.push(("auto_delete_preference", auto_delete_preference.to_string()));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create bookmark", || {
                self.build_form_request(
                    "create bookmark",
                    Method::POST,
                    "/bookmarks.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create bookmark", trace_id, response).await?;
        let value: Value = self
            .read_response_json("create bookmark", trace_id, response)
            .await?;
        parse_bookmark_id("create bookmark", value)
    }

    pub async fn update_bookmark(
        &self,
        bookmark_id: u64,
        name: Option<String>,
        reminder_at: Option<String>,
        auto_delete_preference: Option<i32>,
    ) -> Result<(), FireCoreError> {
        info!(
            bookmark_id,
            has_name = name.is_some(),
            has_reminder = reminder_at.is_some(),
            "updating bookmark"
        );

        let path = format!("/bookmarks/{bookmark_id}.json");
        let body = json!({
            "name": name,
            "reminder_at": reminder_at,
            "auto_delete_preference": auto_delete_preference,
        });
        let body =
            serde_json::to_vec(&body).map_err(|source| FireCoreError::ResponseDeserialize {
                operation: "update bookmark",
                source,
            })?;
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("update bookmark", || {
                self.build_api_request_with_body(
                    "update bookmark",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    openwire::RequestBody::from(body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "update bookmark", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn delete_bookmark(&self, bookmark_id: u64) -> Result<(), FireCoreError> {
        info!(bookmark_id, "deleting bookmark");
        let path = format!("/bookmarks/{bookmark_id}.json");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("delete bookmark", || {
                self.build_api_request("delete bookmark", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "delete bookmark", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }
}
