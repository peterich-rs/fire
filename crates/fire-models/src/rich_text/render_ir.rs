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

