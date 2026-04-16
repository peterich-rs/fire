use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use crate::cookie::is_non_empty;
use crate::topic::{TopicParticipant, TopicTag};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailQuery {
    pub topic_id: u64,
    pub post_number: Option<u32>,
    pub track_visit: bool,
    pub filter: Option<String>,
    pub username_filters: Option<String>,
    pub filter_top_level_replies: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicReaction {
    pub id: String,
    #[serde(default, alias = "type")]
    pub kind: Option<String>,
    pub count: u32,
    #[serde(default)]
    pub can_undo: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PollOption {
    pub id: String,
    pub html: String,
    pub votes: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Poll {
    pub id: u64,
    pub name: String,
    #[serde(default, alias = "type")]
    pub kind: String,
    pub status: String,
    pub results: String,
    #[serde(default)]
    pub options: Vec<PollOption>,
    pub voters: u32,
    #[serde(default)]
    pub user_votes: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicReplyRequest {
    pub topic_id: u64,
    pub raw: String,
    pub reply_to_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicCreateRequest {
    pub title: String,
    pub raw: String,
    pub category_id: u64,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PrivateMessageCreateRequest {
    pub title: String,
    pub raw: String,
    #[serde(default)]
    pub target_recipients: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicUpdateRequest {
    pub topic_id: u64,
    pub title: String,
    pub category_id: u64,
    #[serde(default)]
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostUpdateRequest {
    pub post_id: u64,
    pub raw: String,
    pub edit_reason: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct InviteCreateRequest {
    pub max_redemptions_allowed: u32,
    pub expires_at: Option<String>,
    pub description: Option<String>,
    pub email: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftData {
    pub reply: Option<String>,
    pub title: Option<String>,
    #[serde(rename = "categoryId", alias = "category_id")]
    pub category_id: Option<u64>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(rename = "replyToPostNumber", alias = "reply_to_post_number")]
    pub reply_to_post_number: Option<u32>,
    pub action: Option<String>,
    #[serde(default)]
    pub recipients: Vec<String>,
    #[serde(rename = "archetypeId", alias = "archetype_id")]
    pub archetype_id: Option<String>,
    #[serde(rename = "composerTime", alias = "composer_time")]
    pub composer_time: Option<u32>,
    #[serde(rename = "typingTime", alias = "typing_time")]
    pub typing_time: Option<u32>,
}

impl DraftData {
    pub fn has_content(&self) -> bool {
        is_non_empty(self.reply.as_deref()) || is_non_empty(self.title.as_deref())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Draft {
    pub draft_key: String,
    pub data: DraftData,
    pub sequence: u32,
    pub title: Option<String>,
    pub excerpt: Option<String>,
    pub updated_at: Option<String>,
    pub username: Option<String>,
    pub avatar_template: Option<String>,
    pub topic_id: Option<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct DraftListResponse {
    #[serde(default)]
    pub drafts: Vec<Draft>,
    #[serde(default)]
    pub has_more: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadResult {
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedUploadUrl {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTimingEntry {
    pub post_number: u32,
    pub milliseconds: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTimingsRequest {
    pub topic_id: u64,
    pub topic_time_ms: u32,
    pub timings: Vec<TopicTimingEntry>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PostReactionUpdate {
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPost {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub cooked: String,
    pub raw: Option<String>,
    pub post_number: u32,
    pub post_type: i32,
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub like_count: u32,
    pub reply_count: u32,
    pub reply_to_post_number: Option<u32>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub reactions: Vec<TopicReaction>,
    pub current_user_reaction: Option<TopicReaction>,
    pub polls: Vec<Poll>,
    pub accepted_answer: bool,
    pub can_edit: bool,
    pub can_delete: bool,
    pub can_recover: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicPostStream {
    pub posts: Vec<TopicPost>,
    pub stream: Vec<u64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadReply {
    pub post_number: u32,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadSection {
    pub anchor_post_number: u32,
    pub replies: Vec<TopicThreadReply>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThread {
    pub original_post_number: Option<u32>,
    pub reply_sections: Vec<TopicThreadSection>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicThreadFlatPost {
    pub post: TopicPost,
    pub depth: u32,
    pub parent_post_number: Option<u32>,
    pub shows_thread_line: bool,
    pub is_original_post: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTimelineEntry {
    pub post_id: u64,
    pub post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u32,
    pub is_original_post: bool,
}

impl TopicThread {
    pub fn from_posts(posts: &[TopicPost]) -> Self {
        let Some(original_post) = posts.iter().min_by_key(|post| post.post_number) else {
            return Self::default();
        };

        let root_post_number = original_post.post_number;
        let post_numbers: std::collections::HashSet<u32> =
            posts.iter().map(|post| post.post_number).collect();
        let mut children_by_parent: std::collections::BTreeMap<u32, Vec<&TopicPost>> =
            std::collections::BTreeMap::new();

        for post in posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
        {
            let Some(parent_post_number) = normalized_reply_target(post.reply_to_post_number)
            else {
                continue;
            };
            if parent_post_number == post.post_number {
                continue;
            }
            children_by_parent
                .entry(parent_post_number)
                .or_default()
                .push(post);
        }

        let mut consumed_post_numbers = std::collections::HashSet::from([root_post_number]);
        let mut reply_sections = Vec::new();

        for post in posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
        {
            if consumed_post_numbers.contains(&post.post_number) {
                continue;
            }

            let normalized_parent = normalized_reply_target(post.reply_to_post_number);
            let should_start_section = normalized_parent.is_none()
                || normalized_parent == Some(root_post_number)
                || normalized_parent.is_some_and(|parent| !post_numbers.contains(&parent));
            if !should_start_section {
                continue;
            }

            consumed_post_numbers.insert(post.post_number);
            let mut branch_visited = std::collections::HashSet::from([post.post_number]);
            let replies = flatten_thread_replies(
                post.post_number,
                1,
                &children_by_parent,
                &mut consumed_post_numbers,
                &mut branch_visited,
            );
            reply_sections.push(TopicThreadSection {
                anchor_post_number: post.post_number,
                replies,
            });
        }

        let remaining_post_numbers: Vec<u32> = posts
            .iter()
            .filter(|post| post.post_number != root_post_number)
            .map(|post| post.post_number)
            .filter(|post_number| !consumed_post_numbers.contains(post_number))
            .collect();

        for post_number in remaining_post_numbers {
            let Some(post) = posts.iter().find(|post| post.post_number == post_number) else {
                continue;
            };
            consumed_post_numbers.insert(post.post_number);
            let mut branch_visited = std::collections::HashSet::from([post.post_number]);
            let replies = flatten_thread_replies(
                post.post_number,
                1,
                &children_by_parent,
                &mut consumed_post_numbers,
                &mut branch_visited,
            );
            reply_sections.push(TopicThreadSection {
                anchor_post_number: post.post_number,
                replies,
            });
        }

        Self {
            original_post_number: Some(root_post_number),
            reply_sections,
        }
    }

    pub fn flatten(&self, posts: &[TopicPost]) -> Vec<TopicThreadFlatPost> {
        let posts_by_number: std::collections::HashMap<u32, &TopicPost> =
            posts.iter().map(|post| (post.post_number, post)).collect();
        let mut result = Vec::new();

        if let Some(original_post) = self
            .original_post_number
            .and_then(|post_number| posts_by_number.get(&post_number))
        {
            result.push(TopicThreadFlatPost {
                post: (*original_post).clone(),
                depth: 0,
                parent_post_number: None,
                shows_thread_line: !self.reply_sections.is_empty(),
                is_original_post: true,
            });
        }

        for (section_index, section) in self.reply_sections.iter().enumerate() {
            let is_last_section = section_index == self.reply_sections.len() - 1;
            let has_nested_replies = !section.replies.is_empty();

            let Some(anchor_post) = posts_by_number.get(&section.anchor_post_number) else {
                continue;
            };

            result.push(TopicThreadFlatPost {
                post: (*anchor_post).clone(),
                depth: 0,
                parent_post_number: None,
                shows_thread_line: has_nested_replies || !is_last_section,
                is_original_post: false,
            });

            for (reply_index, reply) in section.replies.iter().enumerate() {
                let Some(reply_post) = posts_by_number.get(&reply.post_number) else {
                    continue;
                };
                let is_last_reply = reply_index == section.replies.len() - 1;
                result.push(TopicThreadFlatPost {
                    post: (*reply_post).clone(),
                    depth: reply.depth,
                    parent_post_number: reply.parent_post_number,
                    shows_thread_line: !is_last_reply || !is_last_section,
                    is_original_post: false,
                });
            }
        }

        result
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailCreatedBy {
    pub id: u64,
    pub username: String,
    pub avatar_template: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetailMeta {
    pub notification_level: Option<i32>,
    pub can_edit: bool,
    pub created_by: Option<TopicDetailCreatedBy>,
    #[serde(default)]
    pub participants: Vec<TopicParticipant>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetail {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub posts_count: u32,
    pub category_id: Option<u64>,
    pub tags: Vec<TopicTag>,
    pub views: u32,
    pub like_count: u32,
    pub created_at: Option<String>,
    pub last_read_post_number: Option<u32>,
    pub bookmarks: Vec<u64>,
    pub bookmarked: bool,
    pub bookmark_id: Option<u64>,
    pub bookmark_name: Option<String>,
    pub bookmark_reminder_at: Option<String>,
    pub accepted_answer: bool,
    pub has_accepted_answer: bool,
    pub can_vote: bool,
    pub vote_count: i32,
    pub user_voted: bool,
    pub summarizable: bool,
    pub has_cached_summary: bool,
    pub has_summary: bool,
    pub archetype: Option<String>,
    pub post_stream: TopicPostStream,
    #[serde(default)]
    pub thread: TopicThread,
    #[serde(default)]
    pub flat_posts: Vec<TopicThreadFlatPost>,
    #[serde(default)]
    pub timeline_entries: Vec<TopicTimelineEntry>,
    pub details: TopicDetailMeta,
}

impl TopicDetail {
    pub fn rebuild_timeline_entries(&mut self) {
        self.timeline_entries = build_floor_timeline_entries(&self.post_stream.posts);
    }

    pub fn interaction_count(&self) -> u32 {
        self.like_count.saturating_add(
            self.post_stream
                .posts
                .iter()
                .flat_map(|post| post.reactions.iter())
                .filter(|reaction| !reaction.id.eq_ignore_ascii_case("heart"))
                .fold(0_u32, |total, reaction| {
                    total.saturating_add(reaction.count)
                }),
        )
    }
}

fn normalized_reply_target(reply_to_post_number: Option<u32>) -> Option<u32> {
    reply_to_post_number.filter(|post_number| *post_number > 0)
}

fn build_floor_timeline_entries(posts: &[TopicPost]) -> Vec<TopicTimelineEntry> {
    let post_numbers: HashSet<u32> = posts.iter().map(|p| p.post_number).collect();
    let min_pn = posts.iter().map(|p| p.post_number).min().unwrap_or(0);
    let mut sorted: Vec<&TopicPost> = posts.iter().collect();
    sorted.sort_by_key(|p| (p.post_number, p.id));

    sorted
        .iter()
        .map(|post| {
            let parent = normalized_reply_target(post.reply_to_post_number);
            let depth = match parent {
                Some(pn) if pn != post.post_number => {
                    compute_depth_walk(pn, posts, &post_numbers, 1)
                }
                _ => 0,
            };
            TopicTimelineEntry {
                post_id: post.id,
                post_number: post.post_number,
                parent_post_number: parent,
                depth,
                is_original_post: post.post_number == min_pn,
            }
        })
        .collect()
}

fn compute_depth_walk(
    parent_pn: u32,
    posts: &[TopicPost],
    loaded: &HashSet<u32>,
    current_depth: u32,
) -> u32 {
    if !loaded.contains(&parent_pn) {
        return current_depth;
    }
    match posts.iter().find(|p| p.post_number == parent_pn) {
        Some(p) => match normalized_reply_target(p.reply_to_post_number) {
            Some(gp) if gp != parent_pn => {
                compute_depth_walk(gp, posts, loaded, current_depth + 1)
            }
            _ => current_depth,
        },
        None => current_depth,
    }
}

fn flatten_thread_replies(
    parent_post_number: u32,
    depth: u32,
    children_by_parent: &std::collections::BTreeMap<u32, Vec<&TopicPost>>,
    consumed_post_numbers: &mut std::collections::HashSet<u32>,
    branch_visited: &mut std::collections::HashSet<u32>,
) -> Vec<TopicThreadReply> {
    let Some(children) = children_by_parent.get(&parent_post_number) else {
        return Vec::new();
    };

    let mut replies = Vec::new();
    for child in children {
        if branch_visited.contains(&child.post_number) {
            continue;
        }

        consumed_post_numbers.insert(child.post_number);
        replies.push(TopicThreadReply {
            post_number: child.post_number,
            depth,
            parent_post_number: normalized_reply_target(child.reply_to_post_number),
        });

        branch_visited.insert(child.post_number);
        replies.extend(flatten_thread_replies(
            child.post_number,
            depth + 1,
            children_by_parent,
            consumed_post_numbers,
            branch_visited,
        ));
        branch_visited.remove(&child.post_number);
    }

    replies
}
