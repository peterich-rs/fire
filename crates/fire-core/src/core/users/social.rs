impl FireCore {
    pub async fn fetch_following(&self, username: &str) -> Result<Vec<FollowUser>, FireCoreError> {
        self.fetch_follow_users(username, "following").await
    }

    pub async fn fetch_followers(&self, username: &str) -> Result<Vec<FollowUser>, FireCoreError> {
        self.fetch_follow_users(username, "followers").await
    }

    pub async fn follow_user(&self, username: &str) -> Result<(), FireCoreError> {
        info!(username, "following user");
        let path = format!("/follow/{username}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("follow user", || {
                self.build_api_request("follow user", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "follow user", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn unfollow_user(&self, username: &str) -> Result<(), FireCoreError> {
        info!(username, "unfollowing user");
        let path = format!("/follow/{username}");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unfollow user", || {
                self.build_api_request("unfollow user", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "unfollow user", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

    pub async fn set_user_notification_level(
        &self,
        username: &str,
        notification_level: &str,
        expiring_at: Option<&str>,
    ) -> Result<(), FireCoreError> {
        let notification_level = normalized_user_notification_level(notification_level)?;
        info!(
            username,
            notification_level,
            has_expiring_at = expiring_at.is_some(),
            "setting user notification level"
        );

        let path = format!("/u/{username}/notification_level.json");
        let mut body = serde_json::Map::new();
        body.insert(
            "notification_level".to_string(),
            Value::String(notification_level.to_string()),
        );
        if let Some(expiring_at) = expiring_at {
            body.insert(
                "expiring_at".to_string(),
                Value::String(expiring_at.to_string()),
            );
        }
        let body = serde_json::to_vec(&Value::Object(body)).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "set user notification level",
                source,
            }
        })?;

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("set user notification level", || {
                self.build_api_request_with_body(
                    "set user notification level",
                    Method::PUT,
                    &path,
                    Some("application/json; charset=utf-8"),
                    RequestBody::from(body.clone()),
                    true,
                )
            })
            .await?;
        let response =
            expect_success(self, "set user notification level", trace_id, response).await?;
        let _ = self.read_response_text(trace_id, response).await?;
        Ok(())
    }

}
