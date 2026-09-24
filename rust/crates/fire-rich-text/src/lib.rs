mod emoji;
mod images;
mod map;
mod onebox;
mod plain_text;
mod presentation;
mod ui_plan;

use fire_models::{CookedHtmlDocument, RenderBlockKind, RenderDocument, RenderImageAttachment};

pub use fire_models::PresentedDocument;
pub use plain_text::plain_text_from_render_document;
pub use presentation::{present_document, present_owned_document};
pub use ui_plan::display_segments;

pub(crate) use map::resolved_url_string;

pub fn render_document(document: &CookedHtmlDocument, base_url: &str) -> RenderDocument {
    let tree = map::CookedTree::new(&document.nodes);
    let root = tree
        .root
        .unwrap_or_else(|| panic!("CookedHtmlDocument is missing a document root node"));

    let mut root_block = map::TreeRenderBlock {
        kind: RenderBlockKind::Document,
        children: Vec::new(),
    };
    for child in tree.children_of(root) {
        root_block
            .children
            .extend(map::map_node(child, &tree, base_url));
    }

    let plain_text = plain_text::render_plain_text(&root_block.children);

    RenderDocument {
        blocks: map::flatten_tree(&root_block),
        plain_text,
        image_attachments: images::collect_image_attachments(document, &tree, base_url),
    }
}

pub fn collect_images(document: &RenderDocument) -> Vec<RenderImageAttachment> {
    document.image_attachments.clone()
}

#[cfg(test)]
mod tests;
