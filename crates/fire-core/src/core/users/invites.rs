impl FireCore {
    pub async fn fetch_pending_invites(
        &self,
        username: &str,
    ) -> Result<Vec<InviteLink>, FireCoreError> {
        info!(username, "fetching pending invites");
        let path = format!("/u/{username}/invited/pending");
        let traced = self.build_json_get_request("fetch pending invites", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch pending invites", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch pending invites", trace_id, response)
            .await?;
        let invites = parse_invite_links_value(value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "fetch pending invites",
                source,
            }
        })?;
        info!(
            username,
            invite_count = invites.len(),
            "pending invites fetched successfully"
        );
        Ok(invites)
    }

    pub async fn create_invite_link(
        &self,
        input: InviteCreateRequest,
    ) -> Result<InviteLink, FireCoreError> {
        info!(
            max_redemptions_allowed = input.max_redemptions_allowed,
            has_expires_at = input.expires_at.is_some(),
            has_description = input.description.is_some(),
            has_email = input.email.is_some(),
            "creating invite link"
        );

        let body = json!({
            "max_redemptions_allowed": input.max_redemptions_allowed,
            "expires_at": input.expires_at,
            "description": input.description,
            "email": input.email,
        });
        let body =
            serde_json::to_vec(&body).map_err(|source| FireCoreError::ResponseDeserialize {
                operation: "create invite link",
                source,
            })?;

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create invite link", || {
                self.build_api_request_with_body(
                    "create invite link",
                    Method::POST,
                    "/invites",
                    Some("application/json; charset=utf-8"),
                    openwire::RequestBody::from(body.clone()),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create invite link", trace_id, response).await?;
        let value: Value = self
            .read_response_json("create invite link", trace_id, response)
            .await?;
        parse_invite_link_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "create invite link",
            source,
        })
    }

}
