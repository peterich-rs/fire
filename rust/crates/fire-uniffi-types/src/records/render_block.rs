use fire_models::{RenderBlock, RenderBlockKind, RenderDocument, RenderImageAttachment};

#[derive(uniffi::Enum, Debug, Clone)]
pub enum RenderBlockKindState {
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
    },
    Video {
        url: String,
        title: Option<String>,
    },
    Divider,
    Unknown,
}

impl From<RenderBlockKind> for RenderBlockKindState {
    fn from(value: RenderBlockKind) -> Self {
        match value {
            RenderBlockKind::Document => Self::Document,
            RenderBlockKind::Text { content } => Self::Text { content },
            RenderBlockKind::Paragraph => Self::Paragraph,
            RenderBlockKind::Heading { level } => Self::Heading { level },
            RenderBlockKind::LineBreak => Self::LineBreak,
            RenderBlockKind::Bold => Self::Bold,
            RenderBlockKind::Italic => Self::Italic,
            RenderBlockKind::Strikethrough => Self::Strikethrough,
            RenderBlockKind::InlineCode { code } => Self::InlineCode { code },
            RenderBlockKind::CodeBlock { language, code } => Self::CodeBlock { language, code },
            RenderBlockKind::Link { url } => Self::Link { url },
            RenderBlockKind::Mention { username } => Self::Mention { username },
            RenderBlockKind::MentionGroup { name, url } => Self::MentionGroup { name, url },
            RenderBlockKind::Hashtag { text, url, kind } => Self::Hashtag { text, url, kind },
            RenderBlockKind::Emoji {
                url,
                fallback_text,
                only_emoji,
            } => Self::Emoji {
                url,
                fallback_text,
                only_emoji,
            },
            RenderBlockKind::Image {
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
            RenderBlockKind::Blockquote => Self::Blockquote,
            RenderBlockKind::Quote {
                author,
                post_number,
                topic_id,
            } => Self::Quote {
                author,
                post_number,
                topic_id,
            },
            RenderBlockKind::List { ordered } => Self::List { ordered },
            RenderBlockKind::ListItem => Self::ListItem,
            RenderBlockKind::Spoiler => Self::Spoiler,
            RenderBlockKind::Details => Self::Details,
            RenderBlockKind::DetailsSummary => Self::DetailsSummary,
            RenderBlockKind::Table { text } => Self::Table { text },
            RenderBlockKind::Onebox {
                url,
                title,
                description,
            } => Self::Onebox {
                url,
                title,
                description,
            },
            RenderBlockKind::Video { url, title } => Self::Video { url, title },
            RenderBlockKind::Divider => Self::Divider,
            RenderBlockKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RenderBlockState {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub depth: u32,
    pub kind: RenderBlockKindState,
}

impl From<RenderBlock> for RenderBlockState {
    fn from(value: RenderBlock) -> Self {
        Self {
            id: value.id,
            parent_id: value.parent_id,
            depth: value.depth,
            kind: value.kind.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RenderImageAttachmentState {
    pub url: String,
    pub alt_text: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

impl From<RenderImageAttachment> for RenderImageAttachmentState {
    fn from(value: RenderImageAttachment) -> Self {
        Self {
            url: value.url,
            alt_text: value.alt_text,
            width: value.width,
            height: value.height,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RenderDocumentState {
    pub blocks: Vec<RenderBlockState>,
    pub plain_text: String,
    pub image_attachments: Vec<RenderImageAttachmentState>,
}

impl From<RenderDocument> for RenderDocumentState {
    fn from(value: RenderDocument) -> Self {
        Self {
            blocks: value.blocks.into_iter().map(Into::into).collect(),
            plain_text: value.plain_text,
            image_attachments: value
                .image_attachments
                .into_iter()
                .map(Into::into)
                .collect(),
        }
    }
}
