use std::collections::{BTreeMap, HashMap, HashSet};

use tracing::debug;

use fire_models::{
    TopicDetailSourceSnapshot, TopicPost, TopicTreePresentation, TopicTreePresentationQuery,
    TopicTreeRow,
};

use super::posts::{deduplicate_topic_posts_by_id, merge_topic_posts, ordered_unique_post_ids};

use super::super::FireCore;

const TOPIC_PARENT_HOP_LIMIT: usize = 32;

fn build_topic_tree_presentation_from_query(
    query: TopicTreePresentationQuery,
) -> TopicTreePresentation {
    let mut ordered_posts = deduplicate_topic_posts_by_id(merge_topic_posts(
        &query.raw_stream_ids,
        query.loaded_posts,
        Vec::new(),
    ));
    if !ordered_posts
        .iter()
        .any(|post| post.id == query.body_post.id)
    {
        ordered_posts.push(query.body_post.clone());
        ordered_posts = deduplicate_topic_posts_by_id(merge_topic_posts(
            &query.raw_stream_ids,
            ordered_posts,
            Vec::new(),
        ));
    }

    let original_post = ordered_posts
        .iter()
        .find(|post| {
            post.id == query.body_post.id || post.post_number == query.body_post.post_number
        })
        .cloned()
        .unwrap_or(query.body_post);

    let mut posts_by_id = HashMap::new();
    let mut posts_by_number = HashMap::new();
    for post in ordered_posts {
        posts_by_number.insert(post.post_number, post.clone());
        posts_by_id.insert(post.id, post);
    }

    let stream_index_by_post_id = query
        .raw_stream_ids
        .iter()
        .enumerate()
        .map(|(index, post_id)| (*post_id, index))
        .collect::<HashMap<_, _>>();

    let mut children_by_parent = BTreeMap::<u32, Vec<u64>>::new();
    for post in posts_by_id.values() {
        if post.id == original_post.id {
            continue;
        }
        let parent_post_number = resolve_tree_attachment_parent_post_number(
            post,
            &posts_by_number,
            original_post.post_number,
        );
        children_by_parent
            .entry(parent_post_number)
            .or_default()
            .push(post.id);
    }

    for child_post_ids in children_by_parent.values_mut() {
        child_post_ids.sort_by_key(|post_id| {
            let stream_index = stream_index_by_post_id
                .get(post_id)
                .copied()
                .unwrap_or(usize::MAX);
            let post_key = posts_by_id
                .get(post_id)
                .map(|post| (post.post_number, post.id))
                .unwrap_or((u32::MAX, u64::MAX));
            (stream_index, post_key.0, post_key.1)
        });
    }

    let mut reply_rows = Vec::new();
    let mut visible_root_post_numbers = Vec::new();
    let mut visited = HashSet::new();
    let root_children = children_by_parent
        .get(&original_post.post_number)
        .cloned()
        .unwrap_or_default();
    append_tree_rows_preorder(
        &root_children,
        original_post.post_number,
        0,
        None,
        &posts_by_id,
        &children_by_parent,
        &mut visited,
        &mut reply_rows,
        &mut visible_root_post_numbers,
    );

    let mut orphan_post_ids = query
        .raw_stream_ids
        .iter()
        .copied()
        .filter(|post_id| {
            posts_by_id.contains_key(post_id)
                && *post_id != original_post.id
                && !visited.contains(post_id)
        })
        .collect::<Vec<_>>();
    orphan_post_ids.extend(
        posts_by_id
            .keys()
            .copied()
            .filter(|post_id| *post_id != original_post.id && !visited.contains(post_id)),
    );
    orphan_post_ids = ordered_unique_post_ids(orphan_post_ids);
    if !orphan_post_ids.is_empty() {
        append_tree_rows_preorder(
            &orphan_post_ids,
            original_post.post_number,
            0,
            None,
            &posts_by_id,
            &children_by_parent,
            &mut visited,
            &mut reply_rows,
            &mut visible_root_post_numbers,
        );
    }

    TopicTreePresentation {
        original_post_id: original_post.id,
        original_post_number: original_post.post_number,
        first_unread_root_post_number: first_unread_root_post_number(
            &reply_rows,
            original_post.post_number,
            query.last_read_post_number,
        ),
        reply_rows,
        total_loaded_post_count: posts_by_id.len() as u32,
        visible_root_post_numbers,
        gained_new_root_progress: false,
    }
}

pub(crate) fn build_topic_tree_presentation_from_source_snapshot(
    snapshot: &TopicDetailSourceSnapshot,
) -> TopicTreePresentation {
    build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
        body_post: snapshot.body.post.clone(),
        raw_stream_ids: snapshot.raw_stream_ids.clone(),
        loaded_posts: snapshot.loaded_posts.clone(),
        focused_post_number: snapshot.focused_post_number,
        last_read_post_number: snapshot.header.last_read_post_number,
    })
}

pub(super) fn topic_tree_needs_unread_root_extension(
    snapshot: &TopicDetailSourceSnapshot,
    presentation: &TopicTreePresentation,
) -> bool {
    let Some(last_read_post_number) = snapshot.header.last_read_post_number else {
        return false;
    };
    last_read_post_number > 0
        && last_read_post_number < snapshot.header.highest_post_number
        && presentation.first_unread_root_post_number.is_none()
        && !snapshot.source_exhausted
}

pub(super) fn first_unread_root_post_number(
    reply_rows: &[TopicTreeRow],
    original_post_number: u32,
    last_read_post_number: Option<u32>,
) -> Option<u32> {
    let last_read_post_number = last_read_post_number?;
    reply_rows
        .iter()
        .find(|row| {
            row.parent_post_number == Some(original_post_number)
                && row.post_number > last_read_post_number
        })
        .map(|row| row.post_number)
}

pub(super) fn topic_detail_source_cooked_byte_count(snapshot: &TopicDetailSourceSnapshot) -> usize {
    let mut seen_post_ids = HashSet::new();
    let mut total = 0usize;
    for post in std::iter::once(&snapshot.body.post).chain(snapshot.loaded_posts.iter()) {
        if seen_post_ids.insert(post.id) {
            total += post.cooked.len();
        }
    }
    total
}

#[allow(clippy::too_many_arguments)]
fn append_tree_rows_preorder(
    child_post_ids: &[u64],
    parent_post_number: u32,
    parent_depth: u16,
    current_root_post_number: Option<u32>,
    posts_by_id: &HashMap<u64, TopicPost>,
    children_by_parent: &BTreeMap<u32, Vec<u64>>,
    visited: &mut HashSet<u64>,
    reply_rows: &mut Vec<TopicTreeRow>,
    visible_root_post_numbers: &mut Vec<u32>,
) -> u32 {
    let mut descendant_total = 0_u32;

    for (sibling_index, child_post_id) in child_post_ids.iter().copied().enumerate() {
        if !visited.insert(child_post_id) {
            continue;
        }
        let Some(post) = posts_by_id.get(&child_post_id).cloned() else {
            continue;
        };
        let root_post_number = current_root_post_number.unwrap_or(post.post_number);
        if current_root_post_number.is_none()
            && visible_root_post_numbers.last().copied() != Some(root_post_number)
        {
            visible_root_post_numbers.push(root_post_number);
        }

        let row_index = reply_rows.len();
        let grand_children = children_by_parent
            .get(&post.post_number)
            .cloned()
            .unwrap_or_default();
        reply_rows.push(TopicTreeRow {
            post_id: post.id,
            post_number: post.post_number,
            root_post_number,
            parent_post_number: Some(parent_post_number),
            depth: parent_depth.saturating_add(1),
            preorder_index: row_index as u32,
            has_children: !grand_children.is_empty(),
            sibling_index: sibling_index as u16,
            is_last_sibling: sibling_index + 1 == child_post_ids.len(),
            descendant_count: 0,
        });
        let nested_descendant_count = append_tree_rows_preorder(
            &grand_children,
            post.post_number,
            parent_depth.saturating_add(1),
            Some(root_post_number),
            posts_by_id,
            children_by_parent,
            visited,
            reply_rows,
            visible_root_post_numbers,
        );
        reply_rows[row_index].descendant_count = nested_descendant_count;
        descendant_total = descendant_total.saturating_add(1 + nested_descendant_count);
    }

    descendant_total
}

fn resolve_tree_attachment_parent_post_number(
    post: &TopicPost,
    posts_by_number: &HashMap<u32, TopicPost>,
    body_post_number: u32,
) -> u32 {
    let Some(declared_parent) = normalized_reply_target(post.reply_to_post_number) else {
        return body_post_number;
    };
    if declared_parent == body_post_number || declared_parent == post.post_number {
        if declared_parent == post.post_number {
            debug!(
                post_number = post.post_number,
                declared_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: post replies to itself"
            );
        }
        return body_post_number;
    }
    if !posts_by_number.contains_key(&declared_parent) {
        debug!(
            post_number = post.post_number,
            declared_parent,
            body_post_number,
            "topic tree attachment parent fell back to body: declared parent missing from loaded posts"
        );
        return body_post_number;
    }

    let mut current_parent = declared_parent;
    let mut visited = [0_u32; TOPIC_PARENT_HOP_LIMIT + 1];
    visited[0] = post.post_number;
    for visited_len in (1..).take(TOPIC_PARENT_HOP_LIMIT) {
        if visited[..visited_len].contains(&current_parent) {
            debug!(
                post_number = post.post_number,
                declared_parent,
                current_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: detected reply cycle"
            );
            return body_post_number;
        }
        visited[visited_len] = current_parent;
        let Some(parent_post) = posts_by_number.get(&current_parent) else {
            debug!(
                post_number = post.post_number,
                declared_parent,
                current_parent,
                body_post_number,
                "topic tree attachment parent fell back to body: ancestor disappeared from loaded posts"
            );
            return body_post_number;
        };
        match normalized_reply_target(parent_post.reply_to_post_number) {
            Some(next_parent) if next_parent == body_post_number => return declared_parent,
            Some(next_parent) if next_parent == parent_post.post_number => {
                debug!(
                    post_number = post.post_number,
                    declared_parent,
                    current_parent,
                    body_post_number,
                    "topic tree attachment parent fell back to body: ancestor replies to itself"
                );
                return body_post_number;
            }
            Some(next_parent) => {
                current_parent = next_parent;
            }
            None => return declared_parent,
        }
    }

    debug!(
        post_number = post.post_number,
        declared_parent,
        body_post_number,
        hop_limit = TOPIC_PARENT_HOP_LIMIT,
        "topic tree attachment parent fell back to body: exceeded parent hop limit"
    );
    body_post_number
}

fn normalized_reply_target(reply_to_post_number: Option<u32>) -> Option<u32> {
    reply_to_post_number.filter(|post_number| *post_number > 0)
}

impl FireCore {
    pub fn build_topic_tree_presentation(
        &self,
        query: TopicTreePresentationQuery,
    ) -> TopicTreePresentation {
        build_topic_tree_presentation_from_query(query)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fire_models::TopicPost;
    use std::collections::HashMap;

    fn make_topic_post(post_number: u32, reply_to_post_number: Option<u32>) -> TopicPost {
        TopicPost {
            id: u64::from(post_number),
            username: format!("user-{post_number}"),
            cooked: format!("<p>{post_number}</p>"),
            post_number,
            reply_to_post_number,
            ..TopicPost::default()
        }
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_when_intermediate_is_missing() {
        let body_post = make_topic_post(1, None);
        let post = make_topic_post(5, Some(3));
        let posts_by_number = HashMap::from([
            (body_post.post_number, body_post.clone()),
            (post.post_number, post.clone()),
        ]);

        let attachment_parent = resolve_tree_attachment_parent_post_number(
            &post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_when_cycle_is_detected() {
        let body_post = make_topic_post(1, None);
        let post = make_topic_post(3, Some(4));
        let parent = make_topic_post(4, Some(3));
        let posts_by_number = HashMap::from([
            (body_post.post_number, body_post.clone()),
            (post.post_number, post.clone()),
            (parent.post_number, parent),
        ]);

        let attachment_parent = resolve_tree_attachment_parent_post_number(
            &post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn resolve_tree_attachment_parent_falls_back_to_body_after_hop_limit() {
        let body_post = make_topic_post(1, None);
        let mut posts_by_number = HashMap::from([(body_post.post_number, body_post.clone())]);

        for post_number in 2..=36 {
            let reply_to_post_number = if post_number == 3 {
                Some(body_post.post_number)
            } else {
                Some(post_number - 1)
            };
            let post = make_topic_post(post_number, reply_to_post_number);
            posts_by_number.insert(post.post_number, post);
        }

        let post = posts_by_number
            .get(&36)
            .expect("missing deep descendant post");
        let attachment_parent = resolve_tree_attachment_parent_post_number(
            post,
            &posts_by_number,
            body_post.post_number,
        );

        assert_eq!(attachment_parent, body_post.post_number);
    }

    #[test]
    fn tree_presentation_preserves_parent_numbers_depths_and_root_grouping() {
        let body_post = make_topic_post(1, None);
        let root_post = make_topic_post(2, Some(1));
        let child_post = make_topic_post(3, Some(2));
        let grandchild_post = make_topic_post(4, Some(3));
        let second_root = make_topic_post(5, Some(1));

        let presentation = build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
            body_post: body_post.clone(),
            raw_stream_ids: vec![
                body_post.id,
                root_post.id,
                child_post.id,
                grandchild_post.id,
                second_root.id,
            ],
            loaded_posts: vec![
                body_post.clone(),
                root_post.clone(),
                child_post.clone(),
                grandchild_post.clone(),
                second_root.clone(),
            ],
            focused_post_number: None,
            last_read_post_number: Some(4),
        });

        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.post_id)
                .collect::<Vec<_>>(),
            vec![
                root_post.id,
                child_post.id,
                grandchild_post.id,
                second_root.id
            ]
        );
        assert_eq!(presentation.reply_rows[0].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[0].depth, 1);
        assert_eq!(presentation.reply_rows[1].parent_post_number, Some(2));
        assert_eq!(presentation.reply_rows[1].depth, 2);
        assert_eq!(presentation.reply_rows[2].parent_post_number, Some(3));
        assert_eq!(presentation.reply_rows[2].depth, 3);
        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.root_post_number)
                .collect::<Vec<_>>(),
            vec![2, 2, 2, 5]
        );
        assert_eq!(presentation.visible_root_post_numbers, vec![2, 5]);
        assert_eq!(presentation.first_unread_root_post_number, Some(5));
    }

    #[test]
    fn tree_presentation_reparents_missing_branch_to_body() {
        let body_post = make_topic_post(1, None);
        let orphan_root = make_topic_post(5, Some(99));
        let orphan_child = make_topic_post(6, Some(5));

        let presentation = build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
            body_post: body_post.clone(),
            raw_stream_ids: vec![body_post.id, orphan_root.id, orphan_child.id],
            loaded_posts: vec![body_post.clone(), orphan_root.clone(), orphan_child.clone()],
            focused_post_number: None,
            last_read_post_number: Some(5),
        });

        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.post_id)
                .collect::<Vec<_>>(),
            vec![orphan_root.id, orphan_child.id]
        );
        assert_eq!(presentation.reply_rows[0].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[1].parent_post_number, Some(1));
        assert_eq!(presentation.reply_rows[0].depth, 1);
        assert_eq!(presentation.reply_rows[1].depth, 1);
        assert_eq!(
            presentation
                .reply_rows
                .iter()
                .map(|row| row.root_post_number)
                .collect::<Vec<_>>(),
            vec![5, 6]
        );
        assert_eq!(presentation.visible_root_post_numbers, vec![5, 6]);
        assert_eq!(presentation.first_unread_root_post_number, Some(6));
    }

    #[test]
    fn tree_presentation_ignores_nested_unread_posts_for_root_target() {
        let body_post = make_topic_post(1, None);
        let root_post = make_topic_post(2, Some(1));
        let child_post = make_topic_post(9, Some(2));

        let presentation = build_topic_tree_presentation_from_query(TopicTreePresentationQuery {
            body_post: body_post.clone(),
            raw_stream_ids: vec![body_post.id, root_post.id, child_post.id],
            loaded_posts: vec![body_post.clone(), root_post.clone(), child_post.clone()],
            focused_post_number: None,
            last_read_post_number: Some(8),
        });

        assert_eq!(presentation.visible_root_post_numbers, vec![2]);
        assert_eq!(presentation.first_unread_root_post_number, None);
    }
}
