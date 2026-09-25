use std::collections::{BTreeMap, HashMap, HashSet};

use fire_models::{CookedHtmlNode, CookedHtmlNodeKind, RenderBlock, RenderBlockKind};
use url::Url;

use crate::emoji;
use crate::images::{
    cleaned_text_node_content, is_avatar_url, is_profile_url, is_quote_title_separator,
    should_skip_render_image, should_suppress_link_for_inline_image,
};
use crate::onebox::onebox_presentation;
use crate::plain_text::{append_subtree_text, extract_text_content, PlainTextBuilder};

#[derive(Debug, Clone, Default)]
pub(crate) struct TreeRenderBlock {
    pub(crate) kind: RenderBlockKind,
    pub(crate) children: Vec<TreeRenderBlock>,
}

pub(crate) fn flatten_tree(root: &TreeRenderBlock) -> Vec<RenderBlock> {
    fn visit(
        node: &TreeRenderBlock,
        parent_id: Option<u32>,
        depth: u32,
        next_id: &mut u32,
        blocks: &mut Vec<RenderBlock>,
    ) {
        let id = *next_id;
        *next_id += 1;
        blocks.push(RenderBlock {
            id,
            parent_id,
            depth,
            kind: node.kind.clone(),
        });
        for child in &node.children {
            visit(child, Some(id), depth + 1, next_id, blocks);
        }
    }

    let mut blocks = Vec::new();
    let mut next_id = 0_u32;
    visit(root, None, 0, &mut next_id, &mut blocks);
    blocks
}

pub(crate) struct CookedTree<'a> {
    pub(crate) root: Option<&'a CookedHtmlNode>,
    nodes_by_id: HashMap<u32, &'a CookedHtmlNode>,
    children_by_parent_id: HashMap<u32, Vec<&'a CookedHtmlNode>>,
}

impl<'a> CookedTree<'a> {
    pub(crate) fn new(nodes: &'a [CookedHtmlNode]) -> Self {
        let nodes_by_id = nodes
            .iter()
            .map(|node| (node.id, node))
            .collect::<HashMap<_, _>>();
        let mut children_by_parent_id = HashMap::<u32, Vec<&CookedHtmlNode>>::new();
        for node in nodes {
            if let Some(parent_id) = node.parent_id {
                children_by_parent_id
                    .entry(parent_id)
                    .or_default()
                    .push(node);
            }
        }
        let root = nodes
            .iter()
            .find(|node| node.parent_id.is_none() && node.kind == CookedHtmlNodeKind::Document)
            .or_else(|| nodes.iter().find(|node| node.parent_id.is_none()));

        Self {
            root,
            nodes_by_id,
            children_by_parent_id,
        }
    }

    pub(crate) fn node(&self, id: Option<u32>) -> Option<&'a CookedHtmlNode> {
        id.and_then(|value| self.nodes_by_id.get(&value).copied())
    }

    pub(crate) fn children_of(&self, node: &'a CookedHtmlNode) -> Vec<&'a CookedHtmlNode> {
        self.children_by_parent_id
            .get(&node.id)
            .cloned()
            .unwrap_or_default()
    }

    pub(crate) fn nearest_ancestor<F>(
        &self,
        node: &'a CookedHtmlNode,
        mut predicate: F,
    ) -> Option<&'a CookedHtmlNode>
    where
        F: FnMut(&CookedHtmlNode) -> bool,
    {
        let mut current = self.node(node.parent_id);
        while let Some(candidate) = current {
            if predicate(candidate) {
                return Some(candidate);
            }
            current = self.node(candidate.parent_id);
        }
        None
    }
}

pub(crate) fn map_node(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
    base_url: &str,
) -> Vec<TreeRenderBlock> {
    let children = tree
        .children_of(node)
        .into_iter()
        .flat_map(|child| map_node(child, tree, base_url))
        .collect::<Vec<_>>();
    let attrs = normalized_attributes(node);

    match &node.kind {
        CookedHtmlNodeKind::Document => children,
        CookedHtmlNodeKind::Text => normalized_text(node.text.as_deref())
            .and_then(|content| cleaned_text_node_content(node, content, tree))
            .map(|content| {
                emoji::kinds_from_text_with_shortcodes(content, base_url)
                    .into_iter()
                    .map(|kind| TreeRenderBlock {
                        kind,
                        children: Vec::new(),
                    })
                    .collect()
            })
            .unwrap_or_default(),
        CookedHtmlNodeKind::Paragraph => vec![TreeRenderBlock {
            kind: RenderBlockKind::Paragraph,
            children,
        }],
        CookedHtmlNodeKind::Heading => vec![TreeRenderBlock {
            kind: RenderBlockKind::Heading {
                level: node.level.unwrap_or(2).clamp(1, 6) as u8,
            },
            children,
        }],
        CookedHtmlNodeKind::LineBreak => vec![TreeRenderBlock {
            kind: RenderBlockKind::LineBreak,
            children: Vec::new(),
        }],
        CookedHtmlNodeKind::Strong => vec![TreeRenderBlock {
            kind: RenderBlockKind::Bold,
            children,
        }],
        CookedHtmlNodeKind::Emphasis => vec![TreeRenderBlock {
            kind: RenderBlockKind::Italic,
            children,
        }],
        CookedHtmlNodeKind::Strikethrough => vec![TreeRenderBlock {
            kind: RenderBlockKind::Strikethrough,
            children,
        }],
        CookedHtmlNodeKind::Code => vec![TreeRenderBlock {
            kind: RenderBlockKind::InlineCode {
                code: subtree_text(node, tree),
            },
            children: Vec::new(),
        }],
        CookedHtmlNodeKind::CodeBlock => vec![TreeRenderBlock {
            kind: RenderBlockKind::CodeBlock {
                language: code_language(node, tree),
                code: subtree_text(node, tree),
            },
            children: Vec::new(),
        }],
        CookedHtmlNodeKind::Link => map_link_node(node, children, &attrs, tree, base_url),
        CookedHtmlNodeKind::Mention => {
            let username = extract_text_content(&children, false)
                .trim()
                .trim_start_matches('@')
                .to_string();
            if username.is_empty() {
                children
            } else {
                vec![TreeRenderBlock {
                    kind: RenderBlockKind::Mention { username },
                    children: Vec::new(),
                }]
            }
        }
        CookedHtmlNodeKind::Hashtag => {
            let text = extract_text_content(&children, false)
                .trim()
                .trim_start_matches('#')
                .to_string();
            let url = resolve_url(node.url.as_deref().unwrap_or_default(), base_url);
            if text.is_empty() {
                children
            } else {
                vec![TreeRenderBlock {
                    kind: RenderBlockKind::Hashtag {
                        text,
                        url,
                        kind: normalized_text(attrs.get("data-type").map(String::as_str)),
                    },
                    children: Vec::new(),
                }]
            }
        }
        CookedHtmlNodeKind::Image => {
            let Some(url) = resolved_url_string(node.url.as_deref(), base_url) else {
                return Vec::new();
            };
            if is_emoji_node(node) || should_skip_render_image(node, &url, &attrs, tree) {
                return Vec::new();
            }
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Image {
                    url,
                    alt: normalized_text(node.alt.as_deref()),
                    width: numeric_attribute("width", &attrs),
                    height: numeric_attribute("height", &attrs),
                },
                children: Vec::new(),
            }]
        }
        CookedHtmlNodeKind::Emoji => {
            let Some(url) = resolved_url_string(node.url.as_deref(), base_url) else {
                return Vec::new();
            };
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Emoji {
                    fallback_text: emoji_fallback_text(&attrs, &url),
                    only_emoji: class_names(attrs.get("class").map(String::as_str))
                        .contains("only-emoji"),
                    url,
                },
                children: Vec::new(),
            }]
        }
        CookedHtmlNodeKind::Blockquote => vec![TreeRenderBlock {
            kind: RenderBlockKind::Blockquote,
            children,
        }],
        CookedHtmlNodeKind::DiscourseQuote => vec![TreeRenderBlock {
            kind: RenderBlockKind::Quote {
                author: normalized_text(
                    attrs
                        .get("data-username")
                        .map(String::as_str)
                        .or(node.title.as_deref()),
                ),
                post_number: attrs.get("data-post").and_then(|value| value.parse().ok()),
                topic_id: attrs.get("data-topic").and_then(|value| value.parse().ok()),
            },
            children: normalize_quoted_children(children),
        }],
        CookedHtmlNodeKind::Divider => vec![TreeRenderBlock {
            kind: RenderBlockKind::Divider,
            children: Vec::new(),
        }],
        CookedHtmlNodeKind::List => {
            let mut items = tree
                .children_of(node)
                .into_iter()
                .filter(|child| child.kind == CookedHtmlNodeKind::ListItem)
                .flat_map(|child| map_node(child, tree, base_url))
                .collect::<Vec<_>>();
            if items.is_empty() {
                items = children;
            }
            vec![TreeRenderBlock {
                kind: RenderBlockKind::List {
                    ordered: node.ordered.unwrap_or(false),
                },
                children: items,
            }]
        }
        CookedHtmlNodeKind::ListItem => vec![TreeRenderBlock {
            kind: RenderBlockKind::ListItem,
            children,
        }],
        CookedHtmlNodeKind::Spoiler => vec![TreeRenderBlock {
            kind: RenderBlockKind::Spoiler,
            children,
        }],
        CookedHtmlNodeKind::Details => {
            let (summary, body) = details_parts(children);
            let mut details_children = Vec::new();
            if !summary.is_empty() {
                details_children.push(TreeRenderBlock {
                    kind: RenderBlockKind::DetailsSummary,
                    children: summary,
                });
            }
            details_children.extend(body);
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Details,
                children: details_children,
            }]
        }
        CookedHtmlNodeKind::Table => vec![TreeRenderBlock {
            kind: RenderBlockKind::Table {
                text: table_plain_text(node, tree),
            },
            children: Vec::new(),
        }],
        CookedHtmlNodeKind::TableRow | CookedHtmlNodeKind::TableCell => children,
        CookedHtmlNodeKind::Onebox => {
            let presentation = onebox_presentation(node, tree, base_url);
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Onebox {
                    url: resolved_url_string(node.url.as_deref(), base_url),
                    title: presentation.title,
                    description: presentation.description,
                    source_name: presentation.source_name,
                    icon_url: presentation.icon_url,
                    thumbnail_url: presentation.thumbnail_url,
                    thumbnail_width: presentation.thumbnail_width,
                    thumbnail_height: presentation.thumbnail_height,
                },
                children: Vec::new(),
            }]
        }
        CookedHtmlNodeKind::Iframe => {
            let Some(url) = resolved_url_string(node.url.as_deref(), base_url) else {
                return children;
            };
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Video {
                    url,
                    title: normalized_text(node.title.as_deref()),
                },
                children: Vec::new(),
            }]
        }
        CookedHtmlNodeKind::Attachment => {
            let url = resolve_url(node.url.as_deref().unwrap_or_default(), base_url);
            if url.is_empty() {
                children
            } else {
                vec![TreeRenderBlock {
                    kind: RenderBlockKind::Link { url },
                    children,
                }]
            }
        }
        CookedHtmlNodeKind::Unknown => children,
    }
}

fn map_link_node(
    node: &CookedHtmlNode,
    children: Vec<TreeRenderBlock>,
    attrs: &BTreeMap<String, String>,
    tree: &CookedTree<'_>,
    base_url: &str,
) -> Vec<TreeRenderBlock> {
    let url = resolve_url(node.url.as_deref().unwrap_or_default(), base_url);
    let classes = class_names(attrs.get("class").map(String::as_str));

    if classes.contains("mention-group") {
        let name = extract_text_content(&children, false)
            .trim()
            .trim_start_matches('@')
            .to_string();
        return if name.is_empty() {
            children
        } else {
            vec![TreeRenderBlock {
                kind: RenderBlockKind::MentionGroup { name, url },
                children: Vec::new(),
            }]
        };
    }
    if classes.contains("mention") {
        let username = extract_text_content(&children, false)
            .trim()
            .trim_start_matches('@')
            .to_string();
        return if username.is_empty() {
            children
        } else {
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Mention { username },
                children: Vec::new(),
            }]
        };
    }
    if classes.contains("hashtag") || classes.contains("hashtag-cooked") {
        let text = extract_text_content(&children, false)
            .trim()
            .trim_start_matches('#')
            .to_string();
        return if text.is_empty() {
            children
        } else {
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Hashtag {
                    text,
                    url,
                    kind: normalized_text(attrs.get("data-type").map(String::as_str)),
                },
                children: Vec::new(),
            }]
        };
    }
    if should_suppress_link_for_inline_image(&url, &classes, &children)
        || tree
            .nearest_ancestor(node, |ancestor| {
                ancestor.kind == CookedHtmlNodeKind::Attachment
            })
            .is_some()
    {
        return children;
    }
    vec![TreeRenderBlock {
        kind: RenderBlockKind::Link { url },
        children,
    }]
}

pub(crate) fn normalized_attributes(node: &CookedHtmlNode) -> BTreeMap<String, String> {
    node.attributes
        .iter()
        .map(|(key, value)| (key.to_ascii_lowercase(), value.clone()))
        .collect()
}

pub(crate) fn normalized_text(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

pub(crate) fn resolve_url(raw: &str, base_url: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    if trimmed.starts_with("//") {
        return format!("https:{trimmed}");
    }
    if let Ok(url) = Url::parse(trimmed) {
        return url.to_string();
    }
    Url::parse(base_url)
        .ok()
        .and_then(|base| base.join(trimmed).ok())
        .map(|url| url.to_string())
        .unwrap_or_else(|| trimmed.to_string())
}

pub(crate) fn resolved_url_string(raw: Option<&str>, base_url: &str) -> Option<String> {
    let resolved = resolve_url(raw.unwrap_or_default(), base_url);
    (!resolved.is_empty()).then_some(resolved)
}

pub(crate) fn subtree_text(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> String {
    let mut builder = PlainTextBuilder::default();
    append_subtree_text(node, tree, &mut builder);
    builder.finish()
}

fn code_language(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> Option<String> {
    let attrs = normalized_attributes(node);
    for class_name in class_names(attrs.get("class").map(String::as_str)) {
        if let Some(language) = class_name.strip_prefix("language-") {
            return Some(language.to_string());
        }
        if let Some(language) = class_name.strip_prefix("lang-") {
            return Some(language.to_string());
        }
    }
    for child in tree.children_of(node) {
        if let Some(language) = code_language(child, tree) {
            return Some(language);
        }
    }
    None
}

pub(crate) fn is_emoji_node(node: &CookedHtmlNode) -> bool {
    if node.kind == CookedHtmlNodeKind::Emoji {
        return true;
    }
    let attrs = normalized_attributes(node);
    class_names(attrs.get("class").map(String::as_str)).contains("emoji")
        || node
            .url
            .as_deref()
            .is_some_and(|url| url.contains("/images/emoji/"))
}

pub(crate) fn class_names(raw: Option<&str>) -> HashSet<String> {
    raw.unwrap_or_default()
        .split_whitespace()
        .filter(|name| !name.is_empty())
        .map(|name| name.to_ascii_lowercase())
        .collect()
}

pub(crate) fn numeric_attribute(name: &str, attrs: &BTreeMap<String, String>) -> Option<u32> {
    attrs.get(name).and_then(|value| value.parse().ok())
}

pub(crate) fn emoji_fallback_text(attrs: &BTreeMap<String, String>, resolved_url: &str) -> String {
    attrs
        .get("title")
        .and_then(|value| normalized_emoji_fallback(value))
        .or_else(|| {
            attrs
                .get("alt")
                .and_then(|value| normalized_emoji_fallback(value))
        })
        .or_else(|| emoji_shortcode(resolved_url))
        .unwrap_or_else(|| ":emoji:".to_string())
}

fn emoji_shortcode(url: &str) -> Option<String> {
    let path = Url::parse(url)
        .ok()
        .map(|parsed| parsed.path().to_string())
        .unwrap_or_else(|| url.to_string());
    let marker = "/images/emoji/";
    let index = path.find(marker)?;
    let components = path[index + marker.len()..]
        .split('/')
        .map(|component| {
            component
                .rsplit_once('.')
                .map(|(head, _)| head)
                .unwrap_or(component)
        })
        .filter(|component| !component.is_empty())
        .collect::<Vec<_>>();
    if components.len() < 2 {
        return None;
    }
    normalized_emoji_fallback(&components[1..].join(":"))
}

fn normalized_emoji_fallback(raw: &str) -> Option<String> {
    let trimmed = normalized_text(Some(raw))?;
    let trimmed_colons = trimmed.trim_matches(':');
    let needs_wrapping = trimmed
        .chars()
        .any(|character| character.is_ascii_alphanumeric() || character == '_' || character == '-');
    if needs_wrapping && !trimmed_colons.is_empty() {
        Some(format!(":{trimmed_colons}:"))
    } else {
        Some(trimmed)
    }
}

fn normalize_quoted_children(children: Vec<TreeRenderBlock>) -> Vec<TreeRenderBlock> {
    let meaningful = children
        .into_iter()
        .flat_map(remove_quote_chrome)
        .filter(is_meaningful_render_block)
        .collect::<Vec<_>>();
    let quoted_body = meaningful
        .iter()
        .filter(|child| child.kind == RenderBlockKind::Blockquote)
        .flat_map(|child| child.children.clone())
        .collect::<Vec<_>>();
    if !quoted_body.is_empty() {
        return quoted_body;
    }
    if meaningful.len() == 1 && meaningful[0].kind == RenderBlockKind::Blockquote {
        return meaningful[0].children.clone();
    }
    meaningful
}

fn remove_quote_chrome(mut child: TreeRenderBlock) -> Vec<TreeRenderBlock> {
    child.children = child
        .children
        .into_iter()
        .flat_map(remove_quote_chrome)
        .filter(is_meaningful_render_block)
        .collect();

    match &child.kind {
        RenderBlockKind::Image { url, .. } if is_avatar_url(url) => Vec::new(),
        RenderBlockKind::Text { content } if is_quote_title_separator(content) => Vec::new(),
        RenderBlockKind::Link { url } if is_profile_url(url) && child.children.is_empty() => {
            Vec::new()
        }
        RenderBlockKind::Paragraph | RenderBlockKind::Blockquote if child.children.is_empty() => {
            Vec::new()
        }
        _ => vec![child],
    }
}

fn is_meaningful_render_block(child: &TreeRenderBlock) -> bool {
    match &child.kind {
        RenderBlockKind::Text { content } => !content.trim().is_empty(),
        RenderBlockKind::Paragraph | RenderBlockKind::Blockquote => !child.children.is_empty(),
        _ => true,
    }
}

fn details_parts(children: Vec<TreeRenderBlock>) -> (Vec<TreeRenderBlock>, Vec<TreeRenderBlock>) {
    let mut summary = Vec::new();
    let mut body = Vec::new();
    let mut reading_summary = true;

    for child in children {
        if reading_summary && is_inline_details_summary_node(&child) {
            summary.push(child);
        } else {
            reading_summary = false;
            body.push(child);
        }
    }

    if summary.is_empty() {
        summary.push(TreeRenderBlock {
            kind: RenderBlockKind::Text {
                content: "Details".to_string(),
            },
            children: Vec::new(),
        });
    }
    (summary, body)
}

fn is_inline_details_summary_node(node: &TreeRenderBlock) -> bool {
    matches!(
        node.kind,
        RenderBlockKind::Text { .. }
            | RenderBlockKind::Bold
            | RenderBlockKind::Italic
            | RenderBlockKind::Strikethrough
            | RenderBlockKind::InlineCode { .. }
            | RenderBlockKind::Link { .. }
            | RenderBlockKind::Mention { .. }
            | RenderBlockKind::MentionGroup { .. }
            | RenderBlockKind::Hashtag { .. }
            | RenderBlockKind::Emoji { .. }
    )
}

fn table_plain_text(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> String {
    let rows = tree
        .children_of(node)
        .into_iter()
        .filter(|row| row.kind == CookedHtmlNodeKind::TableRow)
        .collect::<Vec<_>>();
    if rows.is_empty() {
        return subtree_text(node, tree);
    }

    rows.into_iter()
        .filter_map(|row| {
            let text = tree
                .children_of(row)
                .into_iter()
                .filter(|cell| cell.kind == CookedHtmlNodeKind::TableCell)
                .map(|cell| subtree_text(cell, tree).trim().to_string())
                .filter(|value| !value.is_empty())
                .collect::<Vec<_>>()
                .join(" | ");
            (!text.is_empty()).then_some(text)
        })
        .collect::<Vec<_>>()
        .join("\n")
}
