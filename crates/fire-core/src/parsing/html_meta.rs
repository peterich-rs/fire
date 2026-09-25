use std::sync::OnceLock;

use regex::Regex;

pub(super) fn find_meta_content(html: &str, target_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if !tag.starts_with("<meta") && !tag.starts_with("<META") {
            continue;
        }

        let Some(name) = extract_attr(tag, "name") else {
            continue;
        };
        if !name.eq_ignore_ascii_case(target_name) {
            continue;
        }

        if let Some(content) = extract_attr(tag, "content") {
            return Some(decode_html_entities(&content));
        }
    }

    None
}

pub(super) fn find_first_attr(html: &str, attribute_name: &str) -> Option<String> {
    for tag in all_tags(html) {
        if let Some(value) = extract_attr(tag, attribute_name) {
            return Some(decode_html_entities(&value));
        }
    }

    None
}

fn all_tags(html: &str) -> impl Iterator<Item = &str> {
    static TAG_RE: OnceLock<Regex> = OnceLock::new();
    // NOTE: This lightweight scanner is intentionally scoped to Discourse bootstrap tags.
    // If parsing expands beyond meta/data-* extraction, switch to a real HTML parser.
    let regex = TAG_RE.get_or_init(|| Regex::new(r"(?is)<[^>]+>").expect("tag regex"));
    regex.find_iter(html).map(|matched| matched.as_str())
}

fn extract_attr(tag: &str, attribute_name: &str) -> Option<String> {
    static ATTR_RE: OnceLock<Regex> = OnceLock::new();
    let regex = ATTR_RE.get_or_init(|| {
        Regex::new(
            r#"(?is)\b([a-zA-Z0-9:_-]+)\s*=\s*"([^"]*)"|\b([a-zA-Z0-9:_-]+)\s*=\s*'([^']*)'"#,
        )
        .expect("attr regex")
    });

    for captures in regex.captures_iter(tag) {
        let (name, value) = if let (Some(name), Some(value)) = (captures.get(1), captures.get(2)) {
            (name.as_str(), value.as_str())
        } else if let (Some(name), Some(value)) = (captures.get(3), captures.get(4)) {
            (name.as_str(), value.as_str())
        } else {
            continue;
        };

        if !name.eq_ignore_ascii_case(attribute_name) {
            continue;
        }
        return Some(value.to_string());
    }

    None
}

pub(crate) fn decode_html_entities(raw: &str) -> String {
    let mut decoded = String::with_capacity(raw.len());
    let mut cursor = raw;

    while let Some(start) = cursor.find('&') {
        decoded.push_str(&cursor[..start]);
        let entity_start = &cursor[start..];

        let Some(end) = entity_start.find(';') else {
            decoded.push_str(entity_start);
            return decoded;
        };

        let entity = &entity_start[1..end];
        if let Some(ch) = decode_html_entity(entity) {
            decoded.push(ch);
        } else {
            decoded.push_str(&entity_start[..=end]);
        }

        cursor = &entity_start[end + 1..];
    }

    decoded.push_str(cursor);
    decoded
}

fn decode_html_entity(entity: &str) -> Option<char> {
    match entity {
        "nbsp" | "#160" => Some(' '),
        "quot" => Some('"'),
        "amp" => Some('&'),
        "lt" => Some('<'),
        "gt" => Some('>'),
        "apos" | "#39" => Some('\''),
        _ => decode_numeric_html_entity(entity),
    }
}

fn decode_numeric_html_entity(entity: &str) -> Option<char> {
    let value = if let Some(hex) = entity
        .strip_prefix("#x")
        .or_else(|| entity.strip_prefix("#X"))
    {
        u32::from_str_radix(hex, 16).ok()?
    } else {
        let decimal = entity.strip_prefix('#')?;
        decimal.parse::<u32>().ok()?
    };

    char::from_u32(value)
}
