use fire_models::RenderBlockKind;

/// Split leftover Discourse `:shortcode:` text into Text / Emoji kinds.
///
/// Official cooked HTML already has `<img class="emoji">`. Quote excerpts and
/// some plugin-cooked fragments still leave the shortcode in a text node.
/// Standard URLs follow Discourse `buildEmojiUrl`:
/// `/images/emoji/twitter/{name}.png` or `/images/emoji/twitter/{name}/t{n}.png`.
pub(crate) fn kinds_from_text_with_shortcodes(
    content: String,
    base_url: &str,
) -> Vec<RenderBlockKind> {
    let mut kinds = Vec::new();
    let mut cursor = 0;
    let mut emitted = 0;

    while let Some(relative) = content[cursor..].find(':') {
        let start = cursor + relative;
        if let Some((end, name)) = shortcode_at(&content, start) {
            if let Some(url) = standard_emoji_url(base_url, &name) {
                push_text(&mut kinds, &content[emitted..start]);
                kinds.push(RenderBlockKind::Emoji {
                    url,
                    fallback_text: format!(":{name}:"),
                    only_emoji: false,
                });
                emitted = end;
                cursor = end;
                continue;
            }
        }
        cursor = start + 1;
    }

    push_text(&mut kinds, &content[emitted..]);

    if kinds.is_empty() {
        return vec![RenderBlockKind::Text { content }];
    }

    if kinds
        .iter()
        .all(|kind| matches!(kind, RenderBlockKind::Emoji { .. }))
    {
        for kind in &mut kinds {
            if let RenderBlockKind::Emoji { only_emoji, .. } = kind {
                *only_emoji = true;
            }
        }
    }

    kinds
}

fn shortcode_at(content: &str, start: usize) -> Option<(usize, String)> {
    if !content[start..].starts_with(':') {
        return None;
    }

    let after_open = start + 1;
    let rest = &content[after_open..];
    let mut name_len = 0;
    for character in rest.chars() {
        if !is_shortcode_name_character(character) {
            break;
        }
        name_len += character.len_utf8();
    }
    if name_len == 0 {
        return None;
    }

    let mut name = rest[..name_len].to_string();
    let mut consumed = name_len;
    let after_name = &rest[name_len..];
    if let Some(tone) = skin_tone_suffix(after_name) {
        name.push_str(":t");
        name.push(tone);
        consumed += ":t".len() + tone.len_utf8();
    }

    let base_name = name
        .split_once(":t")
        .map_or(name.as_str(), |(base, _)| base);
    if !rest[consumed..].starts_with(':') || !is_shortcode_base_name(base_name) {
        return None;
    }
    Some((after_open + consumed + 1, name))
}

fn skin_tone_suffix(after_name: &str) -> Option<char> {
    let tail = after_name.strip_prefix(":t")?;
    let digit = tail.chars().next()?;
    ('1'..='6').contains(&digit).then_some(digit)
}

fn is_shortcode_name_character(character: char) -> bool {
    character.is_ascii_alphanumeric() || matches!(character, '_' | '+' | '-')
}

fn is_shortcode_base_name(name: &str) -> bool {
    if matches!(name, "+1" | "-1" | "100") {
        return true;
    }
    let mut chars = name.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    first.is_ascii_alphabetic()
        && chars
            .all(|character| character.is_ascii_alphanumeric() || matches!(character, '_' | '-'))
}

fn standard_emoji_url(base_url: &str, name: &str) -> Option<String> {
    let path = if let Some((base, tone)) = name.split_once(":t") {
        if !matches!(tone, "1" | "2" | "3" | "4" | "5" | "6") {
            return None;
        }
        format!("/images/emoji/twitter/{base}/t{tone}.png?v=12")
    } else {
        format!("/images/emoji/twitter/{name}.png?v=12")
    };
    crate::resolved_url_string(Some(&path), base_url)
}

fn push_text(kinds: &mut Vec<RenderBlockKind>, content: &str) {
    if content.is_empty() {
        return;
    }
    kinds.push(RenderBlockKind::Text {
        content: content.to_string(),
    });
}

#[cfg(test)]
mod tests {
    use fire_models::RenderBlockKind;

    use super::kinds_from_text_with_shortcodes;

    #[test]
    fn splits_waving_hand_shortcode_from_adjacent_text() {
        let kinds = kinds_from_text_with_shortcodes(
            "双胞胎你好:waving_hand:".to_string(),
            "https://linux.do",
        );
        assert_eq!(kinds.len(), 2);
        assert!(matches!(
            &kinds[0],
            RenderBlockKind::Text { content } if content == "双胞胎你好"
        ));
        assert!(matches!(
            &kinds[1],
            RenderBlockKind::Emoji { url, fallback_text, only_emoji: false }
                if url == "https://linux.do/images/emoji/twitter/waving_hand.png?v=12"
                    && fallback_text == ":waving_hand:"
        ));
    }

    #[test]
    fn keeps_plain_text_without_shortcodes() {
        let kinds = kinds_from_text_with_shortcodes("没有表情".to_string(), "https://linux.do");
        assert_eq!(kinds.len(), 1);
        assert!(matches!(
            &kinds[0],
            RenderBlockKind::Text { content } if content == "没有表情"
        ));
    }

    #[test]
    fn expands_skin_tone_shortcode() {
        let kinds =
            kinds_from_text_with_shortcodes("hi :wave:t3: there".to_string(), "https://linux.do");
        assert_eq!(kinds.len(), 3);
        assert!(matches!(
            &kinds[1],
            RenderBlockKind::Emoji { url, .. }
                if url == "https://linux.do/images/emoji/twitter/wave/t3.png?v=12"
        ));
    }

    #[test]
    fn marks_only_emoji_when_the_whole_run_is_shortcodes() {
        let kinds =
            kinds_from_text_with_shortcodes(":waving_hand:".to_string(), "https://linux.do");
        assert!(matches!(
            &kinds[..],
            [RenderBlockKind::Emoji {
                only_emoji: true,
                ..
            }]
        ));
    }

    #[test]
    fn ignores_digit_only_lookalikes() {
        let kinds =
            kinds_from_text_with_shortcodes("at :12: sharp".to_string(), "https://linux.do");
        assert_eq!(kinds.len(), 1);
        assert!(matches!(
            &kinds[0],
            RenderBlockKind::Text { content } if content == "at :12: sharp"
        ));
    }
}
