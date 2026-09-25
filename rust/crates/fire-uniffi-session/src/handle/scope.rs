use fire_uniffi_types::{run_infallible, FireUniFfiError};

use crate::records::*;
use crate::FireSessionHandle;

#[uniffi::export]
impl FireSessionHandle {
    pub fn current_home_topic_list_scope(
        &self,
    ) -> Result<HomeTopicListScopeState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "current_home_topic_list_scope",
            |inner| inner.current_home_topic_list_scope().into(),
        )
    }
    pub fn set_current_home_topic_list_scope(
        &self,
        scope: HomeTopicListScopeState,
    ) -> Result<HomeTopicListScopeState, FireUniFfiError> {
        run_infallible(
            &self.shared.panic_state,
            &self.shared.core,
            "set_current_home_topic_list_scope",
            move |inner| inner.set_current_home_topic_list_scope(scope.into()).into(),
        )
    }
}
