use fire_models::{RenderOneboxCard, RenderPresentation, RenderRichNode, RenderUiSegment};

use super::render_block::RenderImageAttachmentState;

#[derive(uniffi::Record, Debug, Clone)]
pub struct RenderOneboxCardState {
    pub url: Option<String>,
    pub title: Option<String>,
    pub description: Option<String>,
    pub source_name: Option<String>,
    pub icon_url: Option<String>,
    pub thumbnail_url: Option<String>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

impl From<RenderOneboxCard> for RenderOneboxCardState {
    fn from(value: RenderOneboxCard) -> Self {
        Self {
            url: value.url,
            title: value.title,
            description: value.description,
            source_name: value.source_name,
            icon_url: value.icon_url,
            thumbnail_url: value.thumbnail_url,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum RenderRichNodeState {
    Text {
        content: String,
    },
    Bold {
        children: Vec<RenderRichNodeState>,
    },
    Italic {
        children: Vec<RenderRichNodeState>,
    },
    Strikethrough {
        children: Vec<RenderRichNodeState>,
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
        children: Vec<RenderRichNodeState>,
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
        children: Vec<RenderRichNodeState>,
    },
    Blockquote {
        children: Vec<RenderRichNodeState>,
    },
    Quote {
        author: Option<String>,
        post_number: Option<u32>,
        topic_id: Option<u64>,
        children: Vec<RenderRichNodeState>,
    },
    ListNode {
        ordered: bool,
        items: Vec<Vec<RenderRichNodeState>>,
    },
    ListItem {
        children: Vec<RenderRichNodeState>,
    },
    Spoiler {
        children: Vec<RenderRichNodeState>,
    },
    Details {
        summary: Vec<RenderRichNodeState>,
        children: Vec<RenderRichNodeState>,
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
        children: Vec<RenderRichNodeState>,
    },
    Image {
        url: String,
        alt: Option<String>,
        width: Option<u32>,
        height: Option<u32>,
    },
    Onebox {
        card: RenderOneboxCardState,
    },
}

impl From<RenderRichNode> for RenderRichNodeState {
    fn from(value: RenderRichNode) -> Self {
        match value {
            RenderRichNode::Text { content } => Self::Text { content },
            RenderRichNode::Bold { children } => Self::Bold {
                children: map_nodes(children),
            },
            RenderRichNode::Italic { children } => Self::Italic {
                children: map_nodes(children),
            },
            RenderRichNode::Strikethrough { children } => Self::Strikethrough {
                children: map_nodes(children),
            },
            RenderRichNode::Code { code } => Self::Code { code },
            RenderRichNode::CodeBlock { language, code } => Self::CodeBlock { language, code },
            RenderRichNode::Link { url, children } => Self::Link {
                url,
                children: map_nodes(children),
            },
            RenderRichNode::Mention { username } => Self::Mention { username },
            RenderRichNode::MentionGroup { name, url } => Self::MentionGroup { name, url },
            RenderRichNode::Hashtag { text, url, kind } => Self::Hashtag { text, url, kind },
            RenderRichNode::Emoji {
                url,
                fallback_text,
                only_emoji,
            } => Self::Emoji {
                url,
                fallback_text,
                only_emoji,
            },
            RenderRichNode::Heading { level, children } => Self::Heading {
                level,
                children: map_nodes(children),
            },
            RenderRichNode::Blockquote { children } => Self::Blockquote {
                children: map_nodes(children),
            },
            RenderRichNode::Quote {
                author,
                post_number,
                topic_id,
                children,
            } => Self::Quote {
                author,
                post_number,
                topic_id,
                children: map_nodes(children),
            },
            RenderRichNode::List { ordered, items } => Self::ListNode {
                ordered,
                items: items.into_iter().map(map_nodes).collect(),
            },
            RenderRichNode::ListItem { children } => Self::ListItem {
                children: map_nodes(children),
            },
            RenderRichNode::Spoiler { children } => Self::Spoiler {
                children: map_nodes(children),
            },
            RenderRichNode::Details { summary, children } => Self::Details {
                summary: map_nodes(summary),
                children: map_nodes(children),
            },
            RenderRichNode::Table { text } => Self::Table { text },
            RenderRichNode::Video { url, title } => Self::Video { url, title },
            RenderRichNode::Divider => Self::Divider,
            RenderRichNode::LineBreak => Self::LineBreak,
            RenderRichNode::Paragraph { children } => Self::Paragraph {
                children: map_nodes(children),
            },
            RenderRichNode::Image {
                url,
                alt,
                width,
                height,
            } => Self::Image {
                url,
                alt,
                width,
                height,
            },
            RenderRichNode::Onebox(card) => Self::Onebox { card: card.into() },
        }
    }
}

fn map_nodes(nodes: Vec<RenderRichNode>) -> Vec<RenderRichNodeState> {
    nodes.into_iter().map(Into::into).collect()
}

#[derive(uniffi::Enum, Debug, Clone)]
pub enum RenderUiSegmentState {
    Rich { nodes: Vec<RenderRichNodeState> },
    Image { image: RenderImageAttachmentState },
    Onebox { card: RenderOneboxCardState },
}

impl From<RenderUiSegment> for RenderUiSegmentState {
    fn from(value: RenderUiSegment) -> Self {
        match value {
            RenderUiSegment::Rich { nodes } => Self::Rich {
                nodes: map_nodes(nodes),
            },
            RenderUiSegment::Image(image) => Self::Image {
                image: image.into(),
            },
            RenderUiSegment::Onebox(card) => Self::Onebox { card: card.into() },
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RenderPresentationState {
    pub checksum: u64,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachmentState>,
    pub segments: Vec<RenderUiSegmentState>,
}

impl From<RenderPresentation> for RenderPresentationState {
    fn from(value: RenderPresentation) -> Self {
        Self {
            checksum: value.checksum,
            plain_text: value.plain_text,
            image_attachments: value
                .image_attachments
                .into_iter()
                .map(Into::into)
                .collect(),
            segments: value.segments.into_iter().map(Into::into).collect(),
        }
    }
}
