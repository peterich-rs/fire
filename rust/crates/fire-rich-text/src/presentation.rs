use fire_models::{PresentedDocument, RenderDocument, RenderPresentation};

use crate::display_segments;

/// Build the host display plan from an already-rendered document.
///
/// Pure CPU work: callers keep this on the mapping side of an async fetch,
/// not inside the network task.
pub fn present_document(document: &RenderDocument) -> RenderPresentation {
    RenderPresentation::finish(
        document.plain_text.clone(),
        // Stage 1 still clones attachments off the IR. Stage 2 can share.
        document.image_attachments.clone(),
        display_segments(document),
    )
}

pub fn present_owned_document(document: RenderDocument) -> PresentedDocument {
    let presentation = present_document(&document);
    PresentedDocument::new(document, presentation)
}

#[cfg(test)]
mod tests {
    use fire_models::{
        RenderBlock, RenderBlockKind, RenderDocument, RenderImageAttachment, RenderRichNode,
        RenderUiSegment,
    };

    use super::{present_document, present_owned_document};

    fn paragraph_document(text: &str) -> RenderDocument {
        RenderDocument {
            blocks: vec![
                RenderBlock {
                    id: 0,
                    parent_id: None,
                    depth: 0,
                    kind: RenderBlockKind::Document,
                },
                RenderBlock {
                    id: 1,
                    parent_id: Some(0),
                    depth: 1,
                    kind: RenderBlockKind::Paragraph,
                },
                RenderBlock {
                    id: 2,
                    parent_id: Some(1),
                    depth: 2,
                    kind: RenderBlockKind::Text {
                        content: text.to_string(),
                    },
                },
            ],
            plain_text: text.to_string(),
            image_attachments: Vec::new(),
        }
    }

    #[test]
    fn present_document_copies_plain_text_and_builds_rich_segments() {
        let presented = present_owned_document(paragraph_document("Hello Fire"));

        assert_eq!(presented.presentation().plain_text, "Hello Fire");
        assert!(presented.presentation().image_attachments.is_empty());
        assert!(presented
            .presentation()
            .segments
            .iter()
            .any(|segment| matches!(segment, RenderUiSegment::Rich { .. })));
        assert_eq!(presented.document().plain_text, "Hello Fire");
        assert!(!presented.presentation().is_empty());
        assert_ne!(presented.presentation().checksum, 0);
    }

    #[test]
    fn present_document_keeps_trailing_image_attachments() {
        let mut document = paragraph_document("caption");
        document.image_attachments.push(RenderImageAttachment {
            url: "https://linux.do/uploads/fire.png".to_string(),
            alt_text: Some("fire".to_string()),
            width: Some(12),
            height: Some(12),
        });

        let presentation = present_document(&document);
        assert!(matches!(
            presentation.segments.last(),
            Some(RenderUiSegment::Image(image))
                if image.url == "https://linux.do/uploads/fire.png"
        ));
    }

    #[test]
    fn checksum_changes_when_rich_structure_changes() {
        let plain = paragraph_document("Hello Fire");
        let mut bold = paragraph_document("Hello Fire");
        bold.blocks[2].kind = RenderBlockKind::Bold;
        bold.blocks.push(RenderBlock {
            id: 3,
            parent_id: Some(2),
            depth: 3,
            kind: RenderBlockKind::Text {
                content: "Hello Fire".to_string(),
            },
        });

        let left = present_document(&plain);
        let right = present_document(&bold);
        assert_eq!(left.plain_text, right.plain_text);
        assert_ne!(left.checksum, right.checksum);
        assert!(left.segments.iter().any(|segment| {
            matches!(
                segment,
                RenderUiSegment::Rich { nodes }
                    if nodes.iter().any(|node| matches!(node, RenderRichNode::Paragraph { .. }))
            )
        }));
    }
}
