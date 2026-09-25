impl FireCore {
    pub async fn fetch_user_profile(&self, username: &str) -> Result<UserProfile, FireCoreError> {
        info!(username, "fetching user profile");
        let path = format!("/u/{username}.json");
        let traced = self.build_json_get_request("fetch user profile", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch user profile", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user profile", trace_id, response)
            .await?;
        let profile = parse_user_profile_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user profile",
                source,
            }
        })?;
        info!(
            username,
            user_id = profile.id,
            "user profile fetched successfully"
        );
        Ok(profile)
    }

    pub async fn fetch_user_summary(
        &self,
        username: &str,
    ) -> Result<UserSummaryResponse, FireCoreError> {
        info!(username, "fetching user summary");
        let path = format!("/u/{username}/summary.json");
        let traced = self.build_json_get_request("fetch user summary", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch user summary", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user summary", trace_id, response)
            .await?;
        let summary = parse_user_summary_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user summary",
                source,
            }
        })?;
        info!(
            username,
            badge_count = summary.badges.len(),
            top_topic_count = summary.top_topics.len(),
            "user summary fetched successfully"
        );
        Ok(summary)
    }

}
