use std::{
    future::Future,
    pin::Pin,
    sync::{Arc, Mutex},
};

use fire_models::{CookieSelfHealingRequest, CookieSelfHealingResult};

use super::FireCore;

pub(crate) type FireCookieSelfHealingFuture =
    Pin<Box<dyn Future<Output = CookieSelfHealingResult> + Send>>;
pub(crate) type FireCookieSelfHealingHandlerFn =
    Arc<dyn Fn(CookieSelfHealingRequest) -> FireCookieSelfHealingFuture + Send + Sync>;

#[derive(Clone, Default)]
pub(crate) struct FireCookieSelfHealingHandlerRegistry {
    inner: Arc<Mutex<Option<FireCookieSelfHealingHandlerFn>>>,
}

impl FireCookieSelfHealingHandlerRegistry {
    pub(crate) fn set(&self, handler: FireCookieSelfHealingHandlerFn) {
        *self
            .inner
            .lock()
            .expect("cookie self-healing handler mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("cookie self-healing handler mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireCookieSelfHealingHandlerFn> {
        self.inner
            .lock()
            .expect("cookie self-healing handler mutex poisoned")
            .clone()
    }
}

impl FireCore {
    pub fn set_cookie_self_healing_handler<F, Fut>(&self, handler: F)
    where
        F: Fn(CookieSelfHealingRequest) -> Fut + Send + Sync + 'static,
        Fut: Future<Output = CookieSelfHealingResult> + Send + 'static,
    {
        let handler = Arc::new(move |request: CookieSelfHealingRequest| {
            Box::pin(handler(request)) as FireCookieSelfHealingFuture
        });
        self.cookie_self_healing_handler.set(handler);
    }

    pub fn clear_cookie_self_healing_handler(&self) {
        self.cookie_self_healing_handler.clear();
    }
}
