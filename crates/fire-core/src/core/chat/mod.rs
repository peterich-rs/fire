pub(crate) mod channel_session;
mod channels;
pub(crate) mod list;

pub use channel_session::ChatChannelRuntimeSnapshot;
mod messages;
mod pins;
mod reactions;
mod search;
mod threads;

use super::FireCore;
use crate::error::FireCoreError;

pub(super) const DEFAULT_MESSAGE_PAGE_SIZE: u32 = 50;
pub(super) const DEFAULT_BROWSE_LIMIT: u32 = 25;
pub(super) const DEFAULT_SEARCH_LIMIT: u32 = 20;

pub(super) fn ensure_chat_session(core: &FireCore) -> Result<(), FireCoreError> {
    if core.snapshot().cookies.can_authenticate_requests() {
        Ok(())
    } else {
        Err(FireCoreError::MissingLoginSession)
    }
}
