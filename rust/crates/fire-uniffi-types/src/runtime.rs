use std::{
    future::Future,
    panic::{self, AssertUnwindSafe},
    sync::{Arc, OnceLock},
};

use fire_core::{FireCore, FireCoreError};
use futures_util::FutureExt;
use tokio::runtime::{Builder, Runtime};

use crate::error::FireUniFfiError;
use crate::panic::{CapturedPanic, PanicState};

pub fn ffi_runtime() -> &'static Runtime {
    static RUNTIME: OnceLock<Runtime> = OnceLock::new();
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("failed to create ffi runtime")
    })
}

pub async fn run_on_ffi_runtime<T, Fut>(
    operation: &'static str,
    panic_state: Arc<PanicState>,
    future: Fut,
) -> Result<T, FireUniFfiError>
where
    T: Send + 'static,
    Fut: Future<Output = Result<T, FireCoreError>> + Send + 'static,
{
    panic_state.ensure_healthy(operation)?;
    ffi_runtime()
        .spawn(AssertUnwindSafe(future).catch_unwind())
        .await
        .map_err(|error| FireUniFfiError::Runtime {
            details: error.to_string(),
        })?
        .map_err(|payload| panic_state.capture_panic(operation, payload.as_ref()))?
        .map_err(Into::into)
}

pub fn constructor_guard<T, F>(operation: &'static str, f: F) -> Result<T, FireUniFfiError>
where
    F: FnOnce() -> Result<T, FireCoreError>,
{
    match panic::catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(payload) => {
            let report = CapturedPanic::from_payload(operation, payload.as_ref());
            report.log();
            Err(FireUniFfiError::Internal {
                details: report.user_message(),
            })
        }
    }
}

pub fn run_fallible<T, F>(
    panic_state: &PanicState,
    inner: &FireCore,
    operation: &'static str,
    f: F,
) -> Result<T, FireUniFfiError>
where
    F: FnOnce(&FireCore) -> Result<T, FireCoreError>,
{
    panic_state.ensure_healthy(operation)?;
    match panic::catch_unwind(AssertUnwindSafe(|| f(inner))) {
        Ok(Ok(value)) => Ok(value),
        Ok(Err(error)) => Err(error.into()),
        Err(payload) => Err(panic_state.capture_panic(operation, payload.as_ref())),
    }
}

pub fn run_infallible<T, F>(
    panic_state: &PanicState,
    inner: &FireCore,
    operation: &'static str,
    f: F,
) -> Result<T, FireUniFfiError>
where
    F: FnOnce(&FireCore) -> T,
{
    panic_state.ensure_healthy(operation)?;
    match panic::catch_unwind(AssertUnwindSafe(|| f(inner))) {
        Ok(value) => Ok(value),
        Err(payload) => Err(panic_state.capture_panic(operation, payload.as_ref())),
    }
}
