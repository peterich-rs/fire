use std::{
    io,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use fire_models::{
    Poll, PostReactionUpdate, PostUpdateRequest, TopicPost, TopicReplyRequest, TopicTimingsRequest,
    TopicUpdateRequest, VoteResponse, VotedUser,
};
use http::{Method, Response};
use serde_json::json;
use serde_json::Value;
use tracing::{info, warn};
use url::form_urlencoded::byte_serialize;

use super::{network::expect_success, rate_limit, FireCore};
use crate::{
    error::FireCoreError,
    topic_payloads::{
        parse_poll_response_value, parse_post_reaction_update_value, parse_topic_post_value,
        parse_vote_response_value, parse_voted_users_value,
    },
};

#[derive(Default)]
pub(crate) struct FireTopicTimingRuntime {
    cooldown_until: Option<Instant>,
}

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

    pub async fn create_reply(&self, input: TopicReplyRequest) -> Result<TopicPost, FireCoreError> {
        info!(
            topic_id = input.topic_id,
            reply_to = ?input.reply_to_post_number,
            raw_len = input.raw.len(),
            "creating reply"
        );

        let mut fields = vec![("topic_id", input.topic_id.to_string()), ("raw", input.raw)];
        if let Some(reply_to_post_number) = input.reply_to_post_number {
            fields.push(("reply_to_post_number", reply_to_post_number.to_string()));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("create reply", || {
                self.build_form_request(
                    "create reply",
                    Method::POST,
                    "/posts.json",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "create reply", trace_id, response).await?;
        let value: Value = self
            .read_response_json("create reply", trace_id, response)
            .await?;
        let result = parse_create_reply_response(value);
        match &result {
            Ok(post) => info!(
                topic_id = input.topic_id,
                post_id = post.id,
                post_number = post.post_number,
                "reply created successfully"
            ),
            Err(e) => warn!(
                topic_id = input.topic_id,
                error = %e,
                "reply creation failed during response parsing"
            ),
        }
        result
    }

    pub async fn fetch_post(&self, post_id: u64) -> Result<TopicPost, FireCoreError> {
        info!(post_id, "fetching post");
        let path = format!("/posts/{post_id}.json");
        let traced = self.build_json_get_request("fetch post", &path, vec![], &[])?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch post", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch post", trace_id, response)
            .await?;
        parse_topic_post_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch post",
            source,
        })
    }

    pub async fn update_post(&self, input: PostUpdateRequest) -> Result<TopicPost, FireCoreError> {
        info!(
            post_id = input.post_id,
            raw_len = input.raw.len(),
            has_edit_reason = input.edit_reason.is_some(),
            "updating post"
        );

        let path = format!("/posts/{}.json", input.post_id);
        let mut fields = vec![("post[raw]", input.raw)];
        if let Some(edit_reason) = input.edit_reason.filter(|value| !value.trim().is_empty()) {
            fields.push(("post[edit_reason]", edit_reason));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("update post", || {
                self.build_form_request("update post", Method::PUT, &path, fields.clone(), true)
            })
            .await?;
        let response = expect_success(self, "update post", trace_id, response).await?;
        let value: Value = self
            .read_response_json("update post", trace_id, response)
            .await?;
        parse_topic_post_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "update post",
            source,
        })
    }

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

    pub async fn vote_poll(
        &self,
        post_id: u64,
        poll_name: &str,
        options: Vec<String>,
    ) -> Result<Poll, FireCoreError> {
        info!(
            post_id,
            poll_name,
            options_count = options.len(),
            "voting in poll"
        );
        let mut fields = vec![
            ("post_id", post_id.to_string()),
            ("poll_name", poll_name.to_string()),
        ];
        for option in options.into_iter().filter(|value| !value.trim().is_empty()) {
            fields.push(("options[]", option));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("vote poll", || {
                self.build_form_request(
                    "vote poll",
                    Method::PUT,
                    "/polls/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "vote poll", trace_id, response).await?;
        let value: Value = self
            .read_response_json("vote poll", trace_id, response)
            .await?;
        parse_poll_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "vote poll",
            source,
        })
    }

    pub async fn unvote_poll(&self, post_id: u64, poll_name: &str) -> Result<Poll, FireCoreError> {
        info!(post_id, poll_name, "removing poll vote");
        let fields = vec![
            ("post_id", post_id.to_string()),
            ("poll_name", poll_name.to_string()),
        ];

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unvote poll", || {
                self.build_form_request(
                    "unvote poll",
                    Method::DELETE,
                    "/polls/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "unvote poll", trace_id, response).await?;
        let value: Value = self
            .read_response_json("unvote poll", trace_id, response)
            .await?;
        parse_poll_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "unvote poll",
            source,
        })
    }

    pub async fn vote_topic(&self, topic_id: u64) -> Result<VoteResponse, FireCoreError> {
        info!(topic_id, "voting topic");
        let fields = vec![("topic_id", topic_id.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("vote topic", || {
                self.build_form_request(
                    "vote topic",
                    Method::POST,
                    "/voting/vote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "vote topic", trace_id, response).await?;
        let value: Value = self
            .read_response_json("vote topic", trace_id, response)
            .await?;
        parse_vote_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "vote topic",
            source,
        })
    }

    pub async fn unvote_topic(&self, topic_id: u64) -> Result<VoteResponse, FireCoreError> {
        info!(topic_id, "removing topic vote");
        let fields = vec![("topic_id", topic_id.to_string())];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unvote topic", || {
                self.build_form_request(
                    "unvote topic",
                    Method::POST,
                    "/voting/unvote",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "unvote topic", trace_id, response).await?;
        let value: Value = self
            .read_response_json("unvote topic", trace_id, response)
            .await?;
        parse_vote_response_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "unvote topic",
            source,
        })
    }

    pub async fn fetch_topic_voters(&self, topic_id: u64) -> Result<Vec<VotedUser>, FireCoreError> {
        info!(topic_id, "fetching topic voters");
        let traced = self.build_json_get_request(
            "fetch topic voters",
            "/voting/who",
            vec![("topic_id", topic_id.to_string())],
            &[],
        )?;
        let (trace_id, response) = self.execute_request(traced).await?;
        let response = expect_success(self, "fetch topic voters", trace_id, response).await?;
        let value: Value = self
            .read_response_json("fetch topic voters", trace_id, response)
            .await?;
        parse_voted_users_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
            operation: "fetch topic voters",
            source,
        })
    }

    pub async fn like_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        info!(post_id, "liking post");

        let fields = vec![
            ("id", post_id.to_string()),
            ("post_action_type_id", "2".to_string()),
        ];
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("like post", || {
                self.build_form_request(
                    "like post",
                    Method::POST,
                    "/post_actions",
                    fields.clone(),
                    true,
                )
            })
            .await?;
        let response = expect_success(self, "like post", trace_id, response).await?;
        let update = self
            .read_optional_post_reaction_update("like post", trace_id, response)
            .await?;
        info!(
            post_id,
            has_update = update.is_some(),
            "post liked successfully"
        );
        Ok(update)
    }

    pub async fn unlike_post(
        &self,
        post_id: u64,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        info!(post_id, "unliking post");

        let path = format!("/post_actions/{post_id}?post_action_type_id=2");
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("unlike post", || {
                self.build_api_request("unlike post", Method::DELETE, &path, true)
            })
            .await?;
        let response = expect_success(self, "unlike post", trace_id, response).await?;
        let update = self
            .read_optional_post_reaction_update("unlike post", trace_id, response)
            .await?;
        info!(
            post_id,
            has_update = update.is_some(),
            "post unliked successfully"
        );
        Ok(update)
    }

    pub async fn toggle_post_reaction(
        &self,
        post_id: u64,
        reaction_id: String,
    ) -> Result<PostReactionUpdate, FireCoreError> {
        info!(post_id, reaction_id = %reaction_id, "toggling post reaction");

        let reaction_id = encode_path_segment(&reaction_id);
        let path = format!(
            "/discourse-reactions/posts/{post_id}/custom-reactions/{reaction_id}/toggle.json"
        );
        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("toggle post reaction", || {
                self.build_api_request("toggle post reaction", Method::PUT, &path, true)
            })
            .await?;
        let response = expect_success(self, "toggle post reaction", trace_id, response).await?;
        let value: Value = self
            .read_response_json("toggle post reaction", trace_id, response)
            .await?;
        let result = parse_toggle_reaction_response(value);
        match &result {
            Ok(update) => info!(
                post_id,
                reactions_count = update.reactions.len(),
                has_current = update.current_user_reaction.is_some(),
                "post reaction toggled successfully"
            ),
            Err(e) => warn!(
                post_id,
                error = %e,
                "post reaction toggle failed during response parsing"
            ),
        }
        result
    }

    pub async fn report_topic_timings(
        &self,
        input: TopicTimingsRequest,
    ) -> Result<bool, FireCoreError> {
        info!(
            topic_id = input.topic_id,
            topic_time_ms = input.topic_time_ms,
            timings_count = input.timings.len(),
            "reporting topic timings"
        );
        if is_timing_rate_limited(&self.topic_timing) {
            info!(
                topic_id = input.topic_id,
                "topic timings skipped: rate limit cooldown active"
            );
            return Ok(false);
        }

        let mut fields = vec![
            ("topic_id".to_string(), input.topic_id.to_string()),
            ("topic_time".to_string(), input.topic_time_ms.to_string()),
        ];
        for timing in input.timings {
            fields.push((
                format!("timings[{}]", timing.post_number),
                timing.milliseconds.to_string(),
            ));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("report topic timings", || {
                self.build_form_request_with_headers(
                    "report topic timings",
                    Method::POST,
                    "/topics/timings",
                    fields.clone(),
                    vec![
                        ("X-SILENCE-LOGGER", "true".to_string()),
                        ("Discourse-Background", "true".to_string()),
                    ],
                    true,
                )
            })
            .await?;
        let response = match expect_success(self, "report topic timings", trace_id, response).await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status: 429, body, ..
            }) => {
                let cooldown = rate_limit::parse_rate_limit_cooldown(&body)
                    .unwrap_or(rate_limit::RATE_LIMIT_FALLBACK_COOLDOWN);
                apply_timing_rate_limit(&self.topic_timing, cooldown);
                info!(
                    topic_id = input.topic_id,
                    cooldown_ms = cooldown.as_millis() as u64,
                    "topic timings rate limited; deferring subsequent reports"
                );
                return Ok(false);
            }
            Err(error) => return Err(error),
        };
        let _ = self.read_response_text(trace_id, response).await?;
        info!(
            topic_id = input.topic_id,
            "topic timings reported successfully"
        );
        Ok(true)
    }

    async fn read_optional_post_reaction_update(
        &self,
        operation: &'static str,
        trace_id: u64,
        response: Response<openwire::ResponseBody>,
    ) -> Result<Option<PostReactionUpdate>, FireCoreError> {
        let body = self.read_response_text(trace_id, response).await?;
        let trimmed = body.trim();
        if trimmed.is_empty() {
            return Ok(None);
        }

        let value: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(error) => {
                warn!(
                    operation,
                    trace_id,
                    error = %error,
                    body_prefix = %trimmed.chars().take(200).collect::<String>(),
                    "post action response did not contain parseable JSON"
                );
                return Ok(None);
            }
        };

        parse_optional_post_reaction_update(operation, value)
    }
}

fn parse_bookmark_id(operation: &'static str, value: Value) -> Result<u64, FireCoreError> {
    let Value::Object(object) = value else {
        return Err(FireCoreError::ResponseDeserialize {
            operation,
            source: serde_json::Error::io(io::Error::new(
                io::ErrorKind::InvalidData,
                "bookmark response root was not an object",
            )),
        });
    };
    let bookmark_id = object.get("id").and_then(|value| match value {
        Value::Number(value) => value.as_u64(),
        Value::String(value) => value.parse::<u64>().ok(),
        Value::Bool(value) => Some(u64::from(*value)),
        Value::Array(_) | Value::Object(_) | Value::Null => None,
    });
    bookmark_id.ok_or_else(|| FireCoreError::ResponseDeserialize {
        operation,
        source: serde_json::Error::io(io::Error::new(
            io::ErrorKind::InvalidData,
            "bookmark response did not contain a valid id",
        )),
    })
}

fn is_timing_rate_limited(runtime: &Arc<Mutex<FireTopicTimingRuntime>>) -> bool {
    let mut runtime = runtime.lock().expect("topic timing runtime lock poisoned");
    if let Some(cooldown_until) = runtime.cooldown_until {
        if cooldown_until > Instant::now() {
            return true;
        }
        runtime.cooldown_until = None;
    }
    false
}

fn apply_timing_rate_limit(runtime: &Arc<Mutex<FireTopicTimingRuntime>>, cooldown: Duration) {
    let mut runtime = runtime.lock().expect("topic timing runtime lock poisoned");
    runtime.cooldown_until = Some(Instant::now() + cooldown);
}

fn encode_path_segment(value: &str) -> String {
    byte_serialize(value.as_bytes()).collect()
}

fn parse_create_reply_response(value: Value) -> Result<TopicPost, FireCoreError> {
    let Value::Object(mut object) = value else {
        return Err(invalid_response(
            "create reply",
            "response root was not a JSON object",
        ));
    };

    if object
        .get("action")
        .and_then(Value::as_str)
        .is_some_and(|action| action == "enqueued")
    {
        return Err(FireCoreError::PostEnqueued {
            pending_count: pending_count_from(object.get("pending_count")),
        });
    }

    if let Some(post_value) = object.remove("post") {
        return parse_topic_post_value(post_value).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    if object.contains_key("id")
        || object.contains_key("post_number")
        || object.contains_key("cooked")
    {
        return parse_topic_post_value(Value::Object(object)).map_err(|source| {
            FireCoreError::ResponseDeserialize {
                operation: "create reply",
                source,
            }
        });
    }

    Err(invalid_response(
        "create reply",
        "response object did not contain a post payload",
    ))
}

fn parse_toggle_reaction_response(value: Value) -> Result<PostReactionUpdate, FireCoreError> {
    let Value::Object(object) = &value else {
        return Err(invalid_response(
            "toggle post reaction",
            "response root was not a JSON object",
        ));
    };

    if !object.contains_key("reactions") && !object.contains_key("current_user_reaction") {
        return Err(invalid_response(
            "toggle post reaction",
            "response object did not contain reaction fields",
        ));
    }

    parse_post_reaction_update_value(value).map_err(|source| FireCoreError::ResponseDeserialize {
        operation: "toggle post reaction",
        source,
    })
}

fn parse_optional_post_reaction_update(
    operation: &'static str,
    value: Value,
) -> Result<Option<PostReactionUpdate>, FireCoreError> {
    let Value::Object(object) = &value else {
        return Ok(None);
    };

    if !object.contains_key("reactions") && !object.contains_key("current_user_reaction") {
        return Ok(None);
    }

    parse_post_reaction_update_value(value)
        .map(Some)
        .map_err(|source| FireCoreError::ResponseDeserialize { operation, source })
}

fn pending_count_from(value: Option<&Value>) -> u32 {
    match value {
        Some(Value::Number(value)) => value
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or_default(),
        Some(Value::String(value)) => value.parse::<u32>().unwrap_or_default(),
        Some(Value::Bool(value)) => u32::from(*value),
        _ => 0,
    }
}

fn invalid_response(operation: &'static str, details: &'static str) -> FireCoreError {
    FireCoreError::ResponseDeserialize {
        operation,
        source: serde_json::Error::io(io::Error::new(io::ErrorKind::InvalidData, details)),
    }
}
