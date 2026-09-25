use std::collections::{HashMap, HashSet};

use fire_models::{TopicPost, TopicPostStream};

pub(super) fn missing_topic_post_ids(post_stream: &TopicPostStream) -> Vec<u64> {
    if post_stream.stream.len() <= post_stream.posts.len() {
        return Vec::new();
    }

    let loaded_post_ids: HashSet<u64> = post_stream.posts.iter().map(|post| post.id).collect();
    post_stream
        .stream
        .iter()
        .copied()
        .filter(|post_id| !loaded_post_ids.contains(post_id))
        .collect()
}

pub(super) fn merge_topic_posts(
    ordered_post_ids: &[u64],
    existing_posts: Vec<TopicPost>,
    fetched_posts: Vec<TopicPost>,
) -> Vec<TopicPost> {
    let mut posts_by_id: HashMap<u64, TopicPost> = HashMap::new();
    for post in existing_posts {
        posts_by_id.insert(post.id, post);
    }
    for mut post in fetched_posts {
        if let Some(existing) = posts_by_id.get(&post.id) {
            post.reuse_presentation_from(existing);
        }
        posts_by_id.insert(post.id, post);
    }

    let mut merged_posts = Vec::with_capacity(posts_by_id.len());
    for post_id in ordered_post_ids {
        if let Some(post) = posts_by_id.remove(post_id) {
            merged_posts.push(post);
        }
    }

    let mut trailing_posts: Vec<TopicPost> = posts_by_id.into_values().collect();
    trailing_posts.sort_by_key(|post| (post.post_number, post.id));
    merged_posts.extend(trailing_posts);
    merged_posts
}

pub(super) fn topic_posts_for_requested_ids(
    requested_post_ids: &[u64],
    cached_posts: Vec<TopicPost>,
    fetched_posts: Vec<TopicPost>,
) -> Vec<TopicPost> {
    let mut posts_by_id: HashMap<u64, TopicPost> = cached_posts
        .into_iter()
        .chain(fetched_posts)
        .map(|post| (post.id, post))
        .collect();

    let mut ordered_posts = Vec::with_capacity(posts_by_id.len());
    for post_id in requested_post_ids {
        if let Some(post) = posts_by_id.remove(post_id) {
            ordered_posts.push(post);
        }
    }

    let mut trailing_posts: Vec<TopicPost> = posts_by_id.into_values().collect();
    trailing_posts.sort_by_key(|post| (post.post_number, post.id));
    ordered_posts.extend(trailing_posts);
    ordered_posts
}
pub(super) fn missing_post_ids_from_ids(
    ordered_post_ids: &[u64],
    loaded_posts: &[TopicPost],
) -> Vec<u64> {
    let loaded_post_ids: HashSet<u64> = loaded_posts.iter().map(|post| post.id).collect();
    ordered_post_ids
        .iter()
        .copied()
        .filter(|post_id| !loaded_post_ids.contains(post_id))
        .collect()
}

pub(super) fn ordered_unique_post_ids(ids: Vec<u64>) -> Vec<u64> {
    let mut seen = HashSet::new();
    let mut result = Vec::with_capacity(ids.len());
    for post_id in ids {
        if post_id > 0 && seen.insert(post_id) {
            result.push(post_id);
        }
    }
    result
}
pub(super) fn deduplicate_topic_posts_by_id(posts: Vec<TopicPost>) -> Vec<TopicPost> {
    let mut seen_post_ids = HashSet::new();
    let mut deduplicated = Vec::with_capacity(posts.len());
    for post in posts {
        if seen_post_ids.insert(post.id) {
            deduplicated.push(post);
        }
    }
    deduplicated
}
