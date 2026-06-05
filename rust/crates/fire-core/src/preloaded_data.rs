use std::collections::HashMap;
use std::sync::Arc;

use fire_models::{
    BootstrapArtifacts, CurrentUserSnapshot, PreloadedDataResult, PreloadedDataState,
};
use tokio::sync::Notify;
use tracing::{info, warn};

use crate::core::FireCore;
use crate::error::FireCoreError;
use crate::parsing::{parse_home_state, parse_preloaded_payload};

#[derive(Clone)]
enum CachedPreloadedState {
    NotStarted,
    Loading,
    Ready(PreloadedDataResult),
    Failed(String),
}

pub struct PreloadedDataService {
    core: Arc<FireCore>,
    state: std::sync::Mutex<CachedPreloadedState>,
    notify: Notify,
}

impl PreloadedDataService {
    pub fn new(core: Arc<FireCore>) -> Self {
        Self {
            core,
            state: std::sync::Mutex::new(CachedPreloadedState::NotStarted),
            notify: Notify::new(),
        }
    }

    pub fn state(&self) -> PreloadedDataState {
        match &*self.state.lock().unwrap() {
            CachedPreloadedState::NotStarted => PreloadedDataState::NotStarted,
            CachedPreloadedState::Loading => PreloadedDataState::Loading,
            CachedPreloadedState::Ready(_) => PreloadedDataState::Ready,
            CachedPreloadedState::Failed(_) => PreloadedDataState::Failed,
        }
    }

    pub async fn ensure_loaded(&self) -> Result<PreloadedDataState, FireCoreError> {
        loop {
            let should_load = {
                let mut state = self.state.lock().unwrap();
                match &*state {
                    CachedPreloadedState::Ready(_) => return Ok(PreloadedDataState::Ready),
                    CachedPreloadedState::Loading => false,
                    CachedPreloadedState::NotStarted | CachedPreloadedState::Failed(_) => {
                        *state = CachedPreloadedState::Loading;
                        true
                    }
                }
            };

            if !should_load {
                self.notify.notified().await;
                continue;
            }

            let result = self.fetch_and_parse().await;
            match result {
                Ok(data) => {
                    self.store_result(data);
                    return Ok(PreloadedDataState::Ready);
                }
                Err(e) => {
                    warn!(error = %e, "preloaded data fetch failed");
                    let mut state = self.state.lock().unwrap();
                    *state = CachedPreloadedState::Failed(e.to_string());
                    drop(state);
                    self.notify.notify_waiters();
                    return Err(e);
                }
            }
        }
    }

    pub fn get_result(&self) -> Option<PreloadedDataResult> {
        match &*self.state.lock().unwrap() {
            CachedPreloadedState::Ready(result) => Some(result.clone()),
            _ => None,
        }
    }

    pub fn get_current_user(&self) -> Option<CurrentUserSnapshot> {
        self.get_result().and_then(|result| result.current_user)
    }

    pub fn last_error_message(&self) -> Option<String> {
        match &*self.state.lock().unwrap() {
            CachedPreloadedState::Failed(error) => Some(error.clone()),
            _ => None,
        }
    }

    pub fn sync_from_bootstrap(&self, bootstrap: &BootstrapArtifacts) {
        let has_preloaded_payload = bootstrap
            .preloaded_json
            .as_deref()
            .is_some_and(|value| !value.trim().is_empty())
            || bootstrap.has_preloaded_data;
        if !has_preloaded_payload {
            self.reset();
            return;
        }

        self.store_result(Self::result_from_bootstrap(bootstrap));
    }

    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        *state = CachedPreloadedState::NotStarted;
        drop(state);
        self.clear_cached_user();
        self.notify.notify_waiters();
    }

    async fn fetch_and_parse(&self) -> Result<PreloadedDataResult, FireCoreError> {
        let base_url = self.core.base_url().trim_end_matches('/').to_string();
        let html = self.fetch_home_html().await?;
        let parsed = parse_home_state(&base_url, &html);

        let result = Self::result_from_bootstrap(&parsed.bootstrap_patch);

        self.core.update_session(|session| {
            session.cookies.merge_patch(&parsed.cookies_patch);
            session.bootstrap.merge_patch(&parsed.bootstrap_patch);
        });

        Ok(result)
    }

    async fn fetch_home_html(&self) -> Result<String, FireCoreError> {
        let traced = self.core.build_home_request("preloaded data fetch")?;
        let (trace_id, response) = self.core.execute_request(traced).await?;
        let status = response.status();
        if !status.is_success() {
            return Err(FireCoreError::HttpStatus {
                operation: "preloaded data fetch",
                status: status.as_u16(),
                body: format!("homepage request returned {}", status),
            });
        }
        self.core.read_response_text(trace_id, response).await
    }

    fn result_from_bootstrap(bootstrap: &BootstrapArtifacts) -> PreloadedDataResult {
        let mut result = PreloadedDataResult::default();
        if let Some(preloaded_json) = bootstrap.preloaded_json.as_deref() {
            Self::extract_preloaded_fields(preloaded_json, &mut result);
        }
        result.enabled_reaction_ids = bootstrap.enabled_reaction_ids.clone();
        result.categories = bootstrap.categories.clone();
        result.top_tags = bootstrap.top_tags.clone();
        result.can_tag_topics = if bootstrap.can_tag_topics {
            Some(true)
        } else {
            None
        };
        result
    }

    fn store_result(&self, result: PreloadedDataResult) {
        if let Some(user) = &result.current_user {
            self.cache_current_user(user);
        } else {
            self.clear_cached_user();
        }
        let mut state = self.state.lock().unwrap();
        *state = CachedPreloadedState::Ready(result);
        drop(state);
        self.notify.notify_waiters();
    }

    fn extract_preloaded_fields(preloaded_json: &str, result: &mut PreloadedDataResult) {
        let Some(parsed) = parse_preloaded_payload(preloaded_json) else {
            warn!("failed to parse normalized preloaded JSON payload");
            return;
        };
        let Some(parsed) = parsed.as_object() else {
            warn!("normalized preloaded JSON payload was not an object");
            return;
        };

        if let Some(user_val) = parsed.get("currentUser") {
            match serde_json::from_value::<CurrentUserSnapshot>(user_val.clone()) {
                Ok(user) => {
                    info!(username = %user.username, "extracted currentUser from preloaded data");
                    result.current_user = Some(user);
                }
                Err(e) => {
                    warn!(error = %e, "failed to parse currentUser from preloaded data");
                }
            }
        }

        if let Some(val) = parsed.get("siteSettings").cloned() {
            result.site_settings = Some(val);
        }
        if let Some(val) = parsed.get("site").cloned() {
            result.site = Some(val);
        }
        if let Some(val) = parsed.get("topicTrackingStateMeta").cloned() {
            if let Ok(meta) = serde_json::from_value::<HashMap<String, u64>>(val) {
                result.topic_tracking_state_meta = Some(meta);
            }
        }
        if let Some(val) = parsed.get("topicTrackingStates").cloned() {
            result.topic_tracking_states = Some(serde_json::from_value(val).unwrap_or_default());
        }
        if let Some(val) = parsed.get("customEmoji").cloned() {
            result.custom_emoji = Some(serde_json::from_value(val).unwrap_or_default());
        }
        for key in &["topicList", "topic_list", "latest"] {
            if let Some(val) = parsed.get(*key).cloned() {
                result.topic_list = Some(val);
                break;
            }
        }
    }

    fn cache_current_user(&self, user: &CurrentUserSnapshot) {
        if let Ok(data) = serde_json::to_string(user) {
            let store = self
                .core
                .topic_feed_store
                .lock()
                .expect("topic feed store mutex poisoned");
            if let Err(e) = store.set_cached_user(&data) {
                warn!(error = %e, "failed to cache current user");
            }
        }
    }

    pub fn get_cached_user(&self) -> Option<CurrentUserSnapshot> {
        let store = self
            .core
            .topic_feed_store
            .lock()
            .expect("topic feed store mutex poisoned");
        let data = store.get_cached_user().ok()??;
        serde_json::from_str(&data).ok()
    }

    pub fn clear_cached_user(&self) {
        let store = self
            .core
            .topic_feed_store
            .lock()
            .expect("topic feed store mutex poisoned");
        let _ = store.clear_cached_user();
    }
}
