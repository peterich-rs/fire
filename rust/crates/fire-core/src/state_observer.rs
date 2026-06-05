use std::{
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use fire_models::{NotificationState, SessionSnapshot, TopicDetailFeedSnapshot, TopicListResponse};
use tracing::warn;

pub type SessionObserverFn = Arc<dyn Fn(SessionSnapshot) + Send + Sync>;
pub type TopicListObserverFn = Arc<dyn Fn(TopicListResponse) + Send + Sync>;
pub type TopicDetailFeedObserverFn = Arc<dyn Fn(TopicDetailFeedSnapshot) + Send + Sync>;
pub type NotificationObserverFn = Arc<dyn Fn(NotificationState) + Send + Sync>;

const OBSERVER_DEBOUNCE_WINDOW: Duration = Duration::from_millis(100);

#[derive(Clone)]
struct DebouncedEmitter<T>
where
    T: Clone + Send + 'static,
{
    callback: Arc<dyn Fn(T) + Send + Sync>,
    pending: Arc<Mutex<Option<T>>>,
    scheduled: Arc<AtomicBool>,
}

impl<T> DebouncedEmitter<T>
where
    T: Clone + Send + 'static,
{
    fn new(callback: Arc<dyn Fn(T) + Send + Sync>) -> Self {
        Self {
            callback,
            pending: Arc::new(Mutex::new(None)),
            scheduled: Arc::new(AtomicBool::new(false)),
        }
    }

    fn emit(&self, value: T) {
        *self
            .pending
            .lock()
            .expect("observer pending mutex poisoned") = Some(value);

        if self.scheduled.swap(true, Ordering::SeqCst) {
            return;
        }

        let pending = self.pending.clone();
        let scheduled = self.scheduled.clone();
        let callback = self.callback.clone();
        tokio::spawn(async move {
            tokio::time::sleep(OBSERVER_DEBOUNCE_WINDOW).await;
            let next = pending
                .lock()
                .expect("observer pending mutex poisoned")
                .take();
            scheduled.store(false, Ordering::SeqCst);
            if let Some(snapshot) = next {
                if catch_unwind(AssertUnwindSafe(|| (callback)(snapshot))).is_err() {
                    warn!("state observer callback panicked");
                }
            }
        });
    }
}

#[derive(Clone)]
pub struct FireStateObserverCallbacks {
    pub session: SessionObserverFn,
    pub topic_list: TopicListObserverFn,
    pub topic_detail_feed: TopicDetailFeedObserverFn,
    pub notification_center: NotificationObserverFn,
}

#[derive(Clone, Default)]
pub struct FireStateObserverRegistry {
    inner: Arc<Mutex<Option<FireStateObserverEmitters>>>,
}

#[derive(Clone)]
struct FireStateObserverEmitters {
    session: DebouncedEmitter<SessionSnapshot>,
    topic_list: DebouncedEmitter<TopicListResponse>,
    topic_detail_feed: DebouncedEmitter<TopicDetailFeedSnapshot>,
    notification_center: DebouncedEmitter<NotificationState>,
}

impl FireStateObserverRegistry {
    pub fn set(&self, callbacks: FireStateObserverCallbacks) {
        *self.inner.lock().expect("state observer mutex poisoned") =
            Some(FireStateObserverEmitters {
                session: DebouncedEmitter::new(callbacks.session),
                topic_list: DebouncedEmitter::new(callbacks.topic_list),
                topic_detail_feed: DebouncedEmitter::new(callbacks.topic_detail_feed),
                notification_center: DebouncedEmitter::new(callbacks.notification_center),
            });
    }

    pub fn clear(&self) {
        *self.inner.lock().expect("state observer mutex poisoned") = None;
    }

    pub fn notify_session(&self, snapshot: SessionSnapshot) {
        if let Some(emitters) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            emitters.session.emit(snapshot);
        }
    }

    pub fn notify_topic_list(&self, snapshot: TopicListResponse) {
        if let Some(emitters) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            emitters.topic_list.emit(snapshot);
        }
    }

    pub fn notify_topic_detail_feed(&self, snapshot: TopicDetailFeedSnapshot) {
        if let Some(emitters) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            emitters.topic_detail_feed.emit(snapshot);
        }
    }

    pub fn notify_notification_center(&self, snapshot: NotificationState) {
        if let Some(emitters) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            emitters.notification_center.emit(snapshot);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::{Arc, Mutex};

    use fire_models::{BootstrapArtifacts, CookieSnapshot, SessionSnapshot, TopicListResponse};

    use super::{FireStateObserverCallbacks, FireStateObserverRegistry};

    fn sample_session(base_url: &str) -> SessionSnapshot {
        SessionSnapshot {
            cookies: CookieSnapshot::default(),
            bootstrap: BootstrapArtifacts {
                base_url: base_url.to_string(),
                ..BootstrapArtifacts::default()
            },
            browser_user_agent: None,
        }
    }

    #[tokio::test]
    async fn session_notifications_are_debounced_to_latest_snapshot() {
        let registry = FireStateObserverRegistry::default();
        let observed = Arc::new(Mutex::new(Vec::new()));
        let observed_clone = observed.clone();
        registry.set(FireStateObserverCallbacks {
            session: Arc::new(move |snapshot| {
                observed_clone
                    .lock()
                    .expect("observed mutex poisoned")
                    .push(snapshot.bootstrap.base_url);
            }),
            topic_list: Arc::new(|_: TopicListResponse| {}),
            topic_detail_feed: Arc::new(|_| {}),
            notification_center: Arc::new(|_| {}),
        });

        registry.notify_session(sample_session("https://one.example"));
        registry.notify_session(sample_session("https://two.example"));
        registry.notify_session(sample_session("https://three.example"));

        tokio::time::sleep(super::OBSERVER_DEBOUNCE_WINDOW + std::time::Duration::from_millis(30))
            .await;

        let observed = observed.lock().expect("observed mutex poisoned");
        assert_eq!(observed.as_slice(), ["https://three.example"]);
    }

    #[tokio::test]
    async fn observer_panics_are_isolated() {
        let registry = FireStateObserverRegistry::default();
        registry.set(FireStateObserverCallbacks {
            session: Arc::new(|_| panic!("boom")),
            topic_list: Arc::new(|_: TopicListResponse| {}),
            topic_detail_feed: Arc::new(|_| {}),
            notification_center: Arc::new(|_| {}),
        });

        registry.notify_session(sample_session("https://panic.example"));
        tokio::time::sleep(super::OBSERVER_DEBOUNCE_WINDOW + std::time::Duration::from_millis(30))
            .await;
    }
}
