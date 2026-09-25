use fire_models::{
    LoadMoreTopicPostsQuery, TopicDetailPage, TopicDetailSourceQuery, TopicDetailSourceSnapshot,
    TopicLoadMoreOutcome,
};

use super::super::super::FireCore;
use crate::error::FireCoreError;

mod initial;
mod load_more;
mod page;

pub(crate) async fn load_topic_detail_source_snapshot(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailSourceSnapshot, FireCoreError> {
    core.load_topic_detail_source_snapshot_impl(query).await
}

pub(crate) async fn load_topic_detail_page(
    core: &FireCore,
    query: TopicDetailSourceQuery,
) -> Result<TopicDetailPage, FireCoreError> {
    core.load_topic_detail_page_impl(query).await
}

pub(crate) async fn load_more_topic_detail_posts(
    core: &FireCore,
    query: LoadMoreTopicPostsQuery,
) -> Result<TopicLoadMoreOutcome, FireCoreError> {
    core.load_more_topic_posts_impl(query).await
}
