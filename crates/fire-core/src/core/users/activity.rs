impl FireCore {
    pub async fn fetch_user_actions(
        &self,
        username: &str,
        offset: Option<u32>,
        filter: Option<&str>,
    ) -> Result<Vec<UserAction>, FireCoreError> {
        info!(username, ?offset, ?filter, "fetching user actions");
        let mut params: Vec<(&str, String)> = vec![("username", username.to_string())];
        if let Some(offset) = offset {
            params.push(("offset", offset.to_string()));
        }
        if let Some(filter) = filter {
            params.push(("filter", filter.to_string()));
        }
        let traced =
            self.build_json_get_request("fetch user actions", "/user_actions.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch user actions", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user actions", trace_id, response)
            .await?;
        let actions = parse_user_actions_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user actions",
                source,
            }
        })?;
        info!(
            username,
            action_count = actions.len(),
            "user actions fetched successfully"
        );
        Ok(actions)
    }

    pub async fn fetch_user_reactions(
        &self,
        username: &str,
        before_reaction_user_id: Option<u64>,
    ) -> Result<UserReactionsResponse, FireCoreError> {
        info!(
            username,
            ?before_reaction_user_id,
            "fetching user reactions"
        );
        let mut params: Vec<(&str, String)> = vec![("username", username.to_string())];
        if let Some(before_reaction_user_id) = before_reaction_user_id {
            params.push((
                "before_reaction_user_id",
                before_reaction_user_id.to_string(),
            ));
        }
        let traced = self.build_json_get_request(
            "fetch user reactions",
            "/discourse-reactions/posts/reactions.json",
            params,
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch user reactions", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch user reactions", trace_id, response)
            .await?;
        let result = parse_user_reactions_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch user reactions",
                source,
            }
        })?;
        info!(
            username,
            reaction_count = result.reactions.len(),
            "user reactions fetched successfully"
        );
        Ok(result)
    }

    async fn fetch_follow_users(
        &self,
        username: &str,
        kind: &'static str,
    ) -> Result<Vec<FollowUser>, FireCoreError> {
        info!(username, kind, "fetching follow users");
        let path = format!("/u/{username}/follow/{kind}");
        let traced = self.build_json_get_request("fetch follow users", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch follow users", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch follow users", trace_id, response)
            .await?;
        let users = parse_follow_users_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch follow users",
                source,
            }
        })?;
        info!(
            username,
            kind,
            user_count = users.len(),
            "follow users fetched successfully"
        );
        Ok(users)
    }
}
