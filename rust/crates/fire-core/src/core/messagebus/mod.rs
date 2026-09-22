use std::{
    collections::BTreeMap,
    sync::{atomic::AtomicU64, Arc, Mutex, RwLock},
    time::Duration,
};

use fire_models::{MessageBusClientMode, MessageBusEvent, MessageBusSubscriptionScope};
use serde_json::Value;
use tokio::{
    runtime::Handle,
    sync::{mpsc::UnboundedSender, watch},
    task::JoinHandle,
};
use url::Url;

use super::{
    network::FireNetworkLayer, notifications::FireNotificationRuntime,
    presence::FireTopicPresenceRuntime, FireCore, FireSessionRuntimeState,
};
use crate::diagnostics::FireDiagnosticsStore;

const MESSAGE_BUS_OPERATION: &str = "message bus poll";
const INITIAL_MESSAGE_ID: i64 = -1;
const MAX_BACKOFF_DELAY: Duration = Duration::from_secs(15);
const MESSAGE_BUS_MIN_RESTART_INTERVAL: Duration = Duration::from_millis(150);
const BOOTSTRAP_TRACKING_OWNER_TOKEN: &str = "__bootstrap_tracking__";
const BOOTSTRAP_NOTIFICATION_OWNER_TOKEN: &str = "__bootstrap_notification__";
const BOOTSTRAP_LOGOUT_OWNER_TOKEN: &str = "__bootstrap_logout__";

static FOREGROUND_CLIENT_COUNTER: AtomicU64 = AtomicU64::new(1);
static MESSAGE_BUS_SEQUENCE_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Default)]
pub(crate) struct FireMessageBusRuntime {
    foreground_client_id: Option<String>,
    active_client_id: Option<String>,
    active_mode: Option<MessageBusClientMode>,
    runtime_handle: Option<Handle>,
    event_sender: Option<UnboundedSender<MessageBusEvent>>,
    subscriptions: BTreeMap<String, RuntimeSubscription>,
    subscription_revision: u64,
    subscription_updates: Option<watch::Sender<u64>>,
    poll_task_token: u64,
    poll_task: Option<JoinHandle<()>>,
    next_internal_listener_id: u64,
    internal_listeners: Vec<MessageBusInternalListener>,
}

#[derive(Clone)]
pub(crate) struct MessageBusInternalListener {
    pub id: u64,
    pub on_event: std::sync::Arc<dyn Fn(&MessageBusEvent) + Send + Sync>,
    pub on_stopped: std::sync::Arc<dyn Fn() + Send + Sync>,
    pub on_started: std::sync::Arc<dyn Fn() + Send + Sync>,
}

#[derive(Debug, Clone)]
struct RuntimeSubscription {
    last_message_id: i64,
    owners: BTreeMap<String, RuntimeSubscriptionOwner>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct RuntimeSubscriptionOwner {
    scope: MessageBusSubscriptionScope,
}

#[derive(Clone)]
struct MessageBusPollContext {
    core: FireCore,
    base_url: Url,
    network: FireNetworkLayer,
    diagnostics: Arc<FireDiagnosticsStore>,
    session: Arc<RwLock<FireSessionRuntimeState>>,
    runtime: Arc<Mutex<FireMessageBusRuntime>>,
    notifications: Arc<Mutex<FireNotificationRuntime>>,
    topic_presence: Arc<Mutex<FireTopicPresenceRuntime>>,
    event_sender: UnboundedSender<MessageBusEvent>,
    client_id: String,
    mode: MessageBusClientMode,
    task_token: u64,
}

enum PollIterationResult {
    Continue,
    Stop,
    Restart,
}

#[derive(Debug)]
struct RawMessageBusMessage {
    channel: String,
    message_id: i64,
    data: Value,
}

mod channels;
mod parse;
mod poll;
mod runtime;

pub(crate) use channels::{
    active_message_bus_client_id, message_bus_presence_channel_for_topic, upload_client_id,
};
pub(crate) use runtime::message_bus_requires_shared_session_key;
