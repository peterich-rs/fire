use std::collections::BTreeMap;

use ego_tree::NodeRef;
use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind};
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
    if has_class("onebox") || has_class_suffix("-onebox") {
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
    use fire_models::CookedHtmlNodeKind;

    use super::parse_cooked_html;

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
}
