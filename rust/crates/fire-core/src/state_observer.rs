use std::sync::{Arc, Mutex};

use fire_models::{NotificationState, SessionSnapshot, TopicDetailFeedSnapshot, TopicListResponse};

pub type SessionObserverFn = Arc<dyn Fn(SessionSnapshot) + Send + Sync>;
pub type TopicListObserverFn = Arc<dyn Fn(TopicListResponse) + Send + Sync>;
pub type TopicDetailFeedObserverFn = Arc<dyn Fn(TopicDetailFeedSnapshot) + Send + Sync>;
pub type NotificationObserverFn = Arc<dyn Fn(NotificationState) + Send + Sync>;

#[derive(Clone)]
pub struct FireStateObserverCallbacks {
    pub session: SessionObserverFn,
    pub topic_list: TopicListObserverFn,
    pub topic_detail_feed: TopicDetailFeedObserverFn,
    pub notification_center: NotificationObserverFn,
}

#[derive(Clone, Default)]
pub struct FireStateObserverRegistry {
    inner: Arc<Mutex<Option<FireStateObserverCallbacks>>>,
}

impl FireStateObserverRegistry {
    pub fn set(&self, callbacks: FireStateObserverCallbacks) {
        *self.inner.lock().expect("state observer mutex poisoned") = Some(callbacks);
    }

    pub fn clear(&self) {
        *self.inner.lock().expect("state observer mutex poisoned") = None;
    }

    pub fn notify_session(&self, snapshot: SessionSnapshot) {
        if let Some(callbacks) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            (callbacks.session)(snapshot);
        }
    }

    pub fn notify_topic_list(&self, snapshot: TopicListResponse) {
        if let Some(callbacks) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            (callbacks.topic_list)(snapshot);
        }
    }

    pub fn notify_topic_detail_feed(&self, snapshot: TopicDetailFeedSnapshot) {
        if let Some(callbacks) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            (callbacks.topic_detail_feed)(snapshot);
        }
    }

    pub fn notify_notification_center(&self, snapshot: NotificationState) {
        if let Some(callbacks) = self
            .inner
            .lock()
            .expect("state observer mutex poisoned")
            .clone()
        {
            (callbacks.notification_center)(snapshot);
        }
    }
}
