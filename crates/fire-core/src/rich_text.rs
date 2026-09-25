use std::collections::BTreeMap;

use ego_tree::NodeRef;
use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderDocument};
use std::sync::Arc;

use fire_models::{
    AttachedPresentation, ChatMessage, PresentedDocument, TopicPost, TopicPostBoost,
};
use fire_rich_text::{present_owned_document, render_document as shared_render_document};
use html5ever::tendril::TendrilSink;
use html5ever::{local_name, ns, QualName};
use scraper::{ElementRef, Html, HtmlTreeSink, Node as ScraperNode};

pub fn parse_cooked_html(raw_html: &str) -> CookedHtmlDocument {
    let html = parse_fragment(raw_html);
    let mut builder = CookedHtmlBuilder::default();
    let root_id = builder.push_node(None, 0, CookedHtmlNodeKind::Document, NodeMeta::default());

    let root = html.root_element();
    for child in root.children() {
        builder.visit_node(child, root_id, 0, TextMode::Normal);
    }

    builder.finish()
}

pub fn render_cooked_html(raw_html: &str, base_url: &str) -> RenderDocument {
    let document = parse_cooked_html(raw_html);
    shared_render_document(&document, base_url)
}

/// Parse cooked HTML and produce the host display plan.
///
/// Empty input is absence, not an empty presentation. The returned
/// [`PresentedDocument`] keeps the IR for a future handle; callers that only
/// cross UniFFI should lift `into_presentation()`.
pub fn present_cooked_html(raw_html: &str, base_url: &str) -> Option<PresentedDocument> {
    let trimmed = raw_html.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(present_owned_document(render_cooked_html(
            trimmed, base_url,
        )))
    }
}

pub fn attach_post_presentation(post: &mut TopicPost, base_url: &str) {
    if post.presented.get().is_none() {
        post.presented = present_cooked_html(&post.cooked, base_url)
            .map(|document| AttachedPresentation::some(Arc::new(document)))
            .unwrap_or_default();
    }
    for boost in &mut post.boosts {
        attach_boost_presentation(boost, base_url);
    }
}

pub fn attach_boost_presentation(boost: &mut TopicPostBoost, base_url: &str) {
    if boost.presented.get().is_some() {
        return;
    }
    boost.presented = present_cooked_html(&boost.cooked, base_url)
        .map(|document| AttachedPresentation::some(Arc::new(document)))
        .unwrap_or_default();
}

pub fn attach_chat_message_presentation(message: &mut ChatMessage, base_url: &str) {
    if message.presented.get().is_some() {
        return;
    }
    message.presented = present_cooked_html(&message.cooked, base_url)
        .map(|document| AttachedPresentation::some(Arc::new(document)))
        .unwrap_or_default();
}

pub fn attach_posts_presentation(posts: &mut [TopicPost], base_url: &str) {
    for post in posts {
        attach_post_presentation(post, base_url);
    }
}

fn parse_fragment(raw_html: &str) -> Html {
    let parser = html5ever::parse_fragment(
        HtmlTreeSink::new(Html::new_fragment()),
        html5ever::ParseOpts::default(),
        QualName::new(None, ns!(html), local_name!("body")),
        Vec::new(),
        false,
    );
    parser.one(raw_html)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TextMode {
    Normal,
    Preformatted,
}

#[derive(Default)]
struct CookedHtmlBuilder {
    next_id: u32,
    nodes: Vec<CookedHtmlNode>,
    plain_text: String,
    pending_inline_space: bool,
    image_urls: Vec<String>,
    link_urls: Vec<String>,
}

impl CookedHtmlBuilder {
    fn finish(mut self) -> CookedHtmlDocument {
        self.trim_plain_text();
        CookedHtmlDocument {
            nodes: self.nodes,
            plain_text: self.plain_text,
            image_urls: dedupe_preserving_order(self.image_urls),
            link_urls: dedupe_preserving_order(self.link_urls),
        }
    }

    fn visit_node(
        &mut self,
        node: NodeRef<'_, ScraperNode>,
        parent_id: u32,
        depth: u32,
        text_mode: TextMode,
    ) {
        match node.value() {
            ScraperNode::Text(text) => self.push_text_node(&text.text, parent_id, depth, text_mode),
            ScraperNode::Element(_) => {
                if let Some(element) = ElementRef::wrap(node) {
                    self.visit_element(element, parent_id, depth, text_mode);
                }
            }
            _ => {}
        }
    }

    fn visit_element(
        &mut self,
        element: ElementRef<'_>,
        parent_id: u32,
        depth: u32,
        text_mode: TextMode,
    ) {
        let tag = element.value().name();
        if matches!(tag, "script" | "style") {
            return;
        }

        let classes = element.attr("class").unwrap_or_default();
        // Polls are rendered by native Poll UI from structured post.polls.
        // Walking their cooked children leaks option lists + vote labels into body text.
        if is_poll_container(tag, classes) {
            return;
        }
        let kind = node_kind_for_element(tag, classes);
        let next_text_mode = if tag == "pre" {
            TextMode::Preformatted
        } else {
            text_mode
        };

        if tag == "br" {
            let id = self.push_node(
                Some(parent_id),
                depth + 1,
                CookedHtmlNodeKind::LineBreak,
                NodeMeta::from_element(element),
            );
            self.ensure_line_break();
            self.visit_children(element, id, depth + 1, next_text_mode);
            return;
        }

        let starts_block = starts_plain_text_block(kind);
        let ends_block = ends_plain_text_block(kind);
        if starts_block {
            self.ensure_block_boundary();
        }

        let effective_parent_id = if let Some(kind) = kind {
            let mut meta = NodeMeta::from_element(element);
            apply_element_metadata(tag, classes, element, kind, &mut meta);
            if let Some(url) = meta.url.as_ref() {
                match kind {
                    CookedHtmlNodeKind::Image | CookedHtmlNodeKind::Emoji => {
                        self.image_urls.push(url.clone());
                    }
                    CookedHtmlNodeKind::Link
                    | CookedHtmlNodeKind::Mention
                    | CookedHtmlNodeKind::Hashtag
                    | CookedHtmlNodeKind::Attachment
                    | CookedHtmlNodeKind::Onebox
                    | CookedHtmlNodeKind::Iframe => {
                        self.link_urls.push(url.clone());
                    }
                    _ => {}
                }
            }

            let id = self.push_node(Some(parent_id), depth + 1, kind, meta);
            if matches!(kind, CookedHtmlNodeKind::Image | CookedHtmlNodeKind::Emoji) {
                self.append_media_alt_text(element);
            }
            id
        } else {
            parent_id
        };

        self.visit_children(element, effective_parent_id, depth + 1, next_text_mode);

        match kind {
            Some(CookedHtmlNodeKind::ListItem) => self.ensure_line_break(),
            Some(CookedHtmlNodeKind::TableCell) => self.append_plain_separator(" "),
            Some(CookedHtmlNodeKind::TableRow) => self.ensure_line_break(),
            _ if ends_block => self.ensure_block_boundary(),
            _ => {}
        }
    }

    fn visit_children(
        &mut self,
        element: ElementRef<'_>,
        parent_id: u32,
        depth: u32,
        text_mode: TextMode,
    ) {
        for child in element.children() {
            self.visit_node(child, parent_id, depth, text_mode);
        }
    }

    fn push_node(
        &mut self,
        parent_id: Option<u32>,
        depth: u32,
        kind: CookedHtmlNodeKind,
        meta: NodeMeta,
    ) -> u32 {
        let id = self.next_id;
        self.next_id += 1;
        self.nodes.push(CookedHtmlNode {
            id,
            parent_id,
            kind,
            depth,
            text: meta.text,
            url: meta.url,
            title: meta.title,
            alt: meta.alt,
            level: meta.level,
            ordered: meta.ordered,
            attributes: meta.attributes,
        });
        id
    }

    fn push_text_node(&mut self, raw_text: &str, parent_id: u32, depth: u32, text_mode: TextMode) {
        let text = if text_mode == TextMode::Preformatted {
            normalize_preformatted_text(raw_text)
        } else {
            normalize_inline_text(raw_text)
        };
        if text.is_empty() {
            if raw_text.chars().any(char::is_whitespace) {
                self.pending_inline_space = true;
            }
            return;
        }

        let id = self.push_node(
            Some(parent_id),
            depth + 1,
            CookedHtmlNodeKind::Text,
            NodeMeta {
                text: Some(text.clone()),
                ..NodeMeta::default()
            },
        );
        debug_assert!(self.nodes.iter().any(|node| node.id == id));

        if text_mode == TextMode::Preformatted {
            self.append_preformatted_text(&text);
        } else {
            self.append_inline_text(raw_text, &text);
        }
    }

    fn append_media_alt_text(&mut self, element: ElementRef<'_>) {
        let alt = element
            .attr("alt")
            .or_else(|| element.attr("title"))
            .map(str::trim)
            .filter(|value| !value.is_empty());
        if let Some(alt) = alt {
            self.append_inline_text(alt, &normalize_inline_text(alt));
        }
    }

    fn append_inline_text(&mut self, raw_text: &str, text: &str) {
        if text.is_empty() {
            return;
        }

        let had_leading_space = raw_text
            .chars()
            .next()
            .is_some_and(|character| character.is_whitespace() || character == '\u{a0}');
        let had_trailing_space = raw_text
            .chars()
            .last()
            .is_some_and(|character| character.is_whitespace() || character == '\u{a0}');

        if (had_leading_space || self.pending_inline_space)
            && !self.plain_text.is_empty()
            && !self.plain_text.ends_with(char::is_whitespace)
            && !starts_with_closing_punctuation(text)
        {
            self.plain_text.push(' ');
        }

        self.plain_text.push_str(text);
        self.pending_inline_space = had_trailing_space;
    }

    fn append_preformatted_text(&mut self, text: &str) {
        if text.is_empty() {
            return;
        }
        if self.pending_inline_space
            && !self.plain_text.is_empty()
            && !self.plain_text.ends_with(char::is_whitespace)
        {
            self.plain_text.push(' ');
        }
        self.plain_text.push_str(text);
        self.pending_inline_space = false;
    }

    fn append_plain_separator(&mut self, separator: &str) {
        if self.plain_text.is_empty() || self.plain_text.ends_with(char::is_whitespace) {
            return;
        }
        self.plain_text.push_str(separator);
        self.pending_inline_space = false;
    }

    fn ensure_line_break(&mut self) {
        self.trim_plain_text_end();
        if !self.plain_text.is_empty() && !self.plain_text.ends_with('\n') {
            self.plain_text.push('\n');
        }
        self.pending_inline_space = false;
    }

    fn ensure_block_boundary(&mut self) {
        self.trim_plain_text_end();
        if self.plain_text.is_empty() {
            self.pending_inline_space = false;
            return;
        }

        let trailing_newlines = self
            .plain_text
            .chars()
            .rev()
            .take_while(|character| *character == '\n')
            .count();
        for _ in trailing_newlines..2 {
            self.plain_text.push('\n');
        }
        self.pending_inline_space = false;
    }

    fn trim_plain_text_end(&mut self) {
        while self
            .plain_text
            .chars()
            .last()
            .is_some_and(|character| character == ' ' || character == '\t')
        {
            self.plain_text.pop();
        }
    }

    fn trim_plain_text(&mut self) {
        while self
            .plain_text
            .chars()
            .last()
            .is_some_and(char::is_whitespace)
        {
            self.plain_text.pop();
        }
    }
}

#[derive(Default)]
struct NodeMeta {
    text: Option<String>,
    url: Option<String>,
    title: Option<String>,
    alt: Option<String>,
    level: Option<u32>,
    ordered: Option<bool>,
    attributes: BTreeMap<String, String>,
}

impl NodeMeta {
    fn from_element(element: ElementRef<'_>) -> Self {
        let mut attributes = BTreeMap::new();
        for (name, value) in element.value().attrs() {
            attributes.insert(name.to_string(), value.to_string());
        }
        Self {
            title: element.attr("title").map(ToOwned::to_owned),
            alt: element.attr("alt").map(ToOwned::to_owned),
            attributes,
            ..Self::default()
        }
    }
}

fn apply_element_metadata(
    tag: &str,
    classes: &str,
    element: ElementRef<'_>,
    kind: CookedHtmlNodeKind,
    meta: &mut NodeMeta,
) {
    match kind {
        CookedHtmlNodeKind::Heading => {
            meta.level = tag
                .strip_prefix('h')
                .and_then(|value| value.parse::<u32>().ok());
        }
        CookedHtmlNodeKind::List => {
            meta.ordered = Some(tag == "ol");
        }
        CookedHtmlNodeKind::Link
        | CookedHtmlNodeKind::Mention
        | CookedHtmlNodeKind::Hashtag
        | CookedHtmlNodeKind::Attachment => {
            meta.url = element.attr("href").map(ToOwned::to_owned);
        }
        CookedHtmlNodeKind::Image | CookedHtmlNodeKind::Emoji => {
            meta.url = element.attr("src").map(ToOwned::to_owned);
        }
        CookedHtmlNodeKind::Iframe => {
            meta.url = element.attr("src").map(ToOwned::to_owned);
        }
        CookedHtmlNodeKind::Onebox => {
            meta.url = element
                .attr("href")
                .or_else(|| element.attr("data-onebox-src"))
                .or_else(|| element.attr("data-original-href"))
                .map(ToOwned::to_owned);
            if meta.title.is_none() {
                meta.title = first_meaningful_text(element);
            }
        }
        CookedHtmlNodeKind::DiscourseQuote => {
            meta.title = element
                .attr("data-username")
                .or_else(|| element.attr("data-user-card"))
                .map(ToOwned::to_owned)
                .or_else(|| first_meaningful_text(element));
        }
        _ => {}
    }

    if classes
        .split_ascii_whitespace()
        .any(|class| class == "onebox" || class.ends_with("-onebox"))
        && meta.url.is_none()
    {
        meta.url = element
            .attr("href")
            .or_else(|| element.attr("data-onebox-src"))
            .or_else(|| element.attr("data-original-href"))
            .map(ToOwned::to_owned);
    }
}

fn first_meaningful_text(element: ElementRef<'_>) -> Option<String> {
    let text = normalize_inline_text(&element.text().collect::<Vec<_>>().join(" "));
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn node_kind_for_element(tag: &str, classes: &str) -> Option<CookedHtmlNodeKind> {
    let has_class = |target: &str| {
        classes
            .split_ascii_whitespace()
            .any(|class| class == target)
    };
    let has_class_suffix = |suffix: &str| {
        classes
            .split_ascii_whitespace()
            .any(|class| class.ends_with(suffix))
    };

    if has_class("spoiler") || has_class("blur") {
        return Some(CookedHtmlNodeKind::Spoiler);
    }
    // `inline-onebox` is an inline title link, not a preview card. The `-onebox`
    // suffix would otherwise swallow it and drop the surrounding sentence.
    let is_inline_onebox = has_class("inline-onebox") || has_class("inline-onebox-loading");
    if !is_inline_onebox && (has_class("onebox") || has_class_suffix("-onebox")) {
        return Some(CookedHtmlNodeKind::Onebox);
    }
    if has_class("mention") {
        return Some(CookedHtmlNodeKind::Mention);
    }
    if has_class("hashtag") {
        return Some(CookedHtmlNodeKind::Hashtag);
    }
    if has_class("emoji") {
        return Some(CookedHtmlNodeKind::Emoji);
    }
    if has_class("attachment") {
        return Some(CookedHtmlNodeKind::Attachment);
    }

    match tag {
        "p" => Some(CookedHtmlNodeKind::Paragraph),
        "h1" | "h2" | "h3" | "h4" | "h5" | "h6" => Some(CookedHtmlNodeKind::Heading),
        "br" => Some(CookedHtmlNodeKind::LineBreak),
        "strong" | "b" => Some(CookedHtmlNodeKind::Strong),
        "em" | "i" => Some(CookedHtmlNodeKind::Emphasis),
        "s" | "del" | "strike" => Some(CookedHtmlNodeKind::Strikethrough),
        "a" => Some(CookedHtmlNodeKind::Link),
        "img" => Some(CookedHtmlNodeKind::Image),
        "code" => Some(CookedHtmlNodeKind::Code),
        "pre" => Some(CookedHtmlNodeKind::CodeBlock),
        "blockquote" => Some(CookedHtmlNodeKind::Blockquote),
        "aside" if has_class("quote") => Some(CookedHtmlNodeKind::DiscourseQuote),
        "aside" => Some(CookedHtmlNodeKind::Onebox),
        "hr" => Some(CookedHtmlNodeKind::Divider),
        "ul" | "ol" => Some(CookedHtmlNodeKind::List),
        "li" => Some(CookedHtmlNodeKind::ListItem),
        "details" => Some(CookedHtmlNodeKind::Details),
        "table" => Some(CookedHtmlNodeKind::Table),
        "tr" => Some(CookedHtmlNodeKind::TableRow),
        "td" | "th" => Some(CookedHtmlNodeKind::TableCell),
        "iframe" | "video" => Some(CookedHtmlNodeKind::Iframe),
        _ => None,
    }
}

fn is_poll_container(tag: &str, classes: &str) -> bool {
    let has_class = |target: &str| {
        classes
            .split_whitespace()
            .any(|class| class.eq_ignore_ascii_case(target))
    };
    // Discourse poll markup variants seen in the wild.
    has_class("poll")
        || has_class("poll-container")
        || has_class("poll-area")
        || (tag.eq_ignore_ascii_case("div") && has_class("polls"))
}

fn starts_plain_text_block(kind: Option<CookedHtmlNodeKind>) -> bool {
    matches!(
        kind,
        Some(
            CookedHtmlNodeKind::Paragraph
                | CookedHtmlNodeKind::Heading
                | CookedHtmlNodeKind::Blockquote
                | CookedHtmlNodeKind::DiscourseQuote
                | CookedHtmlNodeKind::List
                | CookedHtmlNodeKind::CodeBlock
                | CookedHtmlNodeKind::Details
                | CookedHtmlNodeKind::Table
                | CookedHtmlNodeKind::Onebox
        )
    )
}

fn ends_plain_text_block(kind: Option<CookedHtmlNodeKind>) -> bool {
    starts_plain_text_block(kind)
}

fn normalize_inline_text(raw: &str) -> String {
    raw.replace('\u{a0}', " ")
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn normalize_preformatted_text(raw: &str) -> String {
    raw.replace("\r\n", "\n").replace('\u{a0}', " ")
}

fn starts_with_closing_punctuation(text: &str) -> bool {
    text.chars().next().is_some_and(|character| {
        matches!(
            character,
            '.' | ',' | ';' | ':' | '!' | '?' | ')' | ']' | '}'
        )
    })
}

fn dedupe_preserving_order(values: Vec<String>) -> Vec<String> {
    let mut result = Vec::new();
    for value in values {
        if value.trim().is_empty() || result.contains(&value) {
            continue;
        }
        result.push(value);
    }
    result
}

#[cfg(test)]
mod tests {
    use fire_models::{CookedHtmlNodeKind, TopicPost};

    use super::{
        attach_post_presentation, parse_cooked_html, present_cooked_html, render_cooked_html,
    };

    #[test]
    fn parses_common_discourse_cooked_html_into_nodes() {
        let document = parse_cooked_html(
            r#"
            <p>Hello <strong>Fire</strong><br><a href="/t/123/4">topic</a></p>
            <p><img src="/uploads/default/original/1X/fire.png" alt="diagram"></p>
            <ul><li>Rust</li><li>Android</li></ul>
            "#,
        );

        assert_eq!(
            document.plain_text,
            "Hello Fire\ntopic\n\ndiagram\n\nRust\nAndroid"
        );
        assert_eq!(
            document.image_urls,
            vec!["/uploads/default/original/1X/fire.png".to_string()]
        );
        assert_eq!(document.link_urls, vec!["/t/123/4".to_string()]);
        assert!(document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKind::Strong));
        assert!(document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKind::ListItem));
    }

    #[test]
    fn skips_poll_container_markup_so_native_poll_ui_is_not_duplicated() {
        let document = parse_cooked_html(
            r#"
            <p>开个贴看看</p>
            <div class="poll" data-poll-name="poll">
              <ul>
                <li data-poll-option-id="1">0-10</li>
                <li data-poll-option-id="2">11-20</li>
                <li data-poll-option-id="7">61以上</li>
              </ul>
              <div class="poll-info">1175 投票人</div>
            </div>
            <p>补充说明</p>
            "#,
        );

        assert_eq!(document.plain_text, "开个贴看看\n\n补充说明");
        assert!(!document.plain_text.contains("0-10"));
        assert!(!document.plain_text.contains("投票人"));
        assert!(!document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKind::ListItem));
    }

    #[test]
    fn parses_discourse_quote_details_table_and_onebox_metadata() {
        let document = parse_cooked_html(
            r#"
            <aside class="quote" data-username="alice" data-post="2">
              <blockquote><p>quoted text</p></blockquote>
            </aside>
            <details><summary>More</summary><p>hidden text</p></details>
            <table><tr><th>A</th><td>B</td></tr></table>
            <aside class="onebox" data-onebox-src="https://example.com/card"><h3>Card</h3></aside>
            "#,
        );

        let quote = document
            .nodes
            .iter()
            .find(|node| node.kind == CookedHtmlNodeKind::DiscourseQuote)
            .expect("quote node");
        assert_eq!(quote.title.as_deref(), Some("alice"));
        assert_eq!(
            quote.attributes.get("data-post").map(String::as_str),
            Some("2")
        );
        assert!(document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKind::Details));
        assert!(document
            .nodes
            .iter()
            .any(|node| node.kind == CookedHtmlNodeKind::TableCell));
        assert!(document.nodes.iter().any(|node| {
            node.kind == CookedHtmlNodeKind::Onebox
                && node.url.as_deref() == Some("https://example.com/card")
        }));
    }

    #[test]
    fn inline_onebox_stays_a_link_and_block_onebox_keeps_chrome_out_of_images() {
        let rendered = render_cooked_html(
            r#"
            <aside class="onebox allowlistedgeneric" data-onebox-src="https://www.bilibili.com/video/BV1">
              <header class="source">
                <img src="https://www.bilibili.com/favicon.ico" class="site-icon" alt="">
                <a href="https://www.bilibili.com/video/BV1" target="_blank" rel="noopener">bilibili.com</a>
              </header>
              <article class="onebox-body">
                <img width="480" height="270" src="https://i0.hdslb.com/bfs/archive/cover.jpg" class="thumbnail" alt="">
                <h3><a href="https://www.bilibili.com/video/BV1">开源神器</a></h3>
                <p>番茄钟说明</p>
              </article>
            </aside>
            <p>后文 <a href="https://github.com/topics/clock" class="inline-onebox">GitHub Topics Clock</a></p>
            "#,
            "https://linux.do",
        );

        assert!(rendered.image_attachments.is_empty());
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            fire_models::RenderBlockKind::Onebox {
                source_name: Some(source_name),
                icon_url: Some(icon_url),
                thumbnail_url: Some(thumbnail_url),
                title: Some(title),
                ..
            } if source_name == "bilibili.com"
                && icon_url == "https://www.bilibili.com/favicon.ico"
                && thumbnail_url == "https://i0.hdslb.com/bfs/archive/cover.jpg"
                && title == "开源神器"
        )));
        assert!(rendered.blocks.iter().any(|block| matches!(
            &block.kind,
            fire_models::RenderBlockKind::Link { url } if url == "https://github.com/topics/clock"
        )));
        assert_eq!(
            rendered
                .blocks
                .iter()
                .filter(|block| matches!(block.kind, fire_models::RenderBlockKind::Onebox { .. }))
                .count(),
            1
        );
        let segments = fire_rich_text::display_segments(&rendered);
        assert!(segments
            .iter()
            .all(|segment| !matches!(segment, fire_models::RenderUiSegment::Image(_))));
    }

    #[test]
    fn present_cooked_html_skips_blank_input_and_keeps_ui_plan() {
        assert!(present_cooked_html("   ", "https://linux.do").is_none());

        let presented = present_cooked_html("<p>Hello Fire</p>", "https://linux.do")
            .expect("non-empty cooked html should present");
        assert_eq!(presented.presentation().plain_text, "Hello Fire");
        assert!(!presented.presentation().segments.is_empty());
    }

    #[test]
    fn attach_post_presentation_reuses_arc_when_cooked_is_unchanged() {
        let mut first = TopicPost {
            cooked: "<p>Hello Fire</p>".to_string(),
            ..TopicPost::default()
        };
        attach_post_presentation(&mut first, "https://linux.do");
        let original = first.presented.arc().expect("presented");

        let mut second = first.clone();
        second.like_count = 4;
        second.reuse_presentation_from(&first);
        let reused = second.presented.arc().expect("reused");
        assert!(std::sync::Arc::ptr_eq(&original, &reused));
    }
}
