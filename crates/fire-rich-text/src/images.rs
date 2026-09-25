use std::collections::{BTreeMap, HashSet};

use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderImageAttachment};
use url::Url;

use crate::map::{
    class_names, is_emoji_node, normalized_attributes, normalized_text, numeric_attribute,
    CookedTree, TreeRenderBlock,
};
use crate::onebox::is_site_icon_class;
use crate::plain_text::extract_text_content;

pub(crate) fn should_suppress_link_for_inline_image(
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

pub(crate) fn cleaned_text_node_content(
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

pub(crate) fn looks_like_image_attachment_metadata(value: &str) -> bool {
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

pub(crate) fn should_skip_render_image(
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

pub(crate) fn is_avatar_url(value: &str) -> bool {
    let normalized_path = Url::parse(value)
        .ok()
        .map(|parsed| parsed.path().to_ascii_lowercase())
        .unwrap_or_else(|| value.to_ascii_lowercase());
    normalized_path.contains("/user_avatar/") || normalized_path.contains("/letter_avatar/")
}

pub(crate) fn is_profile_url(value: &str) -> bool {
    Url::parse(value)
        .ok()
        .map(|url| url.path().starts_with("/u/"))
        .unwrap_or_else(|| value.starts_with("/u/") || value.starts_with("fire://profile/"))
}

pub(crate) fn is_quote_title_separator(value: &str) -> bool {
    matches!(value.trim(), ":" | "：")
}

pub(crate) fn collect_image_attachments(
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

    if is_site_icon_class(&classes)
        || classes.contains("avatar")
        || classes.contains("user-avatar")
        || classes.contains("thumbnail")
        || classes.contains("ytp-thumbnail-image")
        || normalized_path.contains("/user_avatar/")
        || normalized_path.contains("/letter_avatar/")
        || tree
            .nearest_ancestor(node, |ancestor| ancestor.kind == CookedHtmlNodeKind::Onebox)
            .is_some()
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

pub(crate) fn resolved_asset_url(raw: &str, base_url: &str) -> Option<String> {
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
