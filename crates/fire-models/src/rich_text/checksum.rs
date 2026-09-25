const FNV_OFFSET: u64 = 0xcbf29ce484222325;
const FNV_PRIME: u64 = 0x0000_0100_0000_01b3;

fn fnv1a_update(hash: &mut u64, bytes: &[u8]) {
    for byte in bytes {
        *hash ^= u64::from(*byte);
        *hash = hash.wrapping_mul(FNV_PRIME);
    }
}

fn hash_u64(hash: &mut u64, value: u64) {
    fnv1a_update(hash, &value.to_le_bytes());
}

fn hash_u32(hash: &mut u64, value: u32) {
    hash_u64(hash, u64::from(value));
}

fn hash_bool(hash: &mut u64, value: bool) {
    hash_u64(hash, u64::from(value));
}

fn hash_str(hash: &mut u64, value: &str) {
    hash_u64(hash, value.len() as u64);
    fnv1a_update(hash, value.as_bytes());
}

fn hash_opt_str(hash: &mut u64, value: Option<&str>) {
    match value {
        Some(text) => {
            hash_u64(hash, 1);
            hash_str(hash, text);
        }
        None => hash_u64(hash, 0),
    }
}

fn hash_opt_u32(hash: &mut u64, value: Option<u32>) {
    match value {
        Some(number) => {
            hash_u64(hash, 1);
            hash_u32(hash, number);
        }
        None => hash_u64(hash, 0),
    }
}

fn hash_opt_u64(hash: &mut u64, value: Option<u64>) {
    match value {
        Some(number) => {
            hash_u64(hash, 1);
            hash_u64(hash, number);
        }
        None => hash_u64(hash, 0),
    }
}

pub fn presentation_checksum(
    plain_text: &str,
    image_attachments: &[RenderImageAttachment],
    segments: &[RenderUiSegment],
) -> u64 {
    let mut hash = FNV_OFFSET;
    hash_str(&mut hash, plain_text);
    hash_u64(&mut hash, image_attachments.len() as u64);
    for attachment in image_attachments {
        hash_str(&mut hash, &attachment.url);
        hash_opt_str(&mut hash, attachment.alt_text.as_deref());
        hash_opt_u32(&mut hash, attachment.width);
        hash_opt_u32(&mut hash, attachment.height);
    }
    hash_u64(&mut hash, segments.len() as u64);
    for segment in segments {
        hash_ui_segment(&mut hash, segment);
    }
    hash
}

fn hash_ui_segment(hash: &mut u64, segment: &RenderUiSegment) {
    match segment {
        RenderUiSegment::Image(image) => {
            hash_u64(hash, 1);
            hash_str(hash, &image.url);
            hash_opt_str(hash, image.alt_text.as_deref());
            hash_opt_u32(hash, image.width);
            hash_opt_u32(hash, image.height);
        }
        RenderUiSegment::Onebox(card) => {
            hash_u64(hash, 2);
            hash_onebox_card(hash, card);
        }
        RenderUiSegment::Rich { nodes } => {
            hash_u64(hash, 3);
            hash_rich_children(hash, nodes);
        }
    }
}

fn hash_onebox_card(hash: &mut u64, card: &RenderOneboxCard) {
    hash_opt_str(hash, card.url.as_deref());
    hash_opt_str(hash, card.title.as_deref());
    hash_opt_str(hash, card.description.as_deref());
    hash_opt_str(hash, card.source_name.as_deref());
    hash_opt_str(hash, card.icon_url.as_deref());
    hash_opt_str(hash, card.thumbnail_url.as_deref());
    hash_opt_u32(hash, card.thumbnail_width);
    hash_opt_u32(hash, card.thumbnail_height);
}

fn hash_rich_children(hash: &mut u64, nodes: &[RenderRichNode]) {
    hash_u64(hash, nodes.len() as u64);
    for node in nodes {
        hash_rich_node(hash, node);
    }
}

fn hash_rich_node(hash: &mut u64, node: &RenderRichNode) {
    match node {
        RenderRichNode::Text { content } => {
            hash_u64(hash, 1);
            hash_str(hash, content);
        }
        RenderRichNode::Bold { children } => {
            hash_u64(hash, 2);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Italic { children } => {
            hash_u64(hash, 3);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Strikethrough { children } => {
            hash_u64(hash, 4);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Code { code } => {
            hash_u64(hash, 5);
            hash_str(hash, code);
        }
        RenderRichNode::CodeBlock { language, code } => {
            hash_u64(hash, 6);
            hash_opt_str(hash, language.as_deref());
            hash_str(hash, code);
        }
        RenderRichNode::Link { url, children } => {
            hash_u64(hash, 7);
            hash_str(hash, url);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Mention { username } => {
            hash_u64(hash, 8);
            hash_str(hash, username);
        }
        RenderRichNode::MentionGroup { name, url } => {
            hash_u64(hash, 9);
            hash_str(hash, name);
            hash_str(hash, url);
        }
        RenderRichNode::Hashtag { text, url, kind } => {
            hash_u64(hash, 10);
            hash_str(hash, text);
            hash_str(hash, url);
            hash_opt_str(hash, kind.as_deref());
        }
        RenderRichNode::Emoji {
            url,
            fallback_text,
            only_emoji,
        } => {
            hash_u64(hash, 11);
            hash_str(hash, url);
            hash_str(hash, fallback_text);
            hash_bool(hash, *only_emoji);
        }
        RenderRichNode::Heading { level, children } => {
            hash_u64(hash, 12);
            hash_u64(hash, u64::from(*level));
            hash_rich_children(hash, children);
        }
        RenderRichNode::Blockquote { children } => {
            hash_u64(hash, 13);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Quote {
            author,
            post_number,
            topic_id,
            children,
        } => {
            hash_u64(hash, 14);
            hash_opt_str(hash, author.as_deref());
            hash_opt_u32(hash, *post_number);
            hash_opt_u64(hash, *topic_id);
            hash_rich_children(hash, children);
        }
        RenderRichNode::List { ordered, items } => {
            hash_u64(hash, 15);
            hash_bool(hash, *ordered);
            hash_u64(hash, items.len() as u64);
            for item in items {
                hash_rich_children(hash, item);
            }
        }
        RenderRichNode::ListItem { children } => {
            hash_u64(hash, 16);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Spoiler { children } => {
            hash_u64(hash, 17);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Details { summary, children } => {
            hash_u64(hash, 18);
            hash_rich_children(hash, summary);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Table { text } => {
            hash_u64(hash, 19);
            hash_str(hash, text);
        }
        RenderRichNode::Video { url, title } => {
            hash_u64(hash, 20);
            hash_str(hash, url);
            hash_opt_str(hash, title.as_deref());
        }
        RenderRichNode::Divider => hash_u64(hash, 21),
        RenderRichNode::LineBreak => hash_u64(hash, 22),
        RenderRichNode::Paragraph { children } => {
            hash_u64(hash, 23);
            hash_rich_children(hash, children);
        }
        RenderRichNode::Image {
            url,
            alt,
            width,
            height,
        } => {
            hash_u64(hash, 24);
            hash_str(hash, url);
            hash_opt_str(hash, alt.as_deref());
            hash_opt_u32(hash, *width);
            hash_opt_u32(hash, *height);
        }
        RenderRichNode::Onebox(card) => {
            hash_u64(hash, 25);
            hash_onebox_card(hash, card);
        }
    }
}
