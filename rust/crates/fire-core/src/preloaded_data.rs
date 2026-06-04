use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use fire_models::{CurrentUserSnapshot, PreloadedDataResult, PreloadedDataState};
use serde_json::Value;
use tracing::{info, warn};

use crate::core::FireCore;
use crate::error::FireCoreError;
use crate::parsing::parse_home_state;

pub struct PreloadedDataService {
    core: Arc<FireCore>,
    loading: AtomicBool,
    result: std::sync::Mutex<Option<PreloadedDataResult>>,
}

impl PreloadedDataService {
    pub fn new(core: Arc<FireCore>) -> Self {
        Self {
            core,
            loading: AtomicBool::new(false),
            result: std::sync::Mutex::new(None),
        }
    }

    pub fn state(&self) -> PreloadedDataState {
        if self.loading.load(Ordering::Acquire) {
            return PreloadedDataState::Loading;
        }
        let guard = self.result.lock().unwrap();
        match guard.as_ref() {
            Some(_) => PreloadedDataState::Ready,
            None => PreloadedDataState::NotStarted,
        }
    }

    pub async fn ensure_loaded(&self) -> Result<PreloadedDataState, FireCoreError> {
        {
            let guard = self.result.lock().unwrap();
            if guard.is_some() {
                return Ok(PreloadedDataState::Ready);
            }
        }

        if self
            .loading
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Ok(PreloadedDataState::Loading);
        }

        let result = self.fetch_and_parse().await;

        self.loading.store(false, Ordering::Release);

        match result {
            Ok(data) => {
                let mut guard = self.result.lock().unwrap();
                *guard = Some(data);
                Ok(PreloadedDataState::Ready)
            }
            Err(e) => {
                warn!(error = %e, "preloaded data fetch failed");
                Err(e)
            }
        }
    }

    pub fn get_result(&self) -> Option<PreloadedDataResult> {
        self.result.lock().unwrap().clone()
    }

    pub fn get_current_user(&self) -> Option<CurrentUserSnapshot> {
        self.result
            .lock()
            .unwrap()
            .as_ref()
            .and_then(|r| r.current_user.clone())
    }

    async fn fetch_and_parse(&self) -> Result<PreloadedDataResult, FireCoreError> {
        let base_url = self.core.base_url().trim_end_matches('/').to_string();
        let html = self.fetch_home_html().await?;
        let parsed = parse_home_state(&base_url, &html);

        let mut result = PreloadedDataResult::default();

        if let Some(preloaded_json) = &parsed.bootstrap_patch.preloaded_json {
            self.extract_preloaded_fields(preloaded_json, &mut result);
        }

        result.enabled_reaction_ids = parsed.bootstrap_patch.enabled_reaction_ids.clone();
        result.categories = parsed.bootstrap_patch.categories.clone();
        result.top_tags = parsed.bootstrap_patch.top_tags.clone();
        result.can_tag_topics = if parsed.bootstrap_patch.can_tag_topics {
            Some(true)
        } else {
            None
        };

        if let Some(user) = &result.current_user {
            self.cache_current_user(user);
        }

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

    fn extract_preloaded_fields(&self, preloaded_json: &str, result: &mut PreloadedDataResult) {
        let Ok(decoded) = html_entity_decode(preloaded_json) else {
            warn!("failed to HTML-decode preloaded JSON");
            return;
        };
        let Ok(parsed): Result<HashMap<String, Value>, _> = serde_json::from_str(&decoded) else {
            warn!("failed to parse preloaded JSON as map");
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

fn html_entity_decode(input: &str) -> Result<String, ()> {
    let mut result = input.to_string();
    result = result.replace("&quot;", "\"");
    result = result.replace("&amp;", "&");
    result = result.replace("&lt;", "<");
    result = result.replace("&gt;", ">");
    result = result.replace("&#39;", "'");
    Ok(result)
}
