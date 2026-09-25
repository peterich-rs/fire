use fire_models::{TopicReplyRequest, TopicUpdateRequest};
use tokio::sync::mpsc;

use super::super::FireCore;
use super::*;
use crate::error::FireCoreError;

include!("posts.rs");
include!("boosts.rs");
include!("polls.rs");
include!("votes.rs");
include!("solutions.rs");
include!("bookmarks.rs");
include!("topic.rs");
