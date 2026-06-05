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
