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

    let plain_text = render_plain_text(&root_block.children);

    RenderDocument {
        blocks: flatten_tree(&root_block),
        plain_text,
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

fn render_plain_text(nodes: &[TreeRenderBlock]) -> String {
    let mut builder = PlainTextBuilder::default();
    append_render_plain_text(nodes, &mut builder);
    builder.finish()
}

fn append_render_plain_text(nodes: &[TreeRenderBlock], builder: &mut PlainTextBuilder) {
    for node in nodes {
        append_render_block_plain_text(node, builder);
    }
}

fn append_render_block_plain_text(node: &TreeRenderBlock, builder: &mut PlainTextBuilder) {
    match &node.kind {
        RenderBlockKind::Text { content } => builder.append_inline(content),
        RenderBlockKind::InlineCode { code } => builder.append_inline(code),
        RenderBlockKind::CodeBlock { code, .. } | RenderBlockKind::Table { text: code } => {
            builder.ensure_block_boundary();
            builder.append_preformatted(code);
            builder.ensure_block_boundary();
        }
        RenderBlockKind::Mention { username } => builder.append_inline(&format!("@{username}")),
        RenderBlockKind::MentionGroup { name, .. } => builder.append_inline(&format!("@{name}")),
        RenderBlockKind::Hashtag { text, .. } => builder.append_inline(&format!("#{text}")),
        RenderBlockKind::Emoji { fallback_text, .. } => builder.append_inline(fallback_text),
        RenderBlockKind::Image { alt, .. } => {
            if let Some(alt) = alt {
                builder.ensure_block_boundary();
                builder.append_inline(alt);
                builder.ensure_block_boundary();
            }
        }
        RenderBlockKind::Onebox {
            title,
            description,
            url,
        } => {
            builder.ensure_block_boundary();
            for value in [title.as_deref(), description.as_deref(), url.as_deref()]
                .into_iter()
                .flatten()
            {
                builder.append_inline(value);
                builder.ensure_line_break();
            }
            builder.ensure_block_boundary();
        }
        RenderBlockKind::Video { title, url } => {
            builder.append_inline(title.as_deref().unwrap_or(url));
        }
        RenderBlockKind::Paragraph
        | RenderBlockKind::Heading { .. }
        | RenderBlockKind::Blockquote
        | RenderBlockKind::Quote { .. }
        | RenderBlockKind::Details => {
            builder.ensure_block_boundary();
            append_render_plain_text(&node.children, builder);
            builder.ensure_block_boundary();
        }
        RenderBlockKind::List { ordered } => {
            builder.ensure_block_boundary();
            for (index, child) in node.children.iter().enumerate() {
                if *ordered {
                    builder.append_inline(&format!("{}.", index + 1));
                } else {
                    builder.append_inline("-");
                }
                append_render_block_plain_text(child, builder);
                builder.ensure_line_break();
            }
            builder.ensure_block_boundary();
        }
        RenderBlockKind::ListItem
        | RenderBlockKind::Bold
        | RenderBlockKind::Italic
        | RenderBlockKind::Strikethrough
        | RenderBlockKind::Link { .. }
        | RenderBlockKind::Spoiler
        | RenderBlockKind::DetailsSummary
        | RenderBlockKind::Document
        | RenderBlockKind::Unknown => {
            append_render_plain_text(&node.children, builder);
        }
        RenderBlockKind::Divider | RenderBlockKind::LineBreak => builder.ensure_line_break(),
    }
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
            .and_then(|content| cleaned_text_node_content(node, content, tree))
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
            let (title, description) = onebox_title_and_description(node, tree);
            vec![TreeRenderBlock {
                kind: RenderBlockKind::Onebox {
                    url: resolved_url_string(node.url.as_deref(), base_url),
                    title,
                    description,
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

fn onebox_title_and_description(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
) -> (Option<String>, Option<String>) {
    let title = first_descendant_text(node, tree, CookedHtmlNodeKind::Heading)
        .or_else(|| normalized_text(node.title.as_deref()))
        .or_else(|| first_descendant_text(node, tree, CookedHtmlNodeKind::Link))
        .or_else(|| normalized_text(Some(&subtree_text(node, tree))));
    let description =
        first_descendant_text(node, tree, CookedHtmlNodeKind::Paragraph).filter(|description| {
            let title = title.as_deref().unwrap_or_default();
            !description.eq_ignore_ascii_case(title)
                && !node
                    .url
                    .as_deref()
                    .is_some_and(|url| description.eq_ignore_ascii_case(url))
        });
    (title, description)
}

fn first_descendant_text(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
    kind: CookedHtmlNodeKind,
) -> Option<String> {
    for child in tree.children_of(node) {
        if child.kind == kind {
            let text = subtree_text(child, tree);
            if let Some(text) = normalized_text(Some(&text)) {
                return Some(text);
            }
        }
        if let Some(text) = first_descendant_text(child, tree, kind) {
            return Some(text);
        }
    }
    None
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
        .flat_map(remove_quote_chrome)
        .filter(is_meaningful_render_block)
        .collect::<Vec<_>>();
    let quoted_body = meaningful
        .iter()
        .filter_map(|child| {
            (child.kind == RenderBlockKind::Blockquote).then(|| child.children.clone())
        })
        .flatten()
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

fn cleaned_text_node_content(
    node: &CookedHtmlNode,
    content: String,
    tree: &CookedTree<'_>,
) -> Option<String> {
    if !has_imageish_sibling(node, tree) {
        return Some(content);
    }
    if belongs_to_split_image_attachment_metadata(node, tree) {
        return None;
    }
    if let Some(stripped) = strip_trailing_image_attachment_metadata(&content) {
        return normalized_text(Some(&stripped));
    }
    Some(content)
}

fn has_imageish_sibling(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> bool {
    let Some(parent) = tree.node(node.parent_id) else {
        return false;
    };
    tree.children_of(parent)
        .into_iter()
        .filter(|sibling| sibling.id != node.id)
        .any(|sibling| subtree_contains_inline_image(sibling, tree))
}

fn belongs_to_split_image_attachment_metadata(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
) -> bool {
    let Some(parent) = tree.node(node.parent_id) else {
        return false;
    };
    let siblings = tree.children_of(parent);
    let Some(index) = siblings.iter().position(|sibling| sibling.id == node.id) else {
        return false;
    };

    let mut start = index;
    while start > 0 && siblings[start - 1].kind == CookedHtmlNodeKind::Text {
        start -= 1;
    }

    let mut end = index + 1;
    while end < siblings.len() && siblings[end].kind == CookedHtmlNodeKind::Text {
        end += 1;
    }

    if end - start <= 1 {
        return false;
    }

    let text_run = siblings[start..end]
        .iter()
        .filter_map(|sibling| {
            normalized_text(sibling.text.as_deref()).map(|content| (sibling.id, content))
        })
        .collect::<Vec<_>>();
    let Some(run_index) = text_run
        .iter()
        .position(|(sibling_id, _)| *sibling_id == node.id)
    else {
        return false;
    };

    split_image_attachment_metadata_range(&text_run)
        .is_some_and(|(start, end)| (start..end).contains(&run_index))
}

fn strip_trailing_image_attachment_metadata(value: &str) -> Option<String> {
    let trimmed_end = value.trim_end();
    if trimmed_end.is_empty() {
        return None;
    }
    let size_start = trailing_file_size_start(trimmed_end)?;
    let before_size = trimmed_end[..size_start].trim_end();
    let dimension_token_start = trailing_dimension_token_start(before_size)?;
    let metadata_start = immediate_prefix_token_start(&before_size[..dimension_token_start])
        .unwrap_or(dimension_token_start);
    Some(trimmed_end[..metadata_start].trim_end().to_string())
}

fn trailing_file_size_start(value: &str) -> Option<usize> {
    let normalized = value.to_ascii_lowercase();
    let unit = ["kib", "mib", "gib", "kb", "mb", "gb", "b"]
        .into_iter()
        .find(|unit| normalized.ends_with(unit))?;
    let unit_start = value.len() - unit.len();
    let number_end = value[..unit_start].trim_end().len();
    if number_end == 0 {
        return None;
    }

    let mut number_start = number_end;
    for (index, character) in value[..number_end].char_indices().rev() {
        if character.is_ascii_digit() || character == '.' {
            number_start = index;
        } else {
            break;
        }
    }
    let number = &value[number_start..number_end];
    if number.is_empty()
        || number == "."
        || number.parse::<f32>().ok().is_none()
        || !number.chars().any(|character| character.is_ascii_digit())
    {
        return None;
    }
    Some(number_start)
}

fn trailing_dimension_token_start(value: &str) -> Option<usize> {
    let trimmed = value.trim_end_matches(|character: char| {
        character.is_whitespace() || matches!(character, '_' | '-' | '.')
    });
    if trimmed.is_empty() {
        return None;
    }

    for (x_index, x_character) in trimmed.char_indices().rev() {
        if !matches!(x_character, 'x' | 'X' | '×') {
            continue;
        }
        let tail = &trimmed[x_index + x_character.len_utf8()..];
        let Some(height_end) = tail
            .char_indices()
            .take_while(|(_, character)| character.is_ascii_digit())
            .last()
            .map(|(index, character)| index + character.len_utf8())
        else {
            continue;
        };
        if height_end != tail.len() {
            continue;
        }
        let Ok(height) = tail[..height_end].parse::<u32>() else {
            continue;
        };

        let before_x = &trimmed[..x_index];
        let Some((width_start, width)) = trailing_number_start(before_x) else {
            continue;
        };
        if width == 0 || height == 0 || width > 50_000 || height > 50_000 {
            continue;
        }
        return Some(token_start_before(width_start, trimmed));
    }
    None
}

fn trailing_number_start(value: &str) -> Option<(usize, u32)> {
    let mut start = value.len();
    for (index, character) in value.char_indices().rev() {
        if character.is_ascii_digit() {
            start = index;
        } else {
            break;
        }
    }
    if start == value.len() {
        return None;
    }
    value[start..]
        .parse::<u32>()
        .ok()
        .map(|number| (start, number))
}

fn token_start_before(index: usize, value: &str) -> usize {
    value[..index]
        .char_indices()
        .rev()
        .find(|(_, character)| character.is_whitespace())
        .map(|(index, character)| index + character.len_utf8())
        .unwrap_or(0)
}

fn immediate_prefix_token_start(value: &str) -> Option<usize> {
    let trimmed = value.trim_end();
    if trimmed.is_empty() {
        return None;
    }
    Some(
        trimmed
            .char_indices()
            .rev()
            .find(|(_, character)| character.is_whitespace())
            .map(|(index, character)| index + character.len_utf8())
            .unwrap_or(0),
    )
}

fn split_image_attachment_metadata_range(text_run: &[(u32, String)]) -> Option<(usize, usize)> {
    for start in (0..text_run.len()).rev() {
        for end in start + 1..=text_run.len() {
            let combined = text_run[start..end]
                .iter()
                .map(|(_, content)| content.as_str())
                .collect::<Vec<_>>()
                .join(" ");
            if !looks_like_image_attachment_metadata(&combined) {
                continue;
            }
            if start > 0 {
                let expanded = text_run[start - 1..end]
                    .iter()
                    .map(|(_, content)| content.as_str())
                    .collect::<Vec<_>>()
                    .join(" ");
                if looks_like_image_attachment_metadata(&expanded) {
                    return Some((start - 1, end));
                }
            }
            return Some((start, end));
        }
    }
    None
}

fn subtree_contains_inline_image(node: &CookedHtmlNode, tree: &CookedTree<'_>) -> bool {
    if node.kind == CookedHtmlNodeKind::Image && !is_emoji_node(node) {
        return true;
    }
    if matches!(
        node.kind,
        CookedHtmlNodeKind::Link | CookedHtmlNodeKind::Attachment
    ) && node
        .url
        .as_deref()
        .is_some_and(|url| is_image_url(url) || url.contains("/uploads/"))
    {
        return true;
    }
    tree.children_of(node)
        .into_iter()
        .any(|child| subtree_contains_inline_image(child, tree))
}

fn looks_like_image_attachment_metadata(value: &str) -> bool {
    let normalized = value
        .replace('\u{00A0}', " ")
        .replace('×', "x")
        .to_ascii_lowercase()
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || character == '.' {
                character
            } else {
                ' '
            }
        })
        .collect::<String>();
    let tokens = normalized.split_whitespace().collect::<Vec<_>>();

    tokens.iter().enumerate().any(|(index, token)| {
        let Some((after_dimensions, width, height)) = parse_image_dimensions_segment(token) else {
            return false;
        };
        if width == 0 || height == 0 || width > 50_000 || height > 50_000 {
            return false;
        }
        let suffix = std::iter::once(after_dimensions)
            .chain(tokens[index + 1..].iter().copied())
            .collect::<String>();
        parse_file_size_suffix(&suffix)
    })
}

fn parse_image_dimensions_segment(value: &str) -> Option<(&str, u32, u32)> {
    for (x_index, _) in value.match_indices('x') {
        let before = &value[..x_index];
        let width_start = before
            .char_indices()
            .rev()
            .find(|(_, character)| !character.is_ascii_digit())
            .map(|(index, character)| index + character.len_utf8())
            .unwrap_or(0);
        if width_start == x_index {
            continue;
        }
        let Ok(width) = before[width_start..].parse::<u32>() else {
            continue;
        };
        let tail = &value[x_index + 1..];
        let height_digits = tail
            .char_indices()
            .take_while(|(_, character)| character.is_ascii_digit())
            .last()
            .map(|(index, character)| index + character.len_utf8());
        let Some(height_digits) = height_digits else {
            continue;
        };
        let Ok(height) = tail[..height_digits].parse::<u32>() else {
            continue;
        };
        return Some((&tail[height_digits..], width, height));
    }
    None
}

fn parse_file_size_suffix(value: &str) -> bool {
    let number_end = value
        .char_indices()
        .take_while(|(_, character)| character.is_ascii_digit() || *character == '.')
        .last()
        .map(|(index, character)| index + character.len_utf8());
    let Some(number_end) = number_end else {
        return false;
    };
    let number = &value[..number_end];
    if number.is_empty() || number == "." || number.parse::<f32>().ok().is_none() {
        return false;
    }
    matches!(
        &value[number_end..],
        "b" | "kb" | "kib" | "mb" | "mib" | "gb" | "gib"
    )
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

fn should_skip_render_image(
    node: &CookedHtmlNode,
    source_url: &str,
    attrs: &BTreeMap<String, String>,
    tree: &CookedTree<'_>,
) -> bool {
    let classes = class_names(attrs.get("class").map(String::as_str));
    tree.nearest_ancestor(node, |ancestor| {
        ancestor.kind == CookedHtmlNodeKind::DiscourseQuote
    })
    .is_some()
        && (classes.contains("quote-avatar")
            || classes.contains("avatar")
            || classes.contains("user-avatar")
            || is_avatar_url(source_url))
}

fn is_avatar_url(value: &str) -> bool {
    let normalized_path = Url::parse(value)
        .ok()
        .map(|parsed| parsed.path().to_ascii_lowercase())
        .unwrap_or_else(|| value.to_ascii_lowercase());
    normalized_path.contains("/user_avatar/") || normalized_path.contains("/letter_avatar/")
}

fn is_profile_url(value: &str) -> bool {
    Url::parse(value)
        .ok()
        .map(|url| url.path().starts_with("/u/"))
        .unwrap_or_else(|| value.starts_with("/u/") || value.starts_with("fire://profile/"))
}

fn is_quote_title_separator(value: &str) -> bool {
    matches!(value.trim(), ":" | "：")
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

    fn append_preformatted(&mut self, value: &str) {
        let trimmed = value.trim_matches('\n');
        if trimmed.is_empty() {
            return;
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

    fn ensure_block_boundary(&mut self) {
        while self.storage.ends_with([' ', '\t']) {
            self.storage.pop();
        }
        if self.storage.is_empty() {
            return;
        }
        let trailing_newlines = self
            .storage
            .chars()
            .rev()
            .take_while(|character| *character == '\n')
            .count();
        for _ in trailing_newlines..2 {
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

    use super::*;

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

    #[test]
    fn render_document_suppresses_inline_image_metadata_text() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "", "1080", "1920"),
                text_node(4, 1, 2, "image 1080x1920 52.5kb"),
                text_node(5, 1, 2, "screen-shot 1080x1920 34kb"),
                text_node(6, 1, 2, "a1b2c3_690x388_11kb"),
                text_node(7, 1, 2, "caption"),
            ],
            plain_text:
                "image 1080x1920 52.5kb screen-shot 1080x1920 34kb a1b2c3_690x388_11kb caption"
                    .to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "caption");
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("1080x1920")
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("34kb")
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("a1b2c3")
        )));
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "caption"
        )));
    }

    #[test]
    fn render_document_suppresses_split_inline_image_metadata_text() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "", "1080", "1920"),
                text_node(4, 1, 2, "image"),
                text_node(5, 1, 2, "1080x1920 52.5kb"),
                text_node(6, 1, 2, "caption"),
            ],
            plain_text: "image 1080x1920 52.5kb caption".to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "caption");
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "image"
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("1080x1920")
        )));
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "caption"
        )));
    }

    #[test]
    fn render_document_keeps_text_before_split_image_metadata() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "", "1080", "1920"),
                text_node(4, 1, 2, "caption"),
                text_node(5, 1, 2, "image"),
                text_node(6, 1, 2, "1080x1920 52.5kb"),
            ],
            plain_text: "caption image 1080x1920 52.5kb".to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "caption");
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "caption"
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "image"
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("1080x1920")
        )));
    }

    #[test]
    fn render_document_strips_trailing_image_metadata_line_without_dropping_body_text() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "", "1080", "1920"),
                text_node(4, 1, 2, "body text\nscreen-shot 1080x1920 52.5kb"),
            ],
            plain_text: "body text\nscreen-shot 1080x1920 52.5kb".to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "body text");
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "body text"
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("1080x1920")
        )));
    }

    #[test]
    fn render_document_strips_trailing_image_metadata_suffix_without_dropping_body_text() {
        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
                link_node(2, 1, 2, "/uploads/full.png", "lightbox"),
                image_node(3, 2, 3, "/uploads/thumb.png", "", "1080", "1920"),
                text_node(4, 1, 2, "body text screen-shot 1080x1920 52.5kb"),
            ],
            plain_text: "body text screen-shot 1080x1920 52.5kb".to_string(),
            image_urls: vec!["/uploads/thumb.png".to_string()],
            link_urls: vec!["/uploads/full.png".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "body text");
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content == "body text"
        )));
        assert!(!rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Text { content } if content.contains("screen-shot")
        )));
    }

    #[test]
    fn image_metadata_detection_allows_unknown_prefixes_but_not_captions() {
        assert!(looks_like_image_attachment_metadata(
            "screen-shot 1080x1920 34kb"
        ));
        assert!(looks_like_image_attachment_metadata("a1b2c3_690x388_11kb"));
        assert!(looks_like_image_attachment_metadata("hash1080x1920 34kb"));
        assert!(looks_like_image_attachment_metadata("截图 1080×1920 34 KB"));

        assert!(!looks_like_image_attachment_metadata(
            "screen-shot 1080x1920 34kb actual caption"
        ));
        assert!(!looks_like_image_attachment_metadata("bug 1080x1920"));
        assert!(!looks_like_image_attachment_metadata(
            "1080x1920 screenshot only"
        ));
    }

    #[test]
    fn render_document_strips_quote_avatar_and_title_chrome() {
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
                        ("data-post".to_string(), "12".to_string()),
                    ]),
                ),
                node(2, Some(1), 2, CookedHtmlNodeKind::Paragraph),
                image_node_with_attrs(
                    3,
                    2,
                    3,
                    "/user_avatar/linux.do/alice/48/1_2.png",
                    "avatar",
                    "24",
                    "24",
                    BTreeMap::from([("class".to_string(), "avatar quote-avatar".to_string())]),
                ),
                image_node_with_attrs(
                    4,
                    2,
                    3,
                    "https://cdn.example.com/avatar/alice.png",
                    "avatar",
                    "24",
                    "24",
                    BTreeMap::from([("class".to_string(), "avatar".to_string())]),
                ),
                link_node(5, 2, 3, "/u/alice", ""),
                text_node(6, 5, 4, "alice"),
                text_node(7, 2, 3, ":"),
                node(8, Some(1), 2, CookedHtmlNodeKind::Blockquote),
                node(9, Some(8), 3, CookedHtmlNodeKind::Paragraph),
                text_node(10, 9, 4, "Hello Fire"),
            ],
            plain_text: "alice:\n\nHello Fire".to_string(),
            image_urls: vec![
                "/user_avatar/linux.do/alice/48/1_2.png".to_string(),
                "https://cdn.example.com/avatar/alice.png".to_string(),
            ],
            link_urls: vec!["/u/alice".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert_eq!(rendered.plain_text, "Hello Fire");
        let rendered_text = rendered
            .blocks
            .iter()
            .filter_map(|block| match &block.kind {
                RenderBlockKind::Text { content } => Some(content.as_str()),
                _ => None,
            })
            .collect::<Vec<_>>()
            .join(" ");
        assert!(!rendered
            .blocks
            .iter()
            .any(|block| matches!(block.kind, RenderBlockKind::Image { .. })));
        assert_eq!(rendered.image_attachments.len(), 0);
        assert_eq!(rendered_text, "Hello Fire");
    }

    #[test]
    fn render_document_extracts_onebox_title_and_description() {
        let mut onebox = node(1, Some(0), 1, CookedHtmlNodeKind::Onebox);
        onebox.url = Some("https://example.com/post".to_string());
        onebox.title = Some("example.com Example title Example description".to_string());
        let mut heading = node(2, Some(1), 2, CookedHtmlNodeKind::Heading);
        heading.level = Some(3);

        let document = CookedHtmlDocument {
            nodes: vec![
                node(0, None, 0, CookedHtmlNodeKind::Document),
                onebox,
                heading,
                link_node(3, 2, 3, "https://example.com/post", ""),
                text_node(4, 3, 4, "Example title"),
                node(5, Some(1), 2, CookedHtmlNodeKind::Paragraph),
                text_node(6, 5, 3, "Example description"),
            ],
            plain_text: "example.com Example title Example description".to_string(),
            image_urls: Vec::new(),
            link_urls: vec!["https://example.com/post".to_string()],
        };

        let rendered = render_document(&document, "https://linux.do");
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            RenderBlockKind::Onebox {
                url: Some(url),
                title: Some(title),
                description: Some(description),
            } if url == "https://example.com/post"
                && title == "Example title"
                && description == "Example description"
        )));
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

    fn image_node_with_attrs(
        id: u32,
        parent_id: u32,
        depth: u32,
        url: &str,
        alt: &str,
        width: &str,
        height: &str,
        mut attributes: BTreeMap<String, String>,
    ) -> CookedHtmlNode {
        attributes.insert("width".to_string(), width.to_string());
        attributes.insert("height".to_string(), height.to_string());
        CookedHtmlNode {
            url: Some(url.to_string()),
            alt: Some(alt.to_string()),
            attributes,
            ..node(id, Some(parent_id), depth, CookedHtmlNodeKind::Image)
        }
    }
}
