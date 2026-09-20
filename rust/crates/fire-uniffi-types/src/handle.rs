use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex, Weak};

use fire_models::PresentedDocument;

use crate::records::{RenderImageAttachmentState, RenderPresentationState, RenderUiSegmentState};

/// Stable UniFFI object wrapping one `Arc<PresentedDocument>`.
///
/// Interned by document pointer so remapping the same presented body keeps
/// the same handle identity. Hosts cache on `checksum()`, not object identity
/// alone, because a new document after edit is a new handle.
#[derive(uniffi::Object, Debug)]
pub struct RenderDocumentHandle {
    inner: Arc<PresentedDocument>,
}

#[uniffi::export]
impl RenderDocumentHandle {
    pub fn checksum(&self) -> u64 {
        self.inner.presentation().checksum
    }

    pub fn is_empty(&self) -> bool {
        self.inner.presentation().is_empty()
    }

    pub fn plain_text(&self) -> String {
        self.inner.presentation().plain_text.clone()
    }

    pub fn image_attachments(&self) -> Vec<RenderImageAttachmentState> {
        self.inner
            .presentation()
            .image_attachments
            .iter()
            .cloned()
            .map(Into::into)
            .collect()
    }

    pub fn segment_count(&self) -> u32 {
        u32::try_from(self.inner.presentation().segments.len()).unwrap_or(u32::MAX)
    }

    pub fn segment(&self, index: u32) -> Option<RenderUiSegmentState> {
        self.inner
            .presentation()
            .segments
            .get(index as usize)
            .cloned()
            .map(Into::into)
    }

    /// Test / debug only. Production cells must call `segment(i)`.
    pub fn debug_ui_plan(&self) -> RenderPresentationState {
        self.inner.presentation().clone().into()
    }
}

impl RenderDocumentHandle {
    pub fn presented(&self) -> &PresentedDocument {
        self.inner.as_ref()
    }
}

static HANDLES: LazyLock<Mutex<HashMap<usize, Weak<RenderDocumentHandle>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub fn intern_presented_handle(presented: Arc<PresentedDocument>) -> Arc<RenderDocumentHandle> {
    let key = Arc::as_ptr(&presented) as usize;
    let mut map = HANDLES.lock().expect("render handle intern poisoned");
    if let Some(existing) = map.get(&key).and_then(Weak::upgrade) {
        return existing;
    }
    map.retain(|_, weak| weak.strong_count() > 0);
    let handle = Arc::new(RenderDocumentHandle { inner: presented });
    map.insert(key, Arc::downgrade(&handle));
    handle
}
