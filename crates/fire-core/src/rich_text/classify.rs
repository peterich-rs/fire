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

