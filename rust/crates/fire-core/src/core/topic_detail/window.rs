use std::ops::Range;

use super::super::FireCore;
use super::*;

impl ActorState {
    pub(super) fn expand_window_for_visible(&mut self, core: &FireCore, visible: &[u32]) {
        let Some(total) = core
            .with_topic_source_session_mut(self.topic_id, None, |session| session.raw_stream_len())
        else {
            return;
        };
        let indices = visible
            .iter()
            .filter_map(|post_number| {
                core.with_topic_source_session_mut(self.topic_id, None, |session| {
                    session.stream_index_for_post_number(*post_number)
                })
                .flatten()
            })
            .collect::<Vec<_>>();
        let Some(min_index) = indices.iter().copied().min() else {
            return;
        };
        let Some(max_index) = indices.iter().copied().max() else {
            return;
        };
        let threshold = TOPIC_DETAIL_PREFETCH_THRESHOLD as usize;
        let expand_back = self.window.requested.start > 0
            && min_index <= self.window.requested.start.saturating_add(threshold);
        let expand_forward = self.window.requested.end < total
            && max_index + 1
                >= self
                    .window
                    .requested
                    .end
                    .saturating_sub(threshold.saturating_add(1))
                    .max(self.window.requested.start);
        if expand_back || expand_forward {
            let lower = if expand_back {
                self.window
                    .requested
                    .start
                    .saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE)
            } else {
                self.window.requested.start
            };
            let upper = if expand_forward {
                self.window.requested.end + TOPIC_DETAIL_FORWARD_EXPANSION as usize
            } else {
                self.window.requested.end
            };
            let anchor = self.anchor_index(core);
            self.window.requested = bounded_range(lower, upper, total, anchor);
        }
    }

    pub(super) fn advance_toward_target(&mut self, core: &FireCore, target: u32) -> bool {
        let Some((total, current, loaded)) =
            core.with_topic_source_session_mut(self.topic_id, None, |session| {
                (
                    session.raw_stream_len(),
                    self.window.requested.clone(),
                    session.loaded_post_numbers_in_range(self.window.requested.clone()),
                )
            })
        else {
            return false;
        };
        let Some(next) = next_range_for_target(target, &current, total, &loaded) else {
            return false;
        };
        if next == self.window.requested {
            return false;
        }
        self.window.requested = next;
        true
    }

    pub(super) fn reset_window(&mut self, core: &FireCore) {
        let Some((total, loaded, anchor_index)) =
            core.with_topic_source_session_mut(self.topic_id, None, |session| {
                let total = session.raw_stream_len();
                let loaded = (0..total)
                    .filter(|index| session.missing_ids_in_range(*index..index + 1).is_empty())
                    .collect::<Vec<_>>();
                let anchor = self
                    .scroll_target
                    .and_then(|post_number| session.stream_index_for_post_number(post_number));
                (total, loaded, anchor)
            })
        else {
            return;
        };
        self.window.anchor = self.scroll_target;
        self.window.requested = initial_range(total, anchor_index, &loaded);
    }

    pub(super) fn extend_window_to_loaded(&mut self, core: &FireCore) {
        let Some(total) = core
            .with_topic_source_session_mut(self.topic_id, None, |session| session.raw_stream_len())
        else {
            return;
        };
        if self.window.requested.end >= total.saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE) {
            self.window.requested.end = total;
            self.window.requested = bounded_range(
                self.window.requested.start,
                self.window.requested.end,
                total,
                self.anchor_index(core),
            );
        }
    }

    pub(super) fn anchor_index(&self, core: &FireCore) -> Option<usize> {
        let anchor = self.window.anchor.or(self.scroll_target)?;
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.stream_index_for_post_number(anchor)
        })
        .flatten()
    }

    pub(super) fn should_load_tail(&self, item_count: u32, visible_max_item: Option<u32>) -> bool {
        let Some(visible_max_item) = visible_max_item else {
            return false;
        };
        let has_more = self
            .published
            .as_ref()
            .is_some_and(|snapshot| snapshot.has_more);
        item_count > 0
            && has_more
            && item_count.saturating_sub(visible_max_item) <= TOPIC_DETAIL_LIST_TAIL_THRESHOLD
    }

    pub(super) fn capture_header(&mut self, core: &FireCore) {
        self.header = core
            .clone_topic_source_snapshot(self.topic_id)
            .map(|snapshot| snapshot.header);
    }

    pub(super) fn restore_inflight_posts(&self, core: &FireCore) {
        if self.inflight_posts.is_empty() {
            return;
        }
        let posts = self.inflight_posts.clone();
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            for (post_id, post) in posts {
                if self.mutating.contains(&post_id) {
                    session.merge_posts(std::iter::once(post));
                }
            }
        });
    }
}

fn bounded_range(
    mut lower: usize,
    mut upper: usize,
    total: usize,
    anchor: Option<usize>,
) -> Range<usize> {
    if total == 0 {
        return 0..0;
    }
    lower = lower.min(total);
    upper = upper.max(lower).min(total);
    if lower == upper {
        upper = (lower + 1).min(total);
    }
    if upper - lower <= TOPIC_DETAIL_MAX_WINDOW {
        return lower..upper;
    }
    if let Some(anchor) = anchor {
        let max_lower = total.saturating_sub(TOPIC_DETAIL_MAX_WINDOW);
        let minimum = anchor.saturating_sub(TOPIC_DETAIL_MAX_WINDOW - 1);
        let maximum = anchor.min(max_lower);
        lower = minimum.max(lower.min(maximum));
        upper = (lower + TOPIC_DETAIL_MAX_WINDOW).min(total);
        lower = upper.saturating_sub(TOPIC_DETAIL_MAX_WINDOW);
        return lower..upper;
    }
    upper = (lower + TOPIC_DETAIL_MAX_WINDOW).min(total);
    lower = upper.saturating_sub(TOPIC_DETAIL_MAX_WINDOW);
    lower..upper
}

fn initial_range(total: usize, anchor: Option<usize>, loaded: &[usize]) -> Range<usize> {
    if total == 0 {
        return 0..0;
    }
    let loaded_lower = loaded.first().copied().unwrap_or(anchor.unwrap_or(0));
    let loaded_upper = loaded
        .last()
        .map(|index| index + 1)
        .unwrap_or((loaded_lower + 1).min(total));
    let desired_lower = if let Some(anchor) = anchor {
        anchor.saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE / 2)
    } else {
        loaded_lower.min(loaded_upper.saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE))
    };
    bounded_range(
        desired_lower.min(loaded_lower),
        loaded_upper.max(loaded_lower + TOPIC_DETAIL_HYDRATION_PAGE),
        total,
        anchor,
    )
}

fn next_range_for_target(
    post_number: u32,
    current: &Range<usize>,
    total: usize,
    loaded: &[u32],
) -> Option<Range<usize>> {
    if total == 0 || (current.start == 0 && current.end >= total) {
        return None;
    }
    let estimated = (post_number.saturating_sub(1) as usize).min(total - 1);
    if !current.contains(&estimated) {
        return Some(bounded_range(
            estimated.saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE / 2),
            estimated + TOPIC_DETAIL_HYDRATION_PAGE / 2 + 1,
            total,
            None,
        ));
    }
    let forward = if let Some(max_loaded) = loaded.iter().copied().max() {
        if post_number > max_loaded {
            true
        } else if loaded
            .iter()
            .copied()
            .min()
            .is_some_and(|min| post_number < min)
        {
            false
        } else {
            total - current.end >= current.start
        }
    } else {
        true
    };
    let next = if forward {
        bounded_range(
            current.start,
            current.end + TOPIC_DETAIL_FORWARD_EXPANSION as usize,
            total,
            None,
        )
    } else {
        bounded_range(
            current.start.saturating_sub(TOPIC_DETAIL_HYDRATION_PAGE),
            current.end,
            total,
            None,
        )
    };
    (next != *current).then_some(next)
}
