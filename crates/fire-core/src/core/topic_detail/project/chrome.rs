use fire_models::{
    TopicDetailChrome, TopicDetailParticipantDisplay, TopicDetailSidecarModel, TopicHeader,
};

use super::ProjectionChrome;

pub(crate) fn project_sidecar(chrome: &ProjectionChrome) -> TopicDetailSidecarModel {
    match &chrome.summary {
        Some(summary) => TopicDetailSidecarModel {
            summarized_text: Some(summary.summarized_text.clone()),
            algorithm: summary.algorithm.clone(),
            outdated: summary.outdated,
            can_regenerate: summary.can_regenerate,
            new_posts_since_summary: summary.new_posts_since_summary,
            updated_at: summary.updated_at.clone(),
            is_loading: chrome.summary_loading,
            error: chrome.summary_error.clone(),
        },
        None => TopicDetailSidecarModel {
            summarized_text: None,
            is_loading: chrome.summary_loading,
            error: chrome.summary_error.clone(),
            ..TopicDetailSidecarModel::default()
        },
    }
}

pub(crate) fn project_chrome(header: &TopicHeader) -> TopicDetailChrome {
    TopicDetailChrome {
        title: header.title.clone(),
        slug: header.slug.clone(),
        archetype: header.archetype.clone(),
        bookmarked: header.bookmarked,
        bookmark_id: header.bookmark_id,
        bookmark_name: header.bookmark_name.clone(),
        bookmark_reminder_at: header.bookmark_reminder_at.clone(),
        notification_level: header.details.notification_level,
        can_edit: header.details.can_edit,
        category_id: header.category_id,
        tags: header.tags.iter().map(|tag| tag.name.clone()).collect(),
        views: header.views,
        posts_count: header.posts_count,
        reply_count: header.reply_count,
        like_count: header.like_count,
        vote_count: header.vote_count,
        user_voted: header.user_voted,
        can_vote: header.can_vote,
        has_accepted_answer: header.has_accepted_answer,
        created_at: header.created_at.clone(),
        highest_post_number: header.highest_post_number,
        last_read_post_number: header.last_read_post_number,
        participants: header
            .details
            .participants
            .iter()
            .map(|participant| TopicDetailParticipantDisplay {
                user_id: participant.user_id,
                username: participant.username.clone().unwrap_or_default(),
                name: participant.name.clone(),
            })
            .collect(),
        summarizable: header.summarizable,
    }
}
