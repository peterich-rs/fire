use fire_models::{
    Poll, PostReactionUpdate, ReactionUser, ReactionUsersGroup, TopicPost, TopicPostAuthorMetadata,
    TopicPostBoost, TopicPostBoostUser, TopicReaction, TopicReplyToUser,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

use super::deser::{
    deserialize_default_bool, deserialize_default_i32, deserialize_default_record,
    deserialize_default_sequence, deserialize_default_string, deserialize_default_string_sequence,
    deserialize_default_u32, deserialize_default_u64, deserialize_optional_bool,
    deserialize_optional_i32, deserialize_optional_record, deserialize_optional_scalar_string,
    deserialize_optional_string_sequence_map, deserialize_optional_u32, deserialize_optional_u64,
};
use super::list::normalized_scalar;
use super::poll::RawPoll;
use crate::json_helpers::{
    integer_u32, integer_u64, invalid_json, parse_array_items_lossy, scalar_string,
};

include!("model.rs");
include!("boosts.rs");
include!("reactions.rs");
include!("replies.rs");
