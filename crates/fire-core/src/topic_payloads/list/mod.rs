use fire_models::{
    TopicListResponse, TopicParticipant, TopicPoster, TopicRow, TopicSummary, TopicTag, TopicUser,
};
use serde::Deserialize;
use std::collections::HashMap;
use time::{format_description::well_known::Rfc3339, OffsetDateTime};

use super::deser::{
    deserialize_default_bool, deserialize_default_record, deserialize_default_sequence,
    deserialize_default_string, deserialize_default_true_bool, deserialize_default_u32,
    deserialize_default_u64, deserialize_optional_record, deserialize_optional_scalar_string,
    deserialize_optional_u32, deserialize_optional_u64, deserialize_topic_tags,
};
use crate::preview_text_from_html;
use crate::topic_status_labels;

include!("topics.rs");
include!("bookmarks.rs");
include!("participants.rs");
