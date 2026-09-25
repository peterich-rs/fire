/// Runtime owner of render IR plus the host UI plan.
///
/// Lives on domain posts as `Arc<PresentedDocument>`. Serde caches must skip
/// it and re-present from `cooked` on cold start.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PresentedDocument {
    document: RenderDocument,
    presentation: RenderPresentation,
}

impl PresentedDocument {
    pub fn new(document: RenderDocument, presentation: RenderPresentation) -> Self {
        Self {
            document,
            presentation,
        }
    }

    pub fn document(&self) -> &RenderDocument {
        &self.document
    }

    pub fn presentation(&self) -> &RenderPresentation {
        &self.presentation
    }

    pub fn into_presentation(self) -> RenderPresentation {
        self.presentation
    }
}

/// Cache slot for a presented body. Invisible to `PartialEq` / serde so record
/// identity stays `cooked` + metadata.
#[derive(Debug, Clone, Default)]
pub struct AttachedPresentation {
    inner: Option<std::sync::Arc<PresentedDocument>>,
}

impl AttachedPresentation {
    pub fn none() -> Self {
        Self { inner: None }
    }

    pub fn some(document: std::sync::Arc<PresentedDocument>) -> Self {
        Self {
            inner: Some(document),
        }
    }

    pub fn get(&self) -> Option<&PresentedDocument> {
        self.inner.as_deref()
    }

    pub fn arc(&self) -> Option<std::sync::Arc<PresentedDocument>> {
        self.inner.clone()
    }
}

impl PartialEq for AttachedPresentation {
    fn eq(&self, _: &Self) -> bool {
        true
    }
}

impl Eq for AttachedPresentation {}

impl Serialize for AttachedPresentation {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_none()
    }
}

impl<'de> Deserialize<'de> for AttachedPresentation {
    fn deserialize<D: serde::Deserializer<'de>>(_: D) -> Result<Self, D::Error> {
        Ok(Self::none())
    }
}

