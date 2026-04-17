use std::{
    any::Any,
    backtrace::Backtrace,
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};

use tracing::error;

use crate::error::FireUniFfiError;

#[derive(Default)]
pub struct PanicState {
    poisoned: AtomicBool,
    last_panic: Mutex<Option<String>>,
}

impl PanicState {
    pub fn ensure_healthy(&self, operation: &'static str) -> Result<(), FireUniFfiError> {
        if !self.poisoned.load(Ordering::SeqCst) {
            return Ok(());
        }

        let previous = self
            .last_panic
            .lock()
            .ok()
            .and_then(|guard| guard.clone())
            .unwrap_or_else(|| "unknown panic".to_string());
        Err(FireUniFfiError::Internal {
            details: format!(
                "fire core handle is poisoned by a previous panic ({previous}); recreate the handle before calling {operation}"
            ),
        })
    }

    pub fn capture_panic(
        &self,
        operation: &'static str,
        payload: &(dyn Any + Send),
    ) -> FireUniFfiError {
        let report = CapturedPanic::from_payload(operation, payload);
        report.log();
        self.poisoned.store(true, Ordering::SeqCst);
        if let Ok(mut last_panic) = self.last_panic.lock() {
            *last_panic = Some(report.summary());
        }
        FireUniFfiError::Internal {
            details: report.user_message(),
        }
    }
}

pub struct CapturedPanic {
    operation: &'static str,
    message: String,
    backtrace: String,
}

impl CapturedPanic {
    pub fn from_payload(operation: &'static str, payload: &(dyn Any + Send)) -> Self {
        Self {
            operation,
            message: panic_payload_to_string(payload),
            backtrace: Backtrace::force_capture().to_string(),
        }
    }

    pub fn summary(&self) -> String {
        format!("{} panicked: {}", self.operation, self.message)
    }

    pub fn user_message(&self) -> String {
        self.summary()
    }

    pub fn log(&self) {
        error!(
            operation = self.operation,
            panic_message = %self.message,
            backtrace = %self.backtrace,
            "caught panic across fire-uniffi boundary"
        );
        if cfg!(debug_assertions) {
            eprintln!(
                "fire-uniffi caught panic in {}: {}\nbacktrace:\n{}",
                self.operation, self.message, self.backtrace
            );
        }
    }
}

pub fn panic_payload_to_string(payload: &(dyn Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&'static str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "non-string panic payload".to_string()
    }
}
