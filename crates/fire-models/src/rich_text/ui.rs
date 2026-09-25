/// Host layout segment. Image and onebox are independent cells; everything
/// else stays in a rich node run.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderUiSegment {
    Rich { nodes: Vec<RenderRichNode> },
    Image(RenderImageAttachment),
    Onebox(RenderOneboxCard),
}

/// UI-ready body produced from a `RenderDocument`.
///
/// `checksum` is written once in `finish` and is the only content identity
/// hosts may cache on. `image_attachments` is still cloned from the IR in
/// Stage 1; Stage 2 can share the same allocation.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderPresentation {
    pub checksum: u64,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachment>,
    pub segments: Vec<RenderUiSegment>,
}

impl RenderPresentation {
    pub fn finish(
        plain_text: String,
        image_attachments: Vec<RenderImageAttachment>,
        segments: Vec<RenderUiSegment>,
    ) -> Self {
        let checksum = presentation_checksum(&plain_text, &image_attachments, &segments);
        Self {
            checksum,
            plain_text,
            image_attachments,
            segments,
        }
    }

    pub fn is_empty(&self) -> bool {
        self.segments.is_empty() && self.plain_text.trim().is_empty()
    }
}

