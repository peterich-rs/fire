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

