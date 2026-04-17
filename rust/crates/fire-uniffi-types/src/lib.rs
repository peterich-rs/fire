uniffi::setup_scaffolding!("fire_uniffi_types");

pub mod error;
pub mod panic;
pub mod records;
pub mod runtime;
pub mod shared;

pub use error::FireUniFfiError;
pub use panic::{CapturedPanic, PanicState};
pub use records::{
    DraftDataState, DraftListResponseState, DraftState, RequiredTagGroupState, TopicListKindState,
    TopicListState, TopicParticipantState, TopicPosterState, TopicRowState, TopicSummaryState,
    TopicTagState, TopicUserState,
};
pub use runtime::{
    constructor_guard, ffi_runtime, run_fallible, run_infallible, run_on_ffi_runtime,
};
pub use shared::SharedFireCore;
