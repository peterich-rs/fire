mod common;

use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc, Mutex,
};

use common::{
    raw_cloudflare_challenge_response, raw_json_response, raw_text_response, sample_home_html,
    sample_latest_json, sample_topic_detail_json, TestServer, TestServerStep,
};
use fire_core::{
    FireAuthRecoveryHint, FireAuthRecoveryHintReason, FireCore, FireCoreConfig, FireCoreError,
};
use fire_models::{
    CookieSelfHealingPhase, CookieSelfHealingResult, LoginSyncInput, PlatformCookie,
    TopicDetailQuery, TopicDetailSourceQuery, TopicListKind, TopicListQuery, TopicReplyRequest,
    TopicTag,
};
use serde_json::{json, Value};
use tokio::{
    sync::Notify,
    time::{sleep, Duration},
};

#[path = "network/auth_rotation.rs"]
mod auth_rotation;
#[path = "network/cloudflare.rs"]
mod cloudflare;
#[path = "network/cookie_healing.rs"]
mod cookie_healing;
#[path = "network/mutations.rs"]
mod mutations;
#[path = "network/session_refresh.rs"]
mod session_refresh;
#[path = "network/stale_responses.rs"]
mod stale_responses;
#[path = "network/topic_detail.rs"]
mod topic_detail;
#[path = "network/topic_list.rs"]
mod topic_list;
