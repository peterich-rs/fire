use std::collections::HashMap;

use fire_models::{TopicDetailUiRow, TopicPost, TopicTreeRow};

use super::{row_shape, ProjectionChrome, RowShape};

#[derive(Clone, Default)]
pub(crate) struct ProjectedRowCache {
    entries: HashMap<u64, CachedRow>,
}

#[derive(Clone)]
struct CachedRow {
    version: u64,
    tree: RowShape,
    mutating: bool,
    loading_reply_context: bool,
    row: TopicDetailUiRow,
}

impl ProjectedRowCache {
    pub(crate) fn take(
        &mut self,
        post: &TopicPost,
        tree_row: &TopicTreeRow,
        is_original_post: bool,
        chrome: &ProjectionChrome,
        version: u64,
    ) -> Option<TopicDetailUiRow> {
        let mutating = chrome.mutating.contains(&post.id);
        let loading_reply_context = chrome.loading_reply_context.contains(&post.id);
        let tree = tree_key(post, tree_row, is_original_post);
        let cached = self.entries.get(&post.id)?;
        if cached.version == version
            && cached.tree == tree
            && cached.mutating == mutating
            && cached.loading_reply_context == loading_reply_context
        {
            return Some(cached.row.clone());
        }
        None
    }

    pub(crate) fn insert(
        &mut self,
        post_id: u64,
        version: u64,
        tree_row: &TopicTreeRow,
        is_original_post: bool,
        chrome: &ProjectionChrome,
        row: TopicDetailUiRow,
    ) {
        self.entries.insert(
            post_id,
            CachedRow {
                version,
                tree: row_shape(&row),
                mutating: chrome.mutating.contains(&post_id),
                loading_reply_context: chrome.loading_reply_context.contains(&post_id),
                row,
            },
        );
        let _ = tree_row;
        let _ = is_original_post;
    }

    pub(crate) fn retain_ids(&mut self, ids: impl Iterator<Item = u64>) {
        let keep: std::collections::HashSet<u64> = ids.collect();
        self.entries.retain(|id, _| keep.contains(id));
    }
}

fn tree_key(post: &TopicPost, tree_row: &TopicTreeRow, is_original_post: bool) -> RowShape {
    (
        post.id,
        post.post_number,
        tree_row.root_post_number,
        tree_row.parent_post_number,
        tree_row.depth,
        tree_row.has_children,
        tree_row.is_last_sibling,
        tree_row.descendant_count,
        post.reply_count,
        is_original_post,
    )
}
