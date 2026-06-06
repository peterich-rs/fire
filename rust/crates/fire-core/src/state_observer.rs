use std::{
    future::Future,
    panic::{catch_unwind, AssertUnwindSafe},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex, MutexGuard, OnceLock,
    },
    time::Duration,
};

use fire_models::{NotificationState, SessionSnapshot, TopicListResponse};
use tokio::runtime::{Builder, Handle, Runtime};
use tracing::warn;

pub type SessionObserverFn = Arc<dyn Fn(SessionSnapshot) + Send + Sync>;
pub type TopicListObserverFn = Arc<dyn Fn(TopicListResponse) + Send + Sync>;
pub type NotificationObserverFn = Arc<dyn Fn(NotificationState) + Send + Sync>;

const OBSERVER_DEBOUNCE_WINDOW: Duration = Duration::from_millis(100);

fn observer_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("fire-state-observer")
            .build()
            .expect("failed to create state observer runtime")
    })
}

fn spawn_observer_task<F>(future: F)
where
    F: Future<Output = ()> + Send + 'static,
{
    if let Ok(handle) = Handle::try_current() {
        handle.spawn(future);
    } else {
        observer_runtime().spawn(future);
    }
}

fn lock_or_recover<'a, T>(mutex: &'a Mutex<T>, name: &'static str) -> MutexGuard<'a, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            warn!(mutex = name, "state observer mutex poisoned; recovering");
            poisoned.into_inner()
        }
    }
}

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
        *lock_or_recover(&self.pending, "observer pending") = Some(value);

        if self.scheduled.swap(true, Ordering::SeqCst) {
            return;
        }

        let pending = self.pending.clone();
        let scheduled = self.scheduled.clone();
        let callback = self.callback.clone();
        spawn_observer_task(async move {
            tokio::time::sleep(OBSERVER_DEBOUNCE_WINDOW).await;
            let next = lock_or_recover(&pending, "observer pending").take();
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
    notification_center: DebouncedEmitter<NotificationState>,
}

impl FireStateObserverRegistry {
    pub fn set(&self, callbacks: FireStateObserverCallbacks) {
        *lock_or_recover(&self.inner, "state observer registry") =
            Some(FireStateObserverEmitters {
                session: DebouncedEmitter::new(callbacks.session),
                topic_list: DebouncedEmitter::new(callbacks.topic_list),
                notification_center: DebouncedEmitter::new(callbacks.notification_center),
            });
    }

    pub fn clear(&self) {
        *lock_or_recover(&self.inner, "state observer registry") = None;
    }

    pub fn notify_session(&self, snapshot: SessionSnapshot) {
        let emitters = { lock_or_recover(&self.inner, "state observer registry").clone() };
        if let Some(emitters) = emitters {
            emitters.session.emit(snapshot);
        }
    }

    pub fn notify_topic_list(&self, snapshot: TopicListResponse) {
        let emitters = { lock_or_recover(&self.inner, "state observer registry").clone() };
        if let Some(emitters) = emitters {
            emitters.topic_list.emit(snapshot);
        }
    }

    pub fn notify_notification_center(&self, snapshot: NotificationState) {
        let emitters = { lock_or_recover(&self.inner, "state observer registry").clone() };
        if let Some(emitters) = emitters {
            emitters.notification_center.emit(snapshot);
        }
    }
}

#[cfg(test)]
mod tests {
    use std::{
        sync::{mpsc, Arc, Mutex},
        time::Duration,
    };

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
            notification_center: Arc::new(|_| {}),
        });

        registry.notify_session(sample_session("https://panic.example"));
        tokio::time::sleep(super::OBSERVER_DEBOUNCE_WINDOW + std::time::Duration::from_millis(30))
            .await;
    }

    #[test]
    fn session_notifications_fall_back_without_existing_tokio_runtime() {
        let registry = FireStateObserverRegistry::default();
        let (sender, receiver) = mpsc::channel();
        registry.set(FireStateObserverCallbacks {
            session: Arc::new(move |snapshot| {
                sender
                    .send(snapshot.bootstrap.base_url)
                    .expect("session observer send");
            }),
            topic_list: Arc::new(|_: TopicListResponse| {}),
            notification_center: Arc::new(|_| {}),
        });

        registry.notify_session(sample_session("https://runtime.example"));

        let observed = receiver
            .recv_timeout(super::OBSERVER_DEBOUNCE_WINDOW + Duration::from_secs(1))
            .expect("session observer callback");
        assert_eq!(observed, "https://runtime.example");
    }
}
