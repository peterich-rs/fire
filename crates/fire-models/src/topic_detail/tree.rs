use std::collections::HashSet;

use serde::{Deserialize, Serialize};

use super::post::TopicPost;

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTreePresentationQuery {
    pub body_post: TopicPost,
    pub raw_stream_ids: Vec<u64>,
    pub loaded_posts: Vec<TopicPost>,
    pub focused_post_number: Option<u32>,
    pub last_read_post_number: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTreePresentation {
    pub original_post_id: u64,
    pub original_post_number: u32,
    pub reply_rows: Vec<TopicTreeRow>,
    pub total_loaded_post_count: u32,
    pub visible_root_post_numbers: Vec<u32>,
    pub first_unread_root_post_number: Option<u32>,
    pub gained_new_root_progress: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicTreeRow {
    pub post_id: u64,
    pub post_number: u32,
    pub root_post_number: u32,
    pub parent_post_number: Option<u32>,
    pub depth: u16,
    pub preorder_index: u32,
    pub has_children: bool,
    pub sibling_index: u16,
    pub is_last_sibling: bool,
    pub descendant_count: u32,
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

pub(super) fn normalized_reply_target(reply_to_post_number: Option<u32>) -> Option<u32> {
    reply_to_post_number.filter(|post_number| *post_number > 0)
}

pub(super) fn build_floor_timeline_entries(posts: &[TopicPost]) -> Vec<TopicTimelineEntry> {
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

pub(super) fn compute_depth_walk(
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
            Some(gp) if gp != parent_pn => compute_depth_walk(gp, posts, loaded, current_depth + 1),
            _ => current_depth,
        },
        None => current_depth,
    }
}

pub(super) fn flatten_thread_replies(
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
