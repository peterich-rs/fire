use std::collections::{HashMap, HashSet};

use fire_models::{
    TopicBody, TopicDetailSourceSnapshot, TopicHeader, TopicLoadedRange, TopicPost,
    TopicSourceCursor,
};

use super::super::posts::merge_topic_posts;
use super::*;
impl TopicDetailSourceSession {
    pub(crate) fn raw_stream_len(&self) -> usize {
        self.raw_stream_ids.len()
    }

    pub(crate) fn raw_stream_ids(&self) -> &[u64] {
        &self.raw_stream_ids
    }

    pub(crate) fn contains_post_number(&self, post_number: u32) -> bool {
        self.post_id_by_number.contains_key(&post_number)
    }

    pub(crate) fn header(&self) -> &TopicHeader {
        &self.header
    }

    pub(crate) fn header_mut(&mut self) -> &mut TopicHeader {
        &mut self.header
    }

    pub(crate) fn post(&self, post_id: u64) -> Option<&TopicPost> {
        self.posts_by_id.get(&post_id)
    }

    pub(crate) fn post_mut(&mut self, post_id: u64) -> Option<&mut TopicPost> {
        self.posts_by_id.get_mut(&post_id)
    }

    pub(crate) fn stream_index_for_post_number(&self, post_number: u32) -> Option<usize> {
        let post_id = self.post_id_by_number.get(&post_number).copied()?;
        self.raw_stream_ids.iter().position(|id| *id == post_id)
    }

    pub(crate) fn append_stream_post(&mut self, post: TopicPost) -> bool {
        let is_new = !self.raw_stream_ids.contains(&post.id);
        if is_new {
            self.raw_stream_ids.push(post.id);
        }
        self.merge_posts(std::iter::once(post));
        self.recompute_loaded_state();
        is_new
    }

    pub(crate) fn missing_ids_in_range(&self, range: std::ops::Range<usize>) -> Vec<u64> {
        let end = range.end.min(self.raw_stream_ids.len());
        let start = range.start.min(end);
        self.raw_stream_ids[start..end]
            .iter()
            .copied()
            .filter(|post_id| !self.is_satisfied_post_id(*post_id))
            .collect()
    }

    pub(crate) fn loaded_post_numbers_in_range(&self, range: std::ops::Range<usize>) -> Vec<u32> {
        let end = range.end.min(self.raw_stream_ids.len());
        let start = range.start.min(end);
        self.raw_stream_ids[start..end]
            .iter()
            .filter_map(|post_id| self.posts_by_id.get(post_id).map(|post| post.post_number))
            .collect()
    }

    pub(super) fn new(init: TopicDetailSourceSessionInit) -> Self {
        let TopicDetailSourceSessionInit {
            session_epoch,
            header,
            body_post,
            focused_post_number,
            raw_stream_ids,
            cached_posts,
            unavailable_post_ids,
            load_more_policy,
        } = init;
        let mut posts_by_id = HashMap::new();
        let mut post_id_by_number = HashMap::new();

        post_id_by_number.insert(body_post.post_number, body_post.id);
        posts_by_id.insert(body_post.id, body_post.clone());

        for post in cached_posts {
            post_id_by_number.insert(post.post_number, post.id);
            posts_by_id.insert(post.id, post);
        }

        let mut session = Self {
            session_id: 0,
            session_epoch,
            header,
            body_post_id: body_post.id,
            body_post_number: body_post.post_number,
            focused_post_number,
            raw_stream_ids,
            posts_by_id,
            post_id_by_number,
            unavailable_post_ids,
            loaded_ranges: Vec::new(),
            next_stream_offset: 0,
            last_loaded_post_id: None,
            source_exhausted: false,
            load_more_policy,
        };
        session.recompute_loaded_state();
        session
    }

    pub(super) fn with_session_id(mut self, session_id: u64) -> Self {
        self.session_id = session_id;
        self
    }

    pub(super) fn posts_for_ids(&self, post_ids: &[u64]) -> Vec<TopicPost> {
        post_ids
            .iter()
            .filter_map(|post_id| self.posts_by_id.get(post_id).cloned())
            .collect()
    }

    pub(crate) fn merge_posts(&mut self, posts: impl IntoIterator<Item = TopicPost>) {
        for mut post in posts {
            self.unavailable_post_ids.remove(&post.id);
            self.post_id_by_number.insert(post.post_number, post.id);
            if let Some(existing) = self.posts_by_id.get(&post.id) {
                post.reuse_presentation_from(existing);
            }
            self.posts_by_id.insert(post.id, post);
        }
    }
    pub(crate) fn mark_unavailable(&mut self, post_ids: HashSet<u64>) {
        for post_id in post_ids {
            if !self.posts_by_id.contains_key(&post_id) {
                self.unavailable_post_ids.insert(post_id);
            }
        }
    }

    pub(crate) fn recompute_loaded_state(&mut self) {
        self.loaded_ranges.clear();
        let mut active_range_start: Option<usize> = None;
        let mut active_range_first_post_id: Option<u64> = None;

        for (offset, post_id) in self.raw_stream_ids.iter().copied().enumerate() {
            if self.is_satisfied_post_id(post_id) {
                if active_range_start.is_none() {
                    active_range_start = Some(offset);
                    active_range_first_post_id = Some(post_id);
                }
                continue;
            }

            if let Some(start_offset) = active_range_start.take() {
                self.loaded_ranges.push(TopicLoadedRange {
                    start_offset: start_offset as u32,
                    end_offset_exclusive: offset as u32,
                    first_post_id: active_range_first_post_id
                        .take()
                        .unwrap_or(self.raw_stream_ids[start_offset]),
                    last_post_id: self.raw_stream_ids[offset.saturating_sub(1)],
                });
            }
        }

        if let Some(start_offset) = active_range_start {
            self.loaded_ranges.push(TopicLoadedRange {
                start_offset: start_offset as u32,
                end_offset_exclusive: self.raw_stream_ids.len() as u32,
                first_post_id: active_range_first_post_id
                    .unwrap_or(self.raw_stream_ids[start_offset]),
                last_post_id: self
                    .raw_stream_ids
                    .last()
                    .copied()
                    .unwrap_or(self.body_post_id),
            });
        }

        self.next_stream_offset = self
            .raw_stream_ids
            .iter()
            .take_while(|post_id| self.is_satisfied_post_id(**post_id))
            .count();
        self.last_loaded_post_id = self
            .next_stream_offset
            .checked_sub(1)
            .and_then(|offset| self.raw_stream_ids.get(offset).copied());
        self.source_exhausted = self.next_stream_offset >= self.raw_stream_ids.len();
    }

    pub(super) fn source_cursor(&self) -> Option<TopicSourceCursor> {
        (!self.source_exhausted).then_some(TopicSourceCursor {
            topic_id: self.header.topic_id,
            session_id: self.session_id,
            next_stream_offset: self.next_stream_offset as u32,
            last_loaded_post_id: self.last_loaded_post_id,
            batch_size: self.load_more_policy.batch_size,
        })
    }

    pub(crate) fn source_snapshot(&self) -> TopicDetailSourceSnapshot {
        TopicDetailSourceSnapshot {
            header: self.header.clone(),
            body: TopicBody {
                post: self.body_post(),
            },
            raw_stream_ids: self.raw_stream_ids.clone(),
            loaded_posts: self.ordered_loaded_posts(),
            loaded_ranges: self.loaded_ranges.clone(),
            source_cursor: self.source_cursor(),
            source_exhausted: self.source_exhausted,
            focused_post_number: self.focused_post_number,
        }
    }

    fn body_post(&self) -> TopicPost {
        self.posts_by_id
            .get(&self.body_post_id)
            .cloned()
            .or_else(|| {
                self.post_id_by_number
                    .get(&self.body_post_number)
                    .and_then(|post_id| self.posts_by_id.get(post_id))
                    .cloned()
            })
            .expect("topic detail source session missing body post")
    }

    fn ordered_loaded_posts(&self) -> Vec<TopicPost> {
        merge_topic_posts(
            &self.raw_stream_ids,
            self.posts_by_id.values().cloned().collect(),
            Vec::new(),
        )
    }

    fn is_satisfied_post_id(&self, post_id: u64) -> bool {
        self.posts_by_id.contains_key(&post_id) || self.unavailable_post_ids.contains(&post_id)
    }
}

#[cfg(test)]
mod tests {
    use super::super::super::posts::ordered_unique_post_ids;
    use super::super::gained_visible_root_progress;
    use super::*;
    use fire_models::{TopicHeader, TopicPost};
    use std::collections::HashSet;

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
    fn ordered_unique_post_ids_drops_zeroes_and_duplicates() {
        assert_eq!(
            ordered_unique_post_ids(vec![0, 2, 2, 3, 0, 4, 3]),
            vec![2, 3, 4]
        );
    }

    #[test]
    fn source_session_tracks_contiguous_loaded_ranges_and_unavailable_post_ids() {
        let body_post = make_topic_post(1, None);
        let second_post = make_topic_post(2, Some(1));
        let fourth_post = make_topic_post(4, Some(1));
        let mut session = TopicDetailSourceSession::new(TopicDetailSourceSessionInit {
            session_epoch: 3,
            header: TopicHeader {
                topic_id: 42,
                ..TopicHeader::default()
            },
            body_post: body_post.clone(),
            focused_post_number: None,
            raw_stream_ids: vec![body_post.id, second_post.id, 3, fourth_post.id],
            cached_posts: vec![body_post.clone(), second_post.clone(), fourth_post.clone()],
            unavailable_post_ids: HashSet::new(),
            load_more_policy: TopicLoadMorePolicy {
                batch_size: 40,
                max_auto_batches_per_gesture: 3,
                max_auto_posts_per_gesture: 120,
                require_new_root_progress: true,
            },
        });

        assert_eq!(session.next_stream_offset, 2);
        assert_eq!(session.last_loaded_post_id, Some(2));
        assert_eq!(
            session
                .loaded_ranges
                .iter()
                .map(|range| (range.start_offset, range.end_offset_exclusive))
                .collect::<Vec<_>>(),
            vec![(0, 2), (3, 4)]
        );
        assert!(!session.source_exhausted);

        session.mark_unavailable(HashSet::from([3]));
        session.recompute_loaded_state();

        assert_eq!(session.next_stream_offset, 4);
        assert_eq!(session.last_loaded_post_id, Some(4));
        assert!(session.source_exhausted);
        assert_eq!(
            session
                .loaded_ranges
                .iter()
                .map(|range| (range.start_offset, range.end_offset_exclusive))
                .collect::<Vec<_>>(),
            vec![(0, 4)]
        );
    }

    #[test]
    fn gained_visible_root_progress_detects_new_root_post_numbers() {
        assert!(!gained_visible_root_progress(&[2, 5], &[2, 5]));
        assert!(gained_visible_root_progress(&[2, 5], &[2, 5, 8]));
    }
}
