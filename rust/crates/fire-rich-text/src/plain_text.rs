use fire_models::{CookedHtmlNode, CookedHtmlNodeKind, RenderBlockKind};

use crate::map::{
    emoji_fallback_text, is_emoji_node, normalized_attributes, CookedTree, TreeRenderBlock,
};

pub(crate) fn render_plain_text(nodes: &[TreeRenderBlock]) -> String {
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
            source_name,
            ..
        } => {
            builder.ensure_block_boundary();
            for value in [
                source_name.as_deref(),
                title.as_deref(),
                description.as_deref(),
                url.as_deref(),
            ]
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

pub(crate) fn append_subtree_text(
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

pub(crate) fn extract_text_content(
    nodes: &[TreeRenderBlock],
    including_emoji_fallback: bool,
) -> String {
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
                source_name,
                ..
            } => {
                for value in [
                    source_name.as_deref(),
                    title.as_deref(),
                    description.as_deref(),
                    url.as_deref(),
                ]
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

#[derive(Default)]
pub(crate) struct PlainTextBuilder {
    storage: String,
}

impl PlainTextBuilder {
    pub(crate) fn append_inline(&mut self, value: &str) {
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

    pub(crate) fn append_preformatted(&mut self, value: &str) {
        let trimmed = value.trim_matches('\n');
        if trimmed.is_empty() {
            return;
        }
        self.storage.push_str(trimmed);
    }

    pub(crate) fn ensure_line_break(&mut self) {
        while self.storage.ends_with([' ', '\t']) {
            self.storage.pop();
        }
        if !self.storage.is_empty() && !self.storage.ends_with('\n') {
            self.storage.push('\n');
        }
    }

    pub(crate) fn ensure_block_boundary(&mut self) {
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

    pub(crate) fn finish(self) -> String {
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

pub fn plain_text_from_render_document(document: &fire_models::RenderDocument) -> String {
    document.plain_text.clone()
}
