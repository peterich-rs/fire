use std::collections::HashSet;

use fire_models::{CookedHtmlNode, CookedHtmlNodeKind};
use url::Url;

use crate::images::resolved_asset_url;
use crate::map::{
    class_names, is_emoji_node, normalized_attributes, normalized_text, numeric_attribute,
    subtree_text, CookedTree,
};

pub(crate) fn onebox_presentation(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
    base_url: &str,
) -> OneboxPresentation {
    let (title, description) = onebox_title_and_description(node, tree);
    let mut presentation = OneboxPresentation {
        title,
        description,
        source_name: None,
        icon_url: None,
        thumbnail_url: None,
        thumbnail_width: None,
        thumbnail_height: None,
    };
    collect_onebox_chrome(node, tree, base_url, &mut presentation);
    if presentation.source_name.is_none() {
        presentation.source_name = host_label(node.url.as_deref());
    }
    presentation
}

#[derive(Default)]
pub(crate) struct OneboxPresentation {
    pub(crate) title: Option<String>,
    pub(crate) description: Option<String>,
    pub(crate) source_name: Option<String>,
    pub(crate) icon_url: Option<String>,
    pub(crate) thumbnail_url: Option<String>,
    pub(crate) thumbnail_width: Option<u32>,
    pub(crate) thumbnail_height: Option<u32>,
}

fn collect_onebox_chrome(
    node: &CookedHtmlNode,
    tree: &CookedTree<'_>,
    base_url: &str,
    presentation: &mut OneboxPresentation,
) {
    for child in tree.children_of(node) {
        if child.kind == CookedHtmlNodeKind::Link
            && presentation.source_name.is_none()
            && tree
                .nearest_ancestor(child, |ancestor| {
                    ancestor.kind == CookedHtmlNodeKind::Heading
                })
                .is_none()
        {
            if let Some(text) = normalized_text(Some(&subtree_text(child, tree))) {
                presentation.source_name = source_label(&text);
            }
        }
        if child.kind == CookedHtmlNodeKind::Image && !is_emoji_node(child) {
            let attrs = normalized_attributes(child);
            let classes = class_names(attrs.get("class").map(String::as_str));
            let url = child
                .url
                .as_deref()
                .and_then(|raw| resolved_asset_url(raw, base_url));
            if is_site_icon_class(&classes) {
                if presentation.icon_url.is_none() {
                    presentation.icon_url = url;
                }
            } else if classes.contains("thumbnail") && presentation.thumbnail_url.is_none() {
                presentation.thumbnail_url = url;
                presentation.thumbnail_width = numeric_attribute("width", &attrs);
                presentation.thumbnail_height = numeric_attribute("height", &attrs);
            }
        }
        collect_onebox_chrome(child, tree, base_url, presentation);
    }
}

pub(crate) fn is_site_icon_class(classes: &HashSet<String>) -> bool {
    classes.contains("site-icon") || classes.contains("favicon")
}

fn source_label(text: &str) -> Option<String> {
    let head = text
        .split(['–', '—'])
        .next()
        .unwrap_or(text)
        .split(" - ")
        .next()
        .unwrap_or(text)
        .trim();
    if head.is_empty() || head.chars().count() > 64 {
        return None;
    }
    if head.contains(char::is_whitespace) && head.chars().count() > 24 {
        return None;
    }
    Some(head.to_string())
}

fn host_label(raw: Option<&str>) -> Option<String> {
    let raw = raw?.trim();
    if raw.is_empty() {
        return None;
    }
    Url::parse(raw)
        .ok()
        .and_then(|url| url.host_str().map(ToOwned::to_owned))
        .map(|host| host.trim_start_matches("www.").to_string())
        .filter(|host| !host.is_empty())
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
