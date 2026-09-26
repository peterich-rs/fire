use std::collections::HashMap;

use fire_models::{
    TopicDetailAuthorDisplay, TopicDetailBoostDisplay, TopicDetailBoostUserDisplay,
    TopicDetailPollDisplay, TopicDetailReactionChip, TopicDetailReplyUserDisplay,
    TopicDetailSourceSnapshot, TopicDetailUiRow, TopicPost, TopicTreeRow,
};

use super::checksum::{
    actions_band_checksum, author_band_checksum, reactions_band_checksum, row_checksums,
    text_band_checksum,
};
use super::ProjectionChrome;

pub(crate) fn project_row(
    post: &TopicPost,
    tree_row: &TopicTreeRow,
    is_original_post: bool,
    chrome: &ProjectionChrome,
) -> TopicDetailUiRow {
    let selected_id = post
        .current_user_reaction
        .as_ref()
        .map(|reaction| reaction.id.clone());
    let reactions = post
        .reactions
        .iter()
        .map(|reaction| {
            TopicDetailReactionChip::from_reaction(
                reaction,
                Some(&reaction.id) == selected_id.as_ref(),
            )
        })
        .collect::<Vec<_>>();
    let author = author_display(post);
    let polls = post
        .polls
        .iter()
        .map(TopicDetailPollDisplay::from)
        .collect::<Vec<_>>();
    let boosts = post
        .boosts
        .iter()
        .map(|boost| TopicDetailBoostDisplay {
            id: boost.id,
            display_text: boost.display_text.clone(),
            user: TopicDetailBoostUserDisplay {
                id: boost.user.id,
                username: boost.user.username.clone(),
                name: boost.user.name.clone(),
                avatar_template: boost.user.avatar_template.clone(),
            },
            can_delete: boost.can_delete,
            can_flag: boost.can_flag,
            user_flag_status: boost.user_flag_status,
            available_flags: boost.available_flags.clone(),
            presentation: boost.presented.clone(),
        })
        .collect::<Vec<_>>();
    let is_mutating = chrome.mutating.contains(&post.id);
    let is_loading_reply_context = chrome.loading_reply_context.contains(&post.id);
    let mut row = TopicDetailUiRow {
        post_id: post.id,
        post_number: post.post_number,
        root_post_number: tree_row.root_post_number,
        parent_post_number: tree_row.parent_post_number,
        depth: tree_row.depth,
        has_children: tree_row.has_children,
        is_last_sibling: tree_row.is_last_sibling,
        descendant_count: tree_row.descendant_count,
        author: author.clone(),
        presentation: post.presented.clone(),
        layout_checksum: 0,
        interaction_checksum: 0,
        author_band_checksum: 0,
        text_band_checksum: 0,
        actions_band_checksum: 0,
        reactions_band_checksum: 0,
        created_at: post.created_at.clone(),
        updated_at: post.updated_at.clone(),
        post_type: post.post_type,
        reply_count: post.reply_count,
        reply_to_username: post
            .reply_to_user
            .as_ref()
            .map(|user| user.username.clone())
            .or_else(|| post.reply_to_post_number.map(|number| format!("#{number}"))),
        reply_to_user: post
            .reply_to_user
            .as_ref()
            .map(|user| TopicDetailReplyUserDisplay {
                username: user.username.clone(),
                name: user.name.clone(),
                avatar_template: user.avatar_template.clone(),
            }),
        like_count: post.like_count,
        reactions,
        current_reaction_id: selected_id,
        polls,
        boosts,
        accepted_answer: post.accepted_answer,
        can_accept_answer: post.can_accept_answer,
        can_unaccept_answer: post.can_unaccept_answer,
        can_edit: post.can_edit,
        can_delete: post.can_delete,
        can_recover: post.can_recover,
        can_boost: post.can_boost,
        bookmarked: post.bookmarked,
        bookmark_id: post.bookmark_id,
        bookmark_name: post.bookmark_name.clone(),
        bookmark_reminder_at: post.bookmark_reminder_at.clone(),
        hidden: post.hidden,
        is_mutating,
        is_loading_reply_context,
        is_original_post,
    };
    let (layout, interaction) = row_checksums(&row);
    row.layout_checksum = layout;
    row.interaction_checksum = interaction;
    row.author_band_checksum = author_band_checksum(&row);
    row.text_band_checksum = text_band_checksum(&row);
    row.actions_band_checksum = actions_band_checksum(&row);
    row.reactions_band_checksum = reactions_band_checksum(&row);
    row
}

fn author_display(post: &TopicPost) -> TopicDetailAuthorDisplay {
    let metadata = &post.author_metadata;
    TopicDetailAuthorDisplay {
        username: post.username.clone(),
        name: post.name.clone(),
        avatar_template: post.avatar_template.clone(),
        user_id: metadata.user_id,
        user_title: metadata.user_title.clone(),
        primary_group_name: metadata.primary_group_name.clone(),
        flair_url: metadata.flair_url.clone(),
        flair_name: metadata.flair_name.clone(),
        flair_bg_color: metadata.flair_bg_color.clone(),
        flair_color: metadata.flair_color.clone(),
        flair_group_id: metadata.flair_group_id,
        moderator: metadata.moderator,
        admin: metadata.admin,
        group_moderator: metadata.group_moderator,
        user_status_emoji: metadata.user_status_emoji.clone(),
        user_status_description: metadata.user_status_description.clone(),
    }
}

pub(crate) fn posts_by_id(source: &TopicDetailSourceSnapshot) -> HashMap<u64, &TopicPost> {
    let mut posts = HashMap::with_capacity(source.loaded_posts.len() + 1);
    posts.insert(source.body.post.id, &source.body.post);
    for post in &source.loaded_posts {
        posts.insert(post.id, post);
    }
    posts
}
