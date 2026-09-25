use fire_models::{Poll, PollOption, VoteResponse, VotedUser};
use serde::Deserialize;
use serde_json::Value;

use super::deser::{
    deserialize_default_sequence, deserialize_default_string, deserialize_default_u32,
    deserialize_default_u64,
};
use crate::json_helpers::{
    boolean, integer_i32, integer_u32, integer_u64, invalid_json, scalar_string,
};
use crate::plain_text_from_html;

#[derive(Debug, Default, Deserialize)]
pub(super) struct RawPollOption {
    #[serde(default, deserialize_with = "deserialize_default_string")]
    id: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    html: String,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    votes: u32,
}

impl From<RawPollOption> for PollOption {
    fn from(value: RawPollOption) -> Self {
        let plain_text = plain_text_from_html(&value.html).trim().to_string();
        Self {
            id: value.id,
            html: value.html,
            plain_text,
            votes: value.votes,
        }
    }
}

#[derive(Debug, Default, Deserialize)]
pub(super) struct RawPoll {
    #[serde(default, deserialize_with = "deserialize_default_u64")]
    id: u64,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    name: String,
    #[serde(
        default,
        rename = "type",
        deserialize_with = "deserialize_default_string"
    )]
    kind: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    status: String,
    #[serde(default, deserialize_with = "deserialize_default_string")]
    results: String,
    #[serde(default, deserialize_with = "deserialize_default_sequence")]
    options: Vec<RawPollOption>,
    #[serde(default, deserialize_with = "deserialize_default_u32")]
    voters: u32,
}

impl From<RawPoll> for Poll {
    fn from(value: RawPoll) -> Self {
        Self {
            id: value.id,
            name: value.name,
            kind: if value.kind.is_empty() {
                "regular".to_string()
            } else {
                value.kind
            },
            status: if value.status.is_empty() {
                "open".to_string()
            } else {
                value.status
            },
            results: if value.results.is_empty() {
                "always".to_string()
            } else {
                value.results
            },
            options: value.options.into_iter().map(Into::into).collect(),
            voters: value.voters,
            user_votes: Vec::new(),
        }
    }
}

pub(crate) fn parse_poll_response_value(value: Value) -> Result<Poll, serde_json::Error> {
    let value = match value {
        Value::Object(ref object) if object.contains_key("poll") => object
            .get("poll")
            .cloned()
            .unwrap_or_else(|| Value::Object(object.clone())),
        value => value,
    };
    RawPoll::deserialize(value).map(Into::into)
}

pub(crate) fn parse_vote_response_value(value: Value) -> Result<VoteResponse, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("vote response root was not an object"));
    };

    let who_voted = object
        .get("who_voted")
        .and_then(Value::as_array)
        .map(|items| {
            crate::json_helpers::parse_array_items_lossy(items, "voted user entry", |item| {
                parse_voted_user_value(item.clone())
            })
        })
        .unwrap_or_default();

    Ok(VoteResponse {
        can_vote: boolean(object.get("can_vote")),
        vote_limit: integer_u32(object.get("vote_limit")).unwrap_or(0),
        vote_count: integer_i32(object.get("vote_count")).unwrap_or(0),
        votes_left: integer_i32(object.get("votes_left")).unwrap_or(0),
        alert: boolean(object.get("alert")),
        who_voted,
    })
}

pub(crate) fn parse_voted_users_value(value: Value) -> Result<Vec<VotedUser>, serde_json::Error> {
    let items = match value {
        Value::Array(items) => items,
        Value::Object(object) => object
            .get("who_voted")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
        _ => Vec::new(),
    };

    Ok(crate::json_helpers::parse_array_items_lossy(
        &items,
        "voted user entry",
        |item| parse_voted_user_value(item.clone()),
    ))
}

fn parse_voted_user_value(value: Value) -> Result<VotedUser, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("voted user entry was not an object"));
    };

    Ok(VotedUser {
        id: integer_u64(object.get("id")).unwrap_or(0),
        username: scalar_string(object.get("username")).unwrap_or_default(),
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
    })
}
