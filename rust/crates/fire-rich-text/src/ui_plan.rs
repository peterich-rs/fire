use std::collections::BTreeMap;

use fire_models::{
    RenderBlock, RenderBlockKind, RenderDocument, RenderImageAttachment, RenderOneboxCard,
    RenderRichNode, RenderUiSegment,
};

/// Split a render document into host layout segments.
///
/// Image and onebox become independent cells. Remaining subtrees are converted
/// to `RenderRichNode` trees — no mini `RenderDocument`, no id remap.
pub fn display_segments(document: &RenderDocument) -> Vec<RenderUiSegment> {
    if document.blocks.is_empty() {
        return Vec::new();
    }

    let tree = DisplayBlockTree::new(&document.blocks);
    let Some(root) = tree.root else {
        return Vec::new();
    };

    let mut attachment_index = 0_usize;
    let mut segments = Vec::new();
    for child in tree.children_of(root) {
        append_display_segments(child, &tree, document, &mut attachment_index, &mut segments);
    }

    while attachment_index < document.image_attachments.len() {
        push_image_segment(
            document.image_attachments[attachment_index].clone(),
            &mut segments,
        );
        attachment_index += 1;
    }

    segments
}

struct DisplayBlockTree<'a> {
    root: Option<&'a RenderBlock>,
    children_by_parent: BTreeMap<u32, Vec<&'a RenderBlock>>,
}

impl<'a> DisplayBlockTree<'a> {
    fn new(blocks: &'a [RenderBlock]) -> Self {
        let mut children_by_parent: BTreeMap<u32, Vec<&RenderBlock>> = BTreeMap::new();
        let mut root = None;
        for block in blocks {
            match block.parent_id {
                Some(parent_id) => {
                    children_by_parent.entry(parent_id).or_default().push(block);
                }
                None if root.is_none() => root = Some(block),
                None => {}
            }
        }
        Self {
            root,
            children_by_parent,
        }
    }

    fn children_of(&self, block: &RenderBlock) -> &[&RenderBlock] {
        self.children_by_parent
            .get(&block.id)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }
}

fn append_display_segments(
    block: &RenderBlock,
    tree: &DisplayBlockTree<'_>,
    document: &RenderDocument,
    attachment_index: &mut usize,
    segments: &mut Vec<RenderUiSegment>,
) {
    match &block.kind {
        RenderBlockKind::Image {
            url,
            alt,
            width,
            height,
        } => {
            let image = take_image_attachment(
                document,
                attachment_index,
                url,
                alt.as_deref(),
                *width,
                *height,
            );
            push_image_segment(image, segments);
        }
        RenderBlockKind::Onebox {
            url,
            title,
            description,
            source_name,
            icon_url,
            thumbnail_url,
            thumbnail_width,
            thumbnail_height,
        } => {
            push_onebox_segment(
                RenderOneboxCard {
                    url: url.clone(),
                    title: title.clone(),
                    description: description.clone(),
                    source_name: source_name.clone(),
                    icon_url: icon_url.clone(),
                    thumbnail_url: thumbnail_url.clone(),
                    thumbnail_width: *thumbnail_width,
                    thumbnail_height: *thumbnail_height,
                },
                segments,
            );
        }
        RenderBlockKind::Details => {
            append_details_segments(block, tree, document, attachment_index, segments)
        }
        RenderBlockKind::Paragraph
        | RenderBlockKind::Heading { .. }
        | RenderBlockKind::Blockquote
        | RenderBlockKind::Quote { .. }
        | RenderBlockKind::List { .. }
        | RenderBlockKind::ListItem
        | RenderBlockKind::Spoiler => {
            let child_segments = collect_child_segments(block, tree, document, attachment_index);
            for child in child_segments {
                match child {
                    RenderUiSegment::Rich { nodes } => {
                        if let Some(wrapped) = wrap_rich_nodes(&block.kind, nodes) {
                            push_rich_segment(vec![wrapped], segments);
                        }
                    }
                    RenderUiSegment::Image(image) => push_image_segment(image, segments),
                    RenderUiSegment::Onebox(card) => push_onebox_segment(card, segments),
                }
            }
        }
        _ => {
            let nodes = nodes_from_block(block, tree);
            push_rich_segment(nodes, segments);
        }
    }
}

fn append_details_segments(
    block: &RenderBlock,
    tree: &DisplayBlockTree<'_>,
    document: &RenderDocument,
    attachment_index: &mut usize,
    segments: &mut Vec<RenderUiSegment>,
) {
    let children = tree.children_of(block);
    let summary = children
        .iter()
        .find(|child| matches!(child.kind, RenderBlockKind::DetailsSummary))
        .map(|child| {
            tree.children_of(child)
                .iter()
                .flat_map(|node| nodes_from_block(node, tree))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let mut emitted_details = false;
    for child in children
        .iter()
        .copied()
        .filter(|child| !matches!(child.kind, RenderBlockKind::DetailsSummary))
    {
        let mut child_segments = Vec::new();
        append_display_segments(child, tree, document, attachment_index, &mut child_segments);
        for piece in child_segments {
            match piece {
                RenderUiSegment::Rich { nodes } => {
                    if nodes.is_empty() {
                        continue;
                    }
                    push_rich_segment(
                        vec![RenderRichNode::Details {
                            summary: summary.clone(),
                            children: nodes,
                        }],
                        segments,
                    );
                    emitted_details = true;
                }
                RenderUiSegment::Image(image) => {
                    if !emitted_details && !summary.is_empty() {
                        push_rich_segment(
                            vec![RenderRichNode::Details {
                                summary: summary.clone(),
                                children: Vec::new(),
                            }],
                            segments,
                        );
                        emitted_details = true;
                    }
                    push_image_segment(image, segments);
                }
                RenderUiSegment::Onebox(card) => {
                    if !emitted_details && !summary.is_empty() {
                        push_rich_segment(
                            vec![RenderRichNode::Details {
                                summary: summary.clone(),
                                children: Vec::new(),
                            }],
                            segments,
                        );
                        emitted_details = true;
                    }
                    push_onebox_segment(card, segments);
                }
            }
        }
    }

    if !emitted_details && !summary.is_empty() {
        push_rich_segment(
            vec![RenderRichNode::Details {
                summary,
                children: Vec::new(),
            }],
            segments,
        );
    }
}

fn collect_child_segments(
    block: &RenderBlock,
    tree: &DisplayBlockTree<'_>,
    document: &RenderDocument,
    attachment_index: &mut usize,
) -> Vec<RenderUiSegment> {
    let mut child_segments = Vec::new();
    for child in tree.children_of(block) {
        append_display_segments(child, tree, document, attachment_index, &mut child_segments);
    }
    child_segments
}

fn wrap_rich_nodes(kind: &RenderBlockKind, nodes: Vec<RenderRichNode>) -> Option<RenderRichNode> {
    if nodes.is_empty() {
        return None;
    }
    Some(match kind {
        RenderBlockKind::Paragraph => RenderRichNode::Paragraph { children: nodes },
        RenderBlockKind::Heading { level } => RenderRichNode::Heading {
            level: *level,
            children: nodes,
        },
        RenderBlockKind::Blockquote => RenderRichNode::Blockquote { children: nodes },
        RenderBlockKind::Quote {
            author,
            post_number,
            topic_id,
        } => RenderRichNode::Quote {
            author: author.clone(),
            post_number: *post_number,
            topic_id: *topic_id,
            children: nodes,
        },
        RenderBlockKind::List { ordered } => {
            let items = list_items_from_nodes(nodes);
            if items.is_empty() {
                return None;
            }
            RenderRichNode::List {
                ordered: *ordered,
                items,
            }
        }
        RenderBlockKind::ListItem => RenderRichNode::ListItem { children: nodes },
        RenderBlockKind::Spoiler => RenderRichNode::Spoiler { children: nodes },
        _ => return None,
    })
}

fn list_items_from_nodes(nodes: Vec<RenderRichNode>) -> Vec<Vec<RenderRichNode>> {
    nodes
        .into_iter()
        .map(|node| match node {
            RenderRichNode::ListItem { children } => children,
            other => vec![other],
        })
        .collect()
}

fn nodes_from_block(block: &RenderBlock, tree: &DisplayBlockTree<'_>) -> Vec<RenderRichNode> {
    let child_nodes = tree
        .children_of(block)
        .iter()
        .flat_map(|child| nodes_from_block(child, tree))
        .collect::<Vec<_>>();

    match &block.kind {
        RenderBlockKind::Document | RenderBlockKind::Unknown | RenderBlockKind::DetailsSummary => {
            child_nodes
        }
        RenderBlockKind::Text { content } => vec![RenderRichNode::Text {
            content: content.clone(),
        }],
        RenderBlockKind::Paragraph => vec![RenderRichNode::Paragraph {
            children: child_nodes,
        }],
        RenderBlockKind::Heading { level } => vec![RenderRichNode::Heading {
            level: *level,
            children: child_nodes,
        }],
        RenderBlockKind::LineBreak => vec![RenderRichNode::LineBreak],
        RenderBlockKind::Bold => vec![RenderRichNode::Bold {
            children: child_nodes,
        }],
        RenderBlockKind::Italic => vec![RenderRichNode::Italic {
            children: child_nodes,
        }],
        RenderBlockKind::Strikethrough => vec![RenderRichNode::Strikethrough {
            children: child_nodes,
        }],
        RenderBlockKind::InlineCode { code } => vec![RenderRichNode::Code { code: code.clone() }],
        RenderBlockKind::CodeBlock { language, code } => vec![RenderRichNode::CodeBlock {
            language: language.clone(),
            code: code.clone(),
        }],
        RenderBlockKind::Link { url } => vec![RenderRichNode::Link {
            url: url.clone(),
            children: child_nodes,
        }],
        RenderBlockKind::Mention { username } => vec![RenderRichNode::Mention {
            username: username.clone(),
        }],
        RenderBlockKind::MentionGroup { name, url } => vec![RenderRichNode::MentionGroup {
            name: name.clone(),
            url: url.clone(),
        }],
        RenderBlockKind::Hashtag { text, url, kind } => vec![RenderRichNode::Hashtag {
            text: text.clone(),
            url: url.clone(),
            kind: kind.clone(),
        }],
        RenderBlockKind::Emoji {
            url,
            fallback_text,
            only_emoji,
        } => vec![RenderRichNode::Emoji {
            url: url.clone(),
            fallback_text: fallback_text.clone(),
            only_emoji: *only_emoji,
        }],
        RenderBlockKind::Image {
            url,
            alt,
            width,
            height,
        } => vec![RenderRichNode::Image {
            url: url.clone(),
            alt: alt.clone(),
            width: *width,
            height: *height,
        }],
        RenderBlockKind::Blockquote => vec![RenderRichNode::Blockquote {
            children: child_nodes,
        }],
        RenderBlockKind::Quote {
            author,
            post_number,
            topic_id,
        } => vec![RenderRichNode::Quote {
            author: author.clone(),
            post_number: *post_number,
            topic_id: *topic_id,
            children: child_nodes,
        }],
        RenderBlockKind::List { ordered } => {
            let items = tree
                .children_of(block)
                .iter()
                .filter_map(|child| {
                    if !matches!(child.kind, RenderBlockKind::ListItem) {
                        return None;
                    }
                    let mapped = nodes_from_block(child, tree);
                    match mapped.into_iter().next() {
                        Some(RenderRichNode::ListItem { children }) => Some(children),
                        _ => None,
                    }
                })
                .collect::<Vec<_>>();
            if items.is_empty() {
                child_nodes
            } else {
                vec![RenderRichNode::List {
                    ordered: *ordered,
                    items,
                }]
            }
        }
        RenderBlockKind::ListItem => vec![RenderRichNode::ListItem {
            children: child_nodes,
        }],
        RenderBlockKind::Spoiler => vec![RenderRichNode::Spoiler {
            children: child_nodes,
        }],
        RenderBlockKind::Details => {
            let summary = tree
                .children_of(block)
                .iter()
                .find(|child| matches!(child.kind, RenderBlockKind::DetailsSummary))
                .map(|child| {
                    tree.children_of(child)
                        .iter()
                        .flat_map(|node| nodes_from_block(node, tree))
                        .collect()
                })
                .unwrap_or_default();
            let body = tree
                .children_of(block)
                .iter()
                .filter(|child| !matches!(child.kind, RenderBlockKind::DetailsSummary))
                .flat_map(|child| nodes_from_block(child, tree))
                .collect();
            vec![RenderRichNode::Details {
                summary,
                children: body,
            }]
        }
        RenderBlockKind::Table { text } => vec![RenderRichNode::Table { text: text.clone() }],
        RenderBlockKind::Onebox {
            url,
            title,
            description,
            source_name,
            icon_url,
            thumbnail_url,
            thumbnail_width,
            thumbnail_height,
        } => vec![RenderRichNode::Onebox(RenderOneboxCard {
            url: url.clone(),
            title: title.clone(),
            description: description.clone(),
            source_name: source_name.clone(),
            icon_url: icon_url.clone(),
            thumbnail_url: thumbnail_url.clone(),
            thumbnail_width: *thumbnail_width,
            thumbnail_height: *thumbnail_height,
        })],
        RenderBlockKind::Video { url, title } => vec![RenderRichNode::Video {
            url: url.clone(),
            title: title.clone(),
        }],
        RenderBlockKind::Divider => vec![RenderRichNode::Divider],
    }
}

fn take_image_attachment(
    document: &RenderDocument,
    attachment_index: &mut usize,
    url: &str,
    alt: Option<&str>,
    width: Option<u32>,
    height: Option<u32>,
) -> RenderImageAttachment {
    if *attachment_index < document.image_attachments.len() {
        let image = document.image_attachments[*attachment_index].clone();
        *attachment_index += 1;
        return image;
    }
    *attachment_index += 1;
    RenderImageAttachment {
        url: url.to_string(),
        alt_text: alt.map(str::to_string),
        width,
        height,
    }
}

fn push_image_segment(image: RenderImageAttachment, segments: &mut Vec<RenderUiSegment>) {
    segments.push(RenderUiSegment::Image(image));
}

fn push_onebox_segment(card: RenderOneboxCard, segments: &mut Vec<RenderUiSegment>) {
    segments.push(RenderUiSegment::Onebox(card));
}

fn push_rich_segment(nodes: Vec<RenderRichNode>, segments: &mut Vec<RenderUiSegment>) {
    if nodes.is_empty() || rich_nodes_are_blank(&nodes) {
        return;
    }
    if let Some(RenderUiSegment::Rich { nodes: existing }) = segments.last_mut() {
        existing.extend(nodes);
        return;
    }
    segments.push(RenderUiSegment::Rich { nodes });
}

fn rich_nodes_are_blank(nodes: &[RenderRichNode]) -> bool {
    nodes.iter().all(node_is_blank)
}

fn node_is_blank(node: &RenderRichNode) -> bool {
    match node {
        RenderRichNode::Text { content } => content.trim().is_empty(),
        RenderRichNode::Code { code } => code.trim().is_empty(),
        RenderRichNode::CodeBlock { code, .. } => code.trim().is_empty(),
        RenderRichNode::Table { text } => text.trim().is_empty(),
        RenderRichNode::LineBreak => true,
        RenderRichNode::Divider => false,
        RenderRichNode::Bold { children }
        | RenderRichNode::Italic { children }
        | RenderRichNode::Strikethrough { children }
        | RenderRichNode::Link { children, .. }
        | RenderRichNode::Heading { children, .. }
        | RenderRichNode::Blockquote { children }
        | RenderRichNode::Quote { children, .. }
        | RenderRichNode::ListItem { children }
        | RenderRichNode::Spoiler { children }
        | RenderRichNode::Paragraph { children } => rich_nodes_are_blank(children),
        RenderRichNode::Details { summary, children } => {
            rich_nodes_are_blank(summary) && rich_nodes_are_blank(children)
        }
        RenderRichNode::List { items, .. } => items.iter().all(|item| rich_nodes_are_blank(item)),
        RenderRichNode::Mention { .. }
        | RenderRichNode::MentionGroup { .. }
        | RenderRichNode::Hashtag { .. }
        | RenderRichNode::Emoji { .. }
        | RenderRichNode::Image { .. }
        | RenderRichNode::Onebox(_)
        | RenderRichNode::Video { .. } => false,
    }
}
