#[uniffi::export]
pub fn plain_text_from_html(raw_html: String) -> String {
    shared_plain_text_from_html(&raw_html)
}

#[uniffi::export]
pub fn parse_cooked_html(raw_html: String) -> CookedHtmlDocumentState {
    shared_parse_cooked_html(&raw_html).into()
}

#[uniffi::export]
pub fn present_cooked_html(
    raw_html: String,
    base_url: String,
) -> Option<std::sync::Arc<fire_uniffi_types::RenderDocumentHandle>> {
    shared_present_cooked_html(&raw_html, &base_url)
        .map(std::sync::Arc::new)
        .map(fire_uniffi_types::intern_presented_handle)
}

#[uniffi::export]
pub fn preview_text_from_html(raw_html: Option<String>) -> Option<String> {
    shared_preview_text_from_html(raw_html.as_deref())
}

#[uniffi::export]
pub fn monogram_for_username(username: String) -> String {
    shared_monogram_for_username(&username)
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum CookedHtmlNodeKindState {
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

impl From<CookedHtmlNodeKind> for CookedHtmlNodeKindState {
    fn from(value: CookedHtmlNodeKind) -> Self {
        match value {
            CookedHtmlNodeKind::Document => Self::Document,
            CookedHtmlNodeKind::Text => Self::Text,
            CookedHtmlNodeKind::Paragraph => Self::Paragraph,
            CookedHtmlNodeKind::Heading => Self::Heading,
            CookedHtmlNodeKind::LineBreak => Self::LineBreak,
            CookedHtmlNodeKind::Strong => Self::Strong,
            CookedHtmlNodeKind::Emphasis => Self::Emphasis,
            CookedHtmlNodeKind::Strikethrough => Self::Strikethrough,
            CookedHtmlNodeKind::Link => Self::Link,
            CookedHtmlNodeKind::Image => Self::Image,
            CookedHtmlNodeKind::Emoji => Self::Emoji,
            CookedHtmlNodeKind::Code => Self::Code,
            CookedHtmlNodeKind::CodeBlock => Self::CodeBlock,
            CookedHtmlNodeKind::Blockquote => Self::Blockquote,
            CookedHtmlNodeKind::DiscourseQuote => Self::DiscourseQuote,
            CookedHtmlNodeKind::Divider => Self::Divider,
            CookedHtmlNodeKind::List => Self::List,
            CookedHtmlNodeKind::ListItem => Self::ListItem,
            CookedHtmlNodeKind::Spoiler => Self::Spoiler,
            CookedHtmlNodeKind::Details => Self::Details,
            CookedHtmlNodeKind::Table => Self::Table,
            CookedHtmlNodeKind::TableRow => Self::TableRow,
            CookedHtmlNodeKind::TableCell => Self::TableCell,
            CookedHtmlNodeKind::Onebox => Self::Onebox,
            CookedHtmlNodeKind::Iframe => Self::Iframe,
            CookedHtmlNodeKind::Mention => Self::Mention,
            CookedHtmlNodeKind::Hashtag => Self::Hashtag,
            CookedHtmlNodeKind::Attachment => Self::Attachment,
            CookedHtmlNodeKind::Unknown => Self::Unknown,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlAttributeState {
    pub name: String,
    pub value: String,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlNodeState {
    pub id: u32,
    pub parent_id: Option<u32>,
    pub kind: CookedHtmlNodeKindState,
    pub depth: u32,
    pub text: Option<String>,
    pub url: Option<String>,
    pub title: Option<String>,
    pub alt: Option<String>,
    pub level: Option<u32>,
    pub ordered: Option<bool>,
    pub attributes: Vec<CookedHtmlAttributeState>,
}

impl From<CookedHtmlNode> for CookedHtmlNodeState {
    fn from(value: CookedHtmlNode) -> Self {
        Self {
            id: value.id,
            parent_id: value.parent_id,
            kind: value.kind.into(),
            depth: value.depth,
            text: value.text,
            url: value.url,
            title: value.title,
            alt: value.alt,
            level: value.level,
            ordered: value.ordered,
            attributes: value
                .attributes
                .into_iter()
                .map(|(name, value)| CookedHtmlAttributeState { name, value })
                .collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CookedHtmlDocumentState {
    pub nodes: Vec<CookedHtmlNodeState>,
    pub plain_text: String,
    pub image_urls: Vec<String>,
    pub link_urls: Vec<String>,
}

impl From<CookedHtmlDocument> for CookedHtmlDocumentState {
    fn from(value: CookedHtmlDocument) -> Self {
        Self {
            nodes: value.nodes.into_iter().map(Into::into).collect(),
            plain_text: value.plain_text,
            image_urls: value.image_urls,
            link_urls: value.link_urls,
        }
    }
}
