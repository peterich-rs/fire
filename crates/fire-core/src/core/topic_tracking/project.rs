use fire_models::{TopicHomeRowCountPatch, TopicTrackingPatch};

use super::super::FireCore;

pub(crate) fn project_tracking_to_home(
    core: &FireCore,
    topic_id: u64,
) -> Option<TopicHomeRowCountPatch> {
    let tracking = core.topic_tracking_state(topic_id)?;
    let tracking_patch = TopicTrackingPatch::from_state(&tracking);
    let auth_scope_hash = core.current_auth_scope_hash();
    let scope_key =
        crate::core::topics::topic_list_cache_scope_key(&core.current_home_topic_list_query());
    let pages = {
        let store = core
            .shared_store
            .lock()
            .expect("shared store mutex poisoned");
        store
            .topic_list_cache_list_pages(&auth_scope_hash, &scope_key)
            .ok()?
    };

    for (_page, payload) in pages {
        let Ok(cached) = serde_json::from_str::<fire_models::TopicListResponse>(&payload) else {
            continue;
        };
        if let Some(row) = cached.rows.iter().find(|row| row.topic.id == topic_id) {
            return Some(home_patch_from_tracking(&tracking_patch, row));
        }
        if let Some(summary) = cached.topics.iter().find(|topic| topic.id == topic_id) {
            return Some(TopicHomeRowCountPatch {
                topic_id,
                posts_count: summary.posts_count.max(tracking.highest_post_number),
                reply_count: summary.reply_count,
                views: summary.views,
                last_read_post_number: tracking.last_read_post_number,
                highest_post_number: tracking
                    .highest_post_number
                    .max(summary.highest_post_number),
                unread: tracking_patch.unread,
                unread_posts: Some(tracking_patch.unread_posts),
                new_posts: Some(tracking_patch.new_posts),
            });
        }
    }
    None
}

fn home_patch_from_tracking(
    tracking: &TopicTrackingPatch,
    row: &fire_models::TopicRow,
) -> TopicHomeRowCountPatch {
    TopicHomeRowCountPatch {
        topic_id: tracking.topic_id,
        posts_count: row.topic.posts_count.max(tracking.highest_post_number),
        reply_count: row.topic.reply_count,
        views: row.topic.views,
        last_read_post_number: tracking.last_read_post_number,
        highest_post_number: tracking
            .highest_post_number
            .max(row.topic.highest_post_number),
        unread: tracking.unread,
        unread_posts: Some(tracking.unread_posts),
        new_posts: Some(tracking.new_posts),
    }
}
