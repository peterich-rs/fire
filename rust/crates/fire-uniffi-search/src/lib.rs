uniffi::setup_scaffolding!("fire_uniffi_search");

use std::sync::Arc;

use fire_uniffi_types::{run_on_ffi_runtime, FireUniFfiError, SharedFireCore};

pub mod records;

pub use records::{
    GroupedSearchResultState, SearchPostState, SearchQueryState, SearchResultState,
    SearchTopicState, SearchTypeFilterState, SearchUserState, TagSearchItemState,
    TagSearchQueryState, TagSearchResultState, UserMentionGroupState, UserMentionQueryState,
    UserMentionResultState, UserMentionUserState,
};

#[derive(uniffi::Object)]
pub struct FireSearchHandle {
    shared: Arc<SharedFireCore>,
}

impl FireSearchHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireSearchHandle {
    pub async fn search(
        &self,
        query: SearchQueryState,
    ) -> Result<SearchResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("search", panic_state, async move {
            inner.search(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn search_tags(
        &self,
        query: TagSearchQueryState,
    ) -> Result<TagSearchResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("search_tags", panic_state, async move {
            inner.search_tags(query.into()).await
        })
        .await?;
        Ok(response.into())
    }

    pub async fn search_users(
        &self,
        query: UserMentionQueryState,
    ) -> Result<UserMentionResultState, FireUniFfiError> {
        let inner = self.shared.core.clone();
        let panic_state = self.shared.panic_state.clone();
        let response = run_on_ffi_runtime("search_users", panic_state, async move {
            inner.search_users(query.into()).await
        })
        .await?;
        Ok(response.into())
    }
}
