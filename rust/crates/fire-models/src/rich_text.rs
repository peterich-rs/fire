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
