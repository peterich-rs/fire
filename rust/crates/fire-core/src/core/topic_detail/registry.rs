use std::{
    collections::HashMap,
    sync::{Arc, Mutex, OnceLock},
};

use fire_models::{ReadPathLoginRequest, TopicHomeRowCountPatch, TopicListResponse};
use tokio::sync::mpsc;
use tracing::warn;

use super::super::topic_detail_project::{apply_patch_to_row, apply_patch_to_summary};
use super::super::topics::topic_list_cache_scope_key;
use super::super::FireCore;
use super::actor::run_actor;
use super::*;

struct Slot {
    session: Arc<TopicDetailSession>,
    owners: HashMap<String, Arc<dyn TopicDetailObserver>>,
}

struct LoginWaiter {
    generation: u64,
    topic_id: u64,
    track_visit: bool,
}

#[derive(Default)]
struct RegistryInner {
    sessions: HashMap<u64, Slot>,
    login_waiters: Vec<LoginWaiter>,
}

pub struct TopicDetailSessionRegistry {
    inner: Mutex<RegistryInner>,
}

impl Default for TopicDetailSessionRegistry {
    fn default() -> Self {
        Self {
            inner: Mutex::new(RegistryInner::default()),
        }
    }
}

impl TopicDetailSessionRegistry {
    pub fn open(
        &self,
        core: &FireCore,
        request: TopicDetailOpenRequest,
        observer: Arc<dyn TopicDetailObserver>,
    ) -> Arc<TopicDetailSession> {
        let topic_id = request.topic_id;
        let owner = request.owner_token.clone();
        let mut guard = self.inner.lock().expect("topic detail registry poisoned");
        if let Some(slot) = guard.sessions.get_mut(&topic_id) {
            slot.owners.insert(owner, observer);
            let owners = slot.owners.clone();
            let session = Arc::clone(&slot.session);
            drop(guard);
            let _ = session.tx.send(Command::SyncOwners {
                owners,
                open: Some(request),
            });
            return session;
        }
        let (tx, rx) = mpsc::unbounded_channel();
        let session = Arc::new(TopicDetailSession {
            topic_id,
            owner_token: owner.clone(),
            tx,
        });
        let mut owners = HashMap::new();
        owners.insert(owner, observer);
        guard.sessions.insert(
            topic_id,
            Slot {
                session: Arc::clone(&session),
                owners: owners.clone(),
            },
        );
        drop(guard);
        let core = core.clone();
        let command_tx = session.tx.clone();
        spawn_actor(async move {
            run_actor(core, topic_id, command_tx, rx).await;
        });
        let _ = session.tx.send(Command::SyncOwners {
            owners,
            open: Some(request),
        });
        session
    }

    pub fn release(&self, topic_id: u64, owner_token: &str) {
        let mut guard = self.inner.lock().expect("topic detail registry poisoned");
        let Some(slot) = guard.sessions.get_mut(&topic_id) else {
            return;
        };
        slot.owners.remove(owner_token);
        if slot.owners.is_empty() {
            let session = guard.sessions.remove(&topic_id).map(|slot| slot.session);
            self.inner_clear_waiters(&mut guard, topic_id);
            drop(guard);
            if let Some(session) = session {
                let _ = session.tx.send(Command::Shutdown);
            }
        } else {
            let owners = slot.owners.clone();
            let session = Arc::clone(&slot.session);
            drop(guard);
            let _ = session.tx.send(Command::SyncOwners { owners, open: None });
        }
    }

    pub fn close_all(&self) {
        let mut guard = self.inner.lock().expect("topic detail registry poisoned");
        let sessions = guard
            .sessions
            .drain()
            .map(|(_, slot)| slot.session)
            .collect::<Vec<_>>();
        guard.login_waiters.clear();
        drop(guard);
        for session in sessions {
            let _ = session.tx.send(Command::Shutdown);
        }
    }

    pub fn cancel_inflight_http(&self) {
        let guard = self.inner.lock().expect("topic detail registry poisoned");
        let senders = guard
            .sessions
            .values()
            .map(|slot| slot.session.tx.clone())
            .collect::<Vec<_>>();
        drop(guard);
        for tx in senders {
            let _ = tx.send(Command::CancelHttp);
        }
    }

    pub fn complete_login(&self, generation: u64, succeeded: bool) {
        let mut guard = self.inner.lock().expect("topic detail registry poisoned");
        let waiters = guard
            .login_waiters
            .iter()
            .filter(|waiter| waiter.generation == generation)
            .cloned()
            .collect::<Vec<_>>();
        guard
            .login_waiters
            .retain(|waiter| waiter.generation != generation);
        let sessions = guard
            .sessions
            .iter()
            .map(|(id, slot)| (*id, slot.session.tx.clone()))
            .collect::<HashMap<_, _>>();
        drop(guard);
        if !succeeded {
            return;
        }
        for waiter in waiters {
            if let Some(tx) = sessions.get(&waiter.topic_id) {
                let _ = tx.send(Command::LoginReload {
                    track_visit: waiter.track_visit,
                });
            }
        }
    }

    pub(super) fn register_waiter(&self, generation: u64, topic_id: u64, track_visit: bool) {
        let mut guard = self.inner.lock().expect("topic detail registry poisoned");
        if guard
            .login_waiters
            .iter()
            .any(|waiter| waiter.generation == generation && waiter.topic_id == topic_id)
        {
            return;
        }
        guard.login_waiters.push(LoginWaiter {
            generation,
            topic_id,
            track_visit,
        });
    }

    fn inner_clear_waiters(&self, guard: &mut RegistryInner, topic_id: u64) {
        guard
            .login_waiters
            .retain(|waiter| waiter.topic_id != topic_id);
    }

    pub fn session_count(&self) -> usize {
        self.inner
            .lock()
            .expect("topic detail registry poisoned")
            .sessions
            .len()
    }
}

impl Clone for LoginWaiter {
    fn clone(&self) -> Self {
        Self {
            generation: self.generation,
            topic_id: self.topic_id,
            track_visit: self.track_visit,
        }
    }
}

fn spawn_actor(future: impl std::future::Future<Output = ()> + Send + 'static) {
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        handle.spawn(future);
        return;
    }
    static RUNTIME: OnceLock<tokio::runtime::Runtime> = OnceLock::new();
    let runtime = RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .thread_name("fire-topic-detail")
            .build()
            .expect("topic detail runtime")
    });
    runtime.spawn(future);
}

impl FireCore {
    pub fn open_topic_detail(
        &self,
        request: TopicDetailOpenRequest,
        observer: Arc<dyn TopicDetailObserver>,
    ) -> Arc<TopicDetailSession> {
        self.topic_detail_sessions.open(self, request, observer)
    }

    pub fn release_topic_detail_owner(&self, topic_id: u64, owner_token: &str) {
        self.topic_detail_sessions.release(topic_id, owner_token);
    }

    pub fn close_all_topic_detail_sessions(&self) {
        self.topic_detail_sessions.close_all();
    }

    pub fn cancel_topic_detail_http(&self) {
        self.topic_detail_sessions.cancel_inflight_http();
    }

    pub fn request_read_path_login(&self, operation: &str) -> u64 {
        let snapshot = {
            let mut session = crate::sync_utils::write_rwlock(&self.session, "session");
            if let Some(existing) = session.read_path_login_request.clone() {
                session.snapshot.read_path_login_request = Some(existing.clone());
                let generation = existing.generation;
                let snapshot = session.snapshot.clone();
                (snapshot, generation, false)
            } else {
                session.read_path_login_generation =
                    session.read_path_login_generation.saturating_add(1).max(1);
                let request = ReadPathLoginRequest {
                    generation: session.read_path_login_generation,
                    operation: operation.to_string(),
                };
                session.read_path_login_request = Some(request.clone());
                session.snapshot.read_path_login_request = Some(request);
                let generation = session.read_path_login_generation;
                (session.snapshot.clone(), generation, true)
            }
        };
        self.state_observers().notify_session(snapshot.0);
        snapshot.1
    }

    pub fn complete_read_path_login(&self, generation: u64, succeeded: bool) {
        let snapshot = {
            let mut session = crate::sync_utils::write_rwlock(&self.session, "session");
            let matches = session
                .read_path_login_request
                .as_ref()
                .is_some_and(|request| request.generation == generation);
            if !matches {
                return;
            }
            session.read_path_login_request = None;
            session.snapshot.read_path_login_request = None;
            session.snapshot.clone()
        };
        self.state_observers().notify_session(snapshot);
        self.topic_detail_sessions
            .complete_login(generation, succeeded);
    }

    pub(crate) fn patch_cached_home_topic_counts(&self, patch: &TopicHomeRowCountPatch) {
        let auth_scope_hash = self.current_auth_scope_hash();
        let scope_key = topic_list_cache_scope_key(&self.current_home_topic_list_query());
        let pages = {
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            match store.topic_list_cache_list_pages(&auth_scope_hash, &scope_key) {
                Ok(pages) => pages,
                Err(error) => {
                    warn!(error = %error, "failed to list cached home topic pages");
                    return;
                }
            }
        };
        for (page, payload) in pages {
            let mut cached: TopicListResponse = match serde_json::from_str(&payload) {
                Ok(cached) => cached,
                Err(_) => continue,
            };
            let row_flag = cached
                .rows
                .iter()
                .find(|row| row.topic.id == patch.topic_id)
                .map(|row| row.has_unread_posts);
            let mut changed = false;
            for topic in &mut cached.topics {
                if topic.id == patch.topic_id {
                    apply_patch_to_summary(topic, patch, row_flag);
                    changed = true;
                }
            }
            for row in &mut cached.rows {
                if row.topic.id == patch.topic_id {
                    apply_patch_to_row(row, patch);
                    changed = true;
                }
            }
            if !changed {
                continue;
            }
            let Ok(payload) = serde_json::to_string(&cached) else {
                continue;
            };
            let store = self
                .shared_store
                .lock()
                .expect("shared store mutex poisoned");
            if let Err(error) =
                store.topic_list_cache_write(&auth_scope_hash, &scope_key, page, &payload)
            {
                warn!(error = %error, "failed to write patched home topic page");
            }
        }
    }
}
