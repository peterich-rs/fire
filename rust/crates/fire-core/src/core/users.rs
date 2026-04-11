use fire_models::{
    Badge, FollowUser, InviteCreateRequest, InviteLink, TopicListResponse, UserAction, UserProfile,
    UserSummaryResponse,
};
use http::Method;
use serde_json::{json, Value};
use tracing::info;

use super::{network::expect_success, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::RawTopicListResponse,
    user_payloads::{
        parse_badge_value, parse_follow_users_value, parse_invite_link_value,
        parse_invite_links_value, parse_user_actions_value, parse_user_profile_value,
        parse_user_summary_value,
    },
};

impl FireCore {
    pub async fn fetch_read_history(
        &self,
        page: Option<u32>,
    ) -> Result<TopicListResponse, FireCoreError> {
        info!(?page, "fetching read history");
        let mut params = Vec::new();
        if let Some(page) = page.filter(|page| *page > 0) {
            params.push(("page", page.to_string()));
        }
        let traced =
            self.build_json_get_request("fetch read history", "/read.json", params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch read history", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch read history", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        info!(
            topic_count = result.topics.len(),
            has_more = result.more_topics_url.is_some(),
            "read history fetched successfully"
        );
        Ok(result)
    }

    pub async fn fetch_bookmarks(
        &self,
        username: &str,
        page: Option<u32>,
    ) -> Result<TopicListResponse, FireCoreError> {
        info!(username, ?page, "fetching user bookmarks");
        let path = format!("/u/{username}/bookmarks.json");
        let mut params = Vec::new();
        if let Some(page) = page {
            if page > 0 {
                params.push(("page", page.to_string()));
            }
        }
        let traced = self.build_json_get_request("fetch bookmarks", &path, params, &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch bookmarks", trace_id, response).await?;
        let raw: RawTopicListResponse = self
            .read_response_json("fetch bookmarks", trace_id, response)
            .await?;
        let result: TopicListResponse = raw.into();
        info!(
            username,
            topic_count = result.topics.len(),
            has_more = result.more_topics_url.is_some(),
            "user bookmarks fetched successfully"
        );
        Ok(result)
    }

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

    pub async fn fetch_badge_detail(&self, badge_id: u64) -> Result<Badge, FireCoreError> {
        info!(badge_id, "fetching badge detail");
        let path = format!("/badges/{badge_id}.json");
        let traced = self.build_json_get_request("fetch badge detail", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch badge detail", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch badge detail", trace_id, response)
            .await?;
        let badge =
            parse_badge_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
                operation: "fetch badge detail",
                source,
            })?;
        info!(badge_id = badge.id, badge_name = %badge.name, "badge detail fetched successfully");
        Ok(badge)
    }

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
