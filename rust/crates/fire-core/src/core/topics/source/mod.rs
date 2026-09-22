use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicDetailSourceSnapshot, TopicHeader, TopicLoadMoreOutcome, TopicLoadMoreStopReason,
    TopicLoadedRange, TopicPost, TopicTreePresentation,
};

use crate::error::FireCoreError;

mod hydrate;
mod load;
mod session;

pub(crate) use load::{load_more_topic_detail_posts, load_topic_detail_page};

const TOPIC_POST_BATCH_SIZE: usize = 50;
const FETCH_TOPIC_AI_SUMMARY_OPERATION: &str = "fetch topic ai summary";
const DEFAULT_TOPIC_INITIAL_BATCH_SIZE: u16 = 40;
const DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE: u16 = 40;
const DEFAULT_TOPIC_MAX_AUTO_BATCHES_PER_GESTURE: u8 = 3;
const DEFAULT_TOPIC_MAX_AUTO_POSTS_PER_GESTURE: u16 = 120;
const TOPIC_LOAD_MORE_FAILURE_MESSAGE: &str = "topic source batch append failed";

#[derive(Default)]
pub(crate) struct FireTopicDetailSourceRuntime {
    next_session_id: u64,
    sessions_by_topic_id: HashMap<u64, TopicDetailSourceSession>,
}

#[derive(Clone)]
pub(crate) struct TopicDetailSourceSession {
    session_id: u64,
    session_epoch: u64,
    header: TopicHeader,
    body_post_id: u64,
    body_post_number: u32,
    focused_post_number: Option<u32>,
    raw_stream_ids: Vec<u64>,
    posts_by_id: HashMap<u64, TopicPost>,
    post_id_by_number: HashMap<u32, u64>,
    unavailable_post_ids: HashSet<u64>,
    loaded_ranges: Vec<TopicLoadedRange>,
    next_stream_offset: usize,
    last_loaded_post_id: Option<u64>,
    source_exhausted: bool,
    load_more_policy: TopicLoadMorePolicy,
}

#[derive(Clone, Copy)]
struct TopicLoadMorePolicy {
    batch_size: u16,
    max_auto_batches_per_gesture: u8,
    max_auto_posts_per_gesture: u16,
    require_new_root_progress: bool,
}

#[derive(Default)]
struct TopicUnreadRootAutoSeekStats {
    chained_batches: u8,
    chained_posts: u16,
}

struct TopicDetailSourceSessionInit {
    session_epoch: u64,
    header: TopicHeader,
    body_post: TopicPost,
    focused_post_number: Option<u32>,
    raw_stream_ids: Vec<u64>,
    cached_posts: Vec<TopicPost>,
    unavailable_post_ids: HashSet<u64>,
    load_more_policy: TopicLoadMorePolicy,
}

fn ensure_requested_topic_detail(
    requested_topic_id: u64,
    actual_topic_id: u64,
) -> Result<(), FireCoreError> {
    if requested_topic_id == actual_topic_id {
        return Ok(());
    }
    Err(FireCoreError::UnexpectedTopicDetail {
        requested_topic_id,
        actual_topic_id,
    })
}

fn normalized_topic_initial_batch_size(batch_size: u16) -> u16 {
    if batch_size == 0 {
        DEFAULT_TOPIC_INITIAL_BATCH_SIZE
    } else {
        batch_size
    }
}

fn topic_load_more_outcome(
    source_snapshot: TopicDetailSourceSnapshot,
    appended_posts: Vec<TopicPost>,
    tree_presentation: TopicTreePresentation,
    chained_batches: u8,
    chained_posts: u16,
    stop_reason: TopicLoadMoreStopReason,
) -> TopicLoadMoreOutcome {
    TopicLoadMoreOutcome {
        source_snapshot,
        appended_posts,
        tree_presentation,
        chained_batches,
        chained_posts,
        stop_reason,
    }
}

fn normalized_topic_load_more_batch_size(batch_size: u16) -> u16 {
    if batch_size == 0 {
        DEFAULT_TOPIC_LOAD_MORE_BATCH_SIZE
    } else {
        batch_size
    }
}

fn normalized_topic_auto_batch_limit(limit: u8) -> u8 {
    if limit == 0 {
        DEFAULT_TOPIC_MAX_AUTO_BATCHES_PER_GESTURE
    } else {
        limit
    }
}

fn normalized_topic_auto_post_limit(limit: u16) -> u16 {
    if limit == 0 {
        DEFAULT_TOPIC_MAX_AUTO_POSTS_PER_GESTURE
    } else {
        limit
    }
}

fn gained_visible_root_progress(previous: &[u32], current: &[u32]) -> bool {
    let previous_roots = previous.iter().copied().collect::<HashSet<_>>();
    current
        .iter()
        .copied()
        .any(|post_number| !previous_roots.contains(&post_number))
}
