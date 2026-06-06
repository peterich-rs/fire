use std::collections::{BTreeMap, HashMap, HashSet};

use fire_models::{
    CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderBlock, RenderBlockKind,
    RenderDocument, RenderImageAttachment,
};
use url::Url;

#[derive(Debug, Clone, Default)]
struct TreeRenderBlock {
    kind: RenderBlockKind,
    children: Vec<TreeRenderBlock>,
}

pub fn render_document(document: &CookedHtmlDocument, base_url: &str) -> RenderDocument {
    let tree = CookedTree::new(&document.nodes);
    let root = tree
        .root
        .unwrap_or_else(|| panic!("CookedHtmlDocument is missing a document root node"));

    let mut root_block = TreeRenderBlock {
        kind: RenderBlockKind::Document,
        children: Vec::new(),
    };
    for child in tree.children_of(root) {
        root_block.children.extend(map_node(child, &tree, base_url));
    }

    RenderDocument {
        blocks: flatten_tree(&root_block),
        plain_text: document.plain_text.clone(),
        image_attachments: collect_image_attachments(document, &tree, base_url),
    }
}

pub fn plain_text_from_render_document(document: &RenderDocument) -> String {
    document.plain_text.clone()
}

pub fn collect_images(document: &RenderDocument) -> Vec<RenderImageAttachment> {
    document.image_attachments.clone()
}

fn flatten_tree(root: &TreeRenderBlock) -> Vec<RenderBlock> {
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

struct CookedTree<'a> {
    root: Option<&'a CookedHtmlNode>,
    nodes_by_id: HashMap<u32, &'a CookedHtmlNode>,
    children_by_parent_id: HashMap<u32, Vec<&'a CookedHtmlNode>>,
}

impl<'a> CookedTree<'a> {
    fn new(nodes: &'a [CookedHtmlNode]) -> Self {
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

    fn node(&self, id: Option<u32>) -> Option<&'a CookedHtmlNode> {
        id.and_then(|value| self.nodes_by_id.get(&value).copied())
    }

    fn children_of(&self, node: &'a CookedHtmlNode) -> Vec<&'a CookedHtmlNode> {
        self.children_by_parent_id
            .get(&node.id)
            .cloned()
            .unwrap_or_default()
    }

    fn nearest_ancestor<F>(
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

fn map_node(node: &CookedHtmlNode, tree: &CookedTree<'_>, base_url: &str) -> Vec<TreeRenderBlock> {
    let children = tree
        .children_of(node)
        .into_iter()
        .flat_map(|child| map_node(child, tree, base_url))
        .collect::<Vec<_>>();
    let attrs = normalized_attributes(node);

    match &node.kind {
        CookedHtmlNodeKind::Document => children,
        CookedHtmlNodeKind::Text => normalized_text(node.text.as_deref())
            .map(|content| {
                vec![TreeRenderBlock {
                    kind: RenderBlockKind::Text { content },
                    children: Vec::new(),
                }]
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
            if is_emoji_node(node) {
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
        CookedHtmlNodeKind::Onebox => vec![TreeRenderBlock {
            kind: RenderBlockKind::Onebox {
                url: resolved_url_string(node.url.as_deref(), base_url),
                title: normalized_text(node.title.as_deref())
                    .or_else(|| normalized_text(Some(&subtree_text(node, tree)))),
                description: None,
            },
            children: Vec::new(),
        }],
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

fn normalized_attributes(node: &CookedHtmlNode) -> BTreeMap<String, String> {
    node.attributes
        .iter()
        .map(|(key, value)| (key.to_ascii_lowercase(), value.clone()))
        .collect()
}

fn normalized_text(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

fn resolve_url(raw: &str, base_url: &str) -> String {
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

fn resolved_url_string(raw: Option<&str>, base_url: &str) -> Option<String> {
    let resolved = resolve_url(raw.unwrap_or_default(), base_url);
    (!resolved.is_empty()).then_some(resolved)
}

fn subtree_text(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> String {
    let mut builder = PlainTextBuilder::default();
    append_subtree_text(node, tree, &mut builder);
    builder.finish()
}

fn append_subtree_text(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
    builder: &mut PlainTextBuilder,
) {
    match node.kind {
        CookedHtmlNodeKind::Text => builder.append_inline(node.text.as_deref().unwrap_or_default()),
        CookedHtmlNodeKind::LineBreak => builder.ensure_line_break(),
        CookedHtmlNodeKind::Image if is_emoji_node(node) => {
            builder.append_inline(&emoji_fallback_text(
                &normalized_attributes(node),
                node.url.as_deref().unwrap_or_default(),
            ))
        }
        CookedHtmlNodeKind::Emoji => builder.append_inline(&emoji_fallback_text(
            &normalized_attributes(node),
            node.url.as_deref().unwrap_or_default(),
        )),
        CookedHtmlNodeKind::TableCell => {
            for child in tree.children_of(node) {
                append_subtree_text(child, tree, builder);
            }
            builder.append_inline(" ");
        }
        CookedHtmlNodeKind::TableRow | CookedHtmlNodeKind::ListItem => {
            for child in tree.children_of(node) {
                append_subtree_text(child, tree, builder);
            }
            builder.ensure_line_break();
        }
        _ => {
            for child in tree.children_of(node) {
                append_subtree_text(child, tree, builder);
            }
        }
    }
}

fn extract_text_content(nodes: &[TreeRenderBlock], including_emoji_fallback: bool) -> String {
    let mut result = String::new();
    for node in nodes {
        match &node.kind {
            RenderBlockKind::Text { content } => result.push_str(content),
            RenderBlockKind::InlineCode { code } | RenderBlockKind::CodeBlock { code, .. } => {
                result.push_str(code)
            }
            RenderBlockKind::Mention { username } => {
                result.push('@');
                result.push_str(username);
            }
            RenderBlockKind::MentionGroup { name, .. } => {
                result.push('@');
                result.push_str(name);
            }
            RenderBlockKind::Hashtag { text, .. } => {
                result.push('#');
                result.push_str(text);
            }
            RenderBlockKind::Emoji { fallback_text, .. } if including_emoji_fallback => {
                result.push_str(fallback_text)
            }
            RenderBlockKind::Onebox {
                title,
                description,
                url,
            } => {
                for value in [title.as_deref(), description.as_deref(), url.as_deref()]
                    .into_iter()
                    .flatten()
                {
                    if !result.is_empty() {
                        result.push('\n');
                    }
                    result.push_str(value);
                }
            }
            RenderBlockKind::Table { text } => result.push_str(text),
            RenderBlockKind::Video { title, url } => {
                result.push_str(title.as_deref().unwrap_or(url));
            }
            RenderBlockKind::Divider | RenderBlockKind::LineBreak => result.push('\n'),
            RenderBlockKind::Image { .. } => {}
            _ => result.push_str(&extract_text_content(
                &node.children,
                including_emoji_fallback,
            )),
        }
    }
    result
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

fn is_emoji_node(node: &CookedHtmlNode) -> bool {
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

fn class_names(raw: Option<&str>) -> HashSet<String> {
    raw.unwrap_or_default()
        .split_whitespace()
        .filter(|name| !name.is_empty())
        .map(|name| name.to_ascii_lowercase())
        .collect()
}

fn numeric_attribute(name: &str, attrs: &BTreeMap<String, String>) -> Option<u32> {
    attrs.get(name).and_then(|value| value.parse().ok())
}

fn emoji_fallback_text(attrs: &BTreeMap<String, String>, resolved_url: &str) -> String {
    normalized_text(attrs.get("title").map(String::as_str))
        .or_else(|| normalized_text(attrs.get("alt").map(String::as_str)))
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
        .filter(|child| match &child.kind {
            RenderBlockKind::Text { content } => !content.trim().is_empty(),
            _ => true,
        })
        .collect::<Vec<_>>();
    if meaningful.len() == 1 && meaningful[0].kind == RenderBlockKind::Blockquote {
        return meaningful[0].children.clone();
    }
    meaningful
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

fn should_suppress_link_for_inline_image(
    url: &str,
    classes: &HashSet<String>,
    children: &[TreeRenderBlock],
) -> bool {
    let visible_text = extract_text_content(children, false).trim().to_string();
    let image_like_url = is_image_url(url);
    if classes.contains("lightbox") {
        return true;
    }
    if classes.contains("attachment") && image_like_url {
        return visible_text.is_empty() || looks_like_image_filename(&visible_text);
    }
    if children.is_empty() && image_like_url {
        return true;
    }
    image_like_url && looks_like_image_filename(&visible_text)
}

fn is_image_url(value: &str) -> bool {
    let normalized = value.to_ascii_lowercase();
    normalized.ends_with(".jpg")
        || normalized.ends_with(".jpeg")
        || normalized.ends_with(".png")
        || normalized.ends_with(".gif")
        || normalized.ends_with(".webp")
        || normalized.ends_with(".avif")
        || normalized.contains("/uploads/")
        || normalized.contains("/original/")
        || normalized.contains("/images/emoji/")
}

fn looks_like_image_filename(value: &str) -> bool {
    !value.is_empty() && is_image_url(value)
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

fn collect_image_attachments(
    document: &CookedHtmlDocument,
    tree: &CookedTree<'_>,
    base_url: &str,
) -> Vec<RenderImageAttachment> {
    let mut seen = HashSet::new();
    let mut images = Vec::new();

    for node in &document.nodes {
        if node.kind != CookedHtmlNodeKind::Image || is_emoji_node(node) {
            continue;
        }

        let attrs = normalized_attributes(node);
        let preferred_source = tree
            .nearest_ancestor(node, |ancestor| {
                matches!(
                    ancestor.kind,
                    CookedHtmlNodeKind::Link | CookedHtmlNodeKind::Attachment
                )
            })
            .and_then(|ancestor| ancestor.url.clone());
        let Some(raw_source) = preferred_source
            .as_deref()
            .and_then(|value| normalized_text(Some(value)))
            .or_else(|| normalized_text(node.url.as_deref()))
        else {
            continue;
        };
        let Some(source_url) = resolved_asset_url(&raw_source, base_url) else {
            continue;
        };
        if should_skip_image_attachment(node, &source_url, &attrs, tree) {
            continue;
        }

        if source_url.contains("/images/emoji/") || !seen.insert(source_url.clone()) {
            continue;
        }
        images.push(RenderImageAttachment {
            url: source_url,
            alt_text: normalized_text(node.alt.as_deref()),
            width: numeric_attribute("width", &attrs),
            height: numeric_attribute("height", &attrs),
        });
    }

    images
}

fn should_skip_image_attachment(
    node: &CookedHtmlNode,
    source_url: &str,
    attrs: &BTreeMap<String, String>,
    tree: &CookedTree<'_>,
) -> bool {
    let classes = class_names(attrs.get("class").map(String::as_str));
    let normalized_path = Url::parse(source_url)
        .ok()
        .map(|parsed| parsed.path().to_ascii_lowercase())
        .unwrap_or_else(|| source_url.to_ascii_lowercase());

    if classes.contains("avatar")
        || classes.contains("user-avatar")
        || classes.contains("thumbnail")
        || classes.contains("ytp-thumbnail-image")
        || normalized_path.contains("/user_avatar/")
        || normalized_path.contains("/letter_avatar/")
    {
        return true;
    }

    tree.nearest_ancestor(node, |ancestor| {
        ancestor.kind == CookedHtmlNodeKind::DiscourseQuote
    })
    .is_some()
        && (classes.contains("quote-avatar")
            || normalized_path.contains("/user_avatar/")
            || normalized_path.contains("/letter_avatar/"))
}

fn resolved_asset_url(raw: &str, base_url: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.starts_with("//") {
        return Some(format!("https:{trimmed}"));
    }
    if let Ok(url) = Url::parse(trimmed) {
        return Some(url.to_string());
    }
    Url::parse(base_url)
        .ok()
        .and_then(|base| base.join(trimmed).ok())
        .map(|url| url.to_string())
}

#[derive(Default)]
struct PlainTextBuilder {
    storage: String,
}

impl PlainTextBuilder {
    fn append_inline(&mut self, value: &str) {
        let trimmed = value.replace('\u{00A0}', " ");
        let trimmed = trimmed.trim();
        if trimmed.is_empty() {
            return;
        }
        if !self.storage.is_empty()
            && !self.storage.ends_with(char::is_whitespace)
            && !starts_with_closing_punctuation(trimmed)
        {
            self.storage.push(' ');
        }
        self.storage.push_str(trimmed);
    }

    fn ensure_line_break(&mut self) {
        while self.storage.ends_with([' ', '\t']) {
            self.storage.pop();
        }
        if !self.storage.is_empty() && !self.storage.ends_with('\n') {
            self.storage.push('\n');
        }
    }

    fn finish(self) -> String {
        self.storage.trim().to_string()
    }
}

fn starts_with_closing_punctuation(value: &str) -> bool {
    value.chars().next().is_some_and(|character| {
        matches!(
            character,
            ',' | '.'
                | '!'
                | '?'
                | ':'
                | ';'
                | ')'
                | ']'
                | '}'
                | '，'
                | '。'
                | '！'
                | '？'
                | '：'
                | '；'
                | '）'
                | '】'
                | '》'
        )
    })
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderBlockKind};

    use super::render_document;

    #[test]
    fn render_document_preserves_quote_and_details_semantics() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node_with_attrs(
                    1,
                    Some(0),
                    1,
                    CookedHtmlNodeKind::DiscourseQuote,
                    BTreeMap::from([
                        ("data-username".to_string(), "alice".to_string()),
                        ("data-post".to_string(), "3".to_string()),
                        ("data-topic".to_string(), "99".to_string()),
                    ]),
                ),
                node(2, Some(1), 2, CookedHtmlNodeKind::Blockquote),
                node(3, Some(2), 3, CookedHtmlNodeKind::Paragraph),
                text_node(4, 3, 4, "Hello"),
                node(5, Some(3), 4, CookedHtmlNodeKind::Strong),
                text_node(6, 5, 5, "Fire"),
                node(7, Some(0), 1, CookedHtmlNodeKind::Details),
                text_node(8, 7, 2, "More"),
                node(9, Some(7), 2, CookedHtmlNodeKind::Paragraph),
                text_node(10, 9, 3, "Body"),
            ],
            plain_text: "Hello Fire\n\nMore\n\nBody".to_string(),
            image_urls: Vec::new(),
            link_urls: Vec::new(),
        };

        let rendered = render_document(&document, "https://linux.do");
        assert!(rendered.blocks.iter().any(|block| matches!(
            block.kind,
            RenderBlockKind::Quote {
                author: Some(ref author),
                post_number: Some(3),
                topic_id: Some(99),
            } if author == "alice"
        )));
        assert!(rendered
            .blocks
            .iter()
            .any(|block| block.kind == RenderBlockKind::Details));
        assert!(rendered
            .blocks
            .iter()
            .any(|block| block.kind == RenderBlockKind::DetailsSummary));
    }

    #[test]
    fn render_document_collects_non_emoji_images() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "demo", "480", "320"),
            ],
            plain_text: "demo".to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.image_attachments.len(), 1);
        assert_eq!(
            rendered.image_attachments[0].url,
            "https://linux.do/uploads/full.png"
        );
        assert_eq!(rendered.image_attachments[0].width, Some(480));
        assert_eq!(rendered.image_attachments[0].height, Some(320));
    }

    fn node(
        id: u32,
        parent_id: Option<u32>,
        depth: u32,
        kind: CookedHtmlNodeKind,
    ) -> CookedHtmlNode {
        CookedHtmlNode {
            id,
            parent_id,
            kind,
            depth,
            text: None,
            url: None,
            title: None,
            alt: None,
            level: None,
            ordered: None,
            attributes: BTreeMap::new(),
        }
    }

    fn node_with_attrs(
        id: u32,
        parent_id: Option<u32>,
        depth: u32,
        kind: CookedHtmlNodeKind,
        attributes: BTreeMap<String, String>,
    ) -> CookedHtmlNode {
        CookedHtmlNode {
            attributes,
            ..node(id, parent_id, depth, kind)
        }
    }

    fn text_node(id: u32, parent_id: u32, depth: u32, text: &str) -> CookedHtmlNode {
        CookedHtmlNode {
            text: Some(text.to_string()),
            ..node(id, Some(parent_id), depth, CookedHtmlNodeKind::Text)
        }
    }

    fn link_node(
        id: u32,
        parent_id: u32,
        depth: u32,
        url: &str,
        class_name: &str,
    ) -> CookedHtmlNode {
        CookedHtmlNode {
            url: Some(url.to_string()),
            attributes: BTreeMap::from([("class".to_string(), class_name.to_string())]),
            ..node(id, Some(parent_id), depth, CookedHtmlNodeKind::Link)
        }
    }

    fn image_node(
        id: u32,
        parent_id: u32,
        depth: u32,
        url: &str,
        alt: &str,
        width: &str,
        height: &str,
    ) -> CookedHtmlNode {
        CookedHtmlNode {
            url: Some(url.to_string()),
            alt: Some(alt.to_string()),
            attributes: BTreeMap::from([
                ("width".to_string(), width.to_string()),
                ("height".to_string(), height.to_string()),
            ]),
            ..node(id, Some(parent_id), depth, CookedHtmlNodeKind::Image)
        }
    }
}
