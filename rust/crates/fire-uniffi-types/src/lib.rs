uniffi::setup_scaffolding!("fire_uniffi_types");

pub mod error;
pub mod panic;
pub mod runtime;
pub mod shared;

pub use error::FireUniFfiError;
pub use panic::{CapturedPanic, PanicState};
pub use runtime::{
    constructor_guard, ffi_runtime, run_fallible, run_infallible, run_on_ffi_runtime,
};
pub use shared::SharedFireCore;
