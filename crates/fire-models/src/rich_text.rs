use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum CookedHtmlNodeKind {
    #[default]
    Document,
    Text,
    Paragraph,
    Heading,
    LineBreak,
    Strong,
    Emphasis,
    Strikethrough,
    Link,
    Image,
    Emoji,
    Code,
    CodeBlock,
    Blockquote,
    DiscourseQuote,
    Divider,
    List,
    ListItem,
    Spoiler,
    Details,
    Table,
    TableRow,
    TableCell,
    Onebox,
    Iframe,
    Mention,
    Hashtag,
    Attachment,
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookedHtmlNode {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub kind: CookedHtmlNodeKind,
    pub depth: u32,
    pub text: Option<String>,
    pub url: Option<String>,
    pub title: Option<String>,
    pub alt: Option<String>,
    pub level: Option<u32>,
    pub ordered: Option<bool>,
    pub attributes: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookedHtmlDocument {
    pub nodes: Vec<CookedHtmlNode>,
    pub plain_text: String,
    pub image_urls: Vec<String>,
    pub link_urls: Vec<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderBlock {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub depth: u32,
    pub kind: RenderBlockKind,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderBlockKind {
    Document,
    Text {
        content: String,
    },
    Paragraph,
    Heading {
        level: u8,
    },
    LineBreak,
    Bold,
    Italic,
    Strikethrough,
    InlineCode {
        code: String,
    },
    CodeBlock {
        language: Option<String>,
        code: String,
    },
    Link {
        url: String,
    },
    Mention {
        username: String,
    },
    MentionGroup {
        name: String,
        url: String,
    },
    Hashtag {
        text: String,
        url: String,
        kind: Option<String>,
    },
    Emoji {
        url: String,
        fallback_text: String,
        only_emoji: bool,
    },
    Image {
        url: String,
        alt: Option<String>,
        width: Option<u32>,
        height: Option<u32>,
    },
    Blockquote,
    Quote {
        author: Option<String>,
        post_number: Option<u32>,
        topic_id: Option<u64>,
    },
    List {
        ordered: bool,
    },
    ListItem,
    Spoiler,
    Details,
    DetailsSummary,
    Table {
        text: String,
    },
    Onebox {
        url: Option<String>,
        title: Option<String>,
        description: Option<String>,
        #[serde(default)]
        source_name: Option<String>,
        #[serde(default)]
        icon_url: Option<String>,
        #[serde(default)]
        thumbnail_url: Option<String>,
        #[serde(default)]
        thumbnail_width: Option<u32>,
        #[serde(default)]
        thumbnail_height: Option<u32>,
    },
    Video {
        url: String,
        title: Option<String>,
    },
    Divider,
    #[default]
    Unknown,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderImageAttachment {
    pub url: String,
    pub alt_text: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderDocument {
    pub blocks: Vec<RenderBlock>,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachment>,
}

/// Onebox card extracted as a first-class layout segment.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct RenderOneboxCard {
    pub url: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub source_name: Option<String>,
    pub icon_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

/// Host-drawable rich node. Isomorphic to iOS/Android `FireRichTextNode`.
///
/// This is a tree, not a flattened `RenderBlock` list: quote / list / details
/// keep their nesting so hosts map mechanically and do not rebuild IR.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum RenderRichNode {
    Text {
        content: String,
    },
    Bold {
        children: Vec<RenderRichNode>,
    },
    Italic {
        children: Vec<RenderRichNode>,
    },
    Strikethrough {
        children: Vec<RenderRichNode>,
    },
    Code {
        code: String,
    },
    CodeBlock {
        language: Option<String>,
        code: String,
    },
    Link {
        url: String,
        children: Vec<RenderRichNode>,
    },
    Mention {
        username: String,
    },
    MentionGroup {
        name: String,
        url: String,
    },
    Hashtag {
        text: String,
        url: String,
        kind: Option<String>,
    },
    Emoji {
        url: String,
        fallback_text: String,
        only_emoji: bool,
    },
    Heading {
        level: u8,
        children: Vec<RenderRichNode>,
    },
    Blockquote {
        children: Vec<RenderRichNode>,
    },
    Quote {
        author: Option<String>,
        post_number: Option<u32>,
        topic_id: Option<u64>,
        children: Vec<RenderRichNode>,
    },
    List {
        ordered: bool,
        items: Vec<Vec<RenderRichNode>>,
    },
    ListItem {
        children: Vec<RenderRichNode>,
    },
    Spoiler {
        children: Vec<RenderRichNode>,
    },
    Details {
        summary: Vec<RenderRichNode>,
        children: Vec<RenderRichNode>,
    },
    Table {
        text: String,
    },
    Video {
        url: String,
        title: Option<String>,
    },
    Divider,
    LineBreak,
    Paragraph {
        children: Vec<RenderRichNode>,
    },
    Image {
        url: String,
        alt: Option<String>,
        width: Option<u32>,
        height: Option<u32>,
    },
    Onebox(RenderOneboxCard),
}

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
