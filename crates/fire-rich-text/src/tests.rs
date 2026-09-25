use std::collections::BTreeMap;

use fire_models::{
    CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderBlockKind, RenderRichNode,
    RenderUiSegment,
};

use super::*;
use crate::images::looks_like_image_attachment_metadata;

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
fn render_document_normalizes_emoji_image_fallbacks() {
    let document = CookedHtmlDocument {
        nodes: vec![
            node(0, None, 0, CookedHtmlNodeKind::Document),
            node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
            emoji_node_with_attrs(
                2,
                1,
                2,
                "/images/emoji/twitter/smile.png?v=12",
                BTreeMap::from([
                    ("class".to_string(), "emoji".to_string()),
                    ("title".to_string(), "smile".to_string()),
                ]),
            ),
            emoji_node_with_attrs(
                3,
                1,
                2,
                "/images/emoji/twitter/wave/t3.png?v=12",
                BTreeMap::from([("class".to_string(), "emoji".to_string())]),
            ),
        ],
        plain_text: String::new(),
        image_urls: Vec::new(),
        link_urls: Vec::new(),
    };

    let rendered = render_document(&document, "https://linux.do");

    assert_eq!(rendered.plain_text, ":smile::wave:t3:");
    assert!(rendered.image_attachments.is_empty());
}

#[test]
fn render_document_expands_leftover_emoji_shortcodes_in_text() {
    let document = CookedHtmlDocument {
        nodes: vec![
            node(0, None, 0, CookedHtmlNodeKind::Document),
            node(1, Some(0), 1, CookedHtmlNodeKind::Paragraph),
            text_node(2, 1, 2, "双胞胎你好:waving_hand:"),
        ],
        plain_text: "双胞胎你好:waving_hand:".to_string(),
        image_urls: Vec::new(),
        link_urls: Vec::new(),
    };

    let rendered = render_document(&document, "https://linux.do");
    assert_eq!(rendered.plain_text, "双胞胎你好:waving_hand:");
    assert!(rendered.blocks.iter().any(|block| matches!(
        &block.kind,
        RenderBlockKind::Emoji {
            url,
            fallback_text,
            only_emoji: false
        } if url == "https://linux.do/images/emoji/twitter/waving_hand.png?v=12"
            && fallback_text == ":waving_hand:"
    )));
    assert!(!rendered.blocks.iter().any(|block| matches!(
        &block.kind,
        RenderBlockKind::Text { content } if content.contains(":waving_hand:")
    )));

    let segments = display_segments(&rendered);
    assert!(segments.iter().any(|segment| matches!(
        segment,
        RenderUiSegment::Rich { nodes }
            if nodes.iter().any(|node| matches!(
                node,
                RenderRichNode::Paragraph { children }
                    if children.iter().any(|child| matches!(
                        child,
                        RenderRichNode::Emoji { url, .. }
                            if url == "https://linux.do/images/emoji/twitter/waving_hand.png?v=12"
                    ))
            ))
    )));
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
        plain_text: "image 1080x1920 52.5kb screen-shot 1080x1920 34kb a1b2c3_690x388_11kb caption"
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
            source_name: Some(source_name),
            ..
        } if url == "https://example.com/post"
            && title == "Example title"
            && description == "Example description"
            && source_name == "example.com"
    )));
}

#[test]
fn onebox_site_icon_is_not_a_trailing_post_image() {
    let mut onebox = node(1, Some(0), 1, CookedHtmlNodeKind::Onebox);
    onebox.url = Some("https://www.bilibili.com/video/BV1".to_string());
    let document = CookedHtmlDocument {
        nodes: vec![
            node(0, None, 0, CookedHtmlNodeKind::Document),
            onebox,
            image_node_with_attrs(
                2,
                1,
                2,
                "https://www.bilibili.com/favicon.ico",
                "",
                "16",
                "16",
                BTreeMap::from([("class".to_string(), "site-icon".to_string())]),
            ),
            link_node(3, 1, 2, "https://www.bilibili.com/video/BV1", ""),
            text_node(4, 3, 3, "bilibili.com"),
            image_node_with_attrs(
                5,
                1,
                2,
                "https://i0.hdslb.com/bfs/archive/cover.jpg",
                "",
                "480",
                "270",
                BTreeMap::from([("class".to_string(), "thumbnail".to_string())]),
            ),
            node(6, Some(1), 2, CookedHtmlNodeKind::Heading),
            text_node(7, 6, 3, "开源神器"),
            node(8, Some(1), 2, CookedHtmlNodeKind::Paragraph),
            text_node(9, 8, 3, "番茄钟说明"),
        ],
        plain_text: String::new(),
        image_urls: Vec::new(),
        link_urls: Vec::new(),
    };

    let rendered = render_document(&document, "https://linux.do");
    assert!(rendered.image_attachments.is_empty());
    let segments = display_segments(&rendered);
    assert!(segments
        .iter()
        .all(|segment| !matches!(segment, RenderUiSegment::Image(_))));
    assert!(rendered.blocks.iter().any(|block| matches!(
        &block.kind,
        RenderBlockKind::Onebox {
            source_name: Some(source_name),
            icon_url: Some(icon_url),
            thumbnail_url: Some(thumbnail_url),
            thumbnail_width: Some(480),
            thumbnail_height: Some(270),
            title: Some(title),
            description: Some(description),
            ..
        } if source_name == "bilibili.com"
            && icon_url == "https://www.bilibili.com/favicon.ico"
            && thumbnail_url == "https://i0.hdslb.com/bfs/archive/cover.jpg"
            && title == "开源神器"
            && description == "番茄钟说明"
    )));
}

fn node(id: u32, parent_id: Option<u32>, depth: u32, kind: CookedHtmlNodeKind) -> CookedHtmlNode {
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

fn link_node(id: u32, parent_id: u32, depth: u32, url: &str, class_name: &str) -> CookedHtmlNode {
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

#[allow(clippy::too_many_arguments)]
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

fn emoji_node_with_attrs(
    id: u32,
    parent_id: u32,
    depth: u32,
    url: &str,
    attributes: BTreeMap<String, String>,
) -> CookedHtmlNode {
    CookedHtmlNode {
        url: Some(url.to_string()),
        attributes,
        ..node(id, Some(parent_id), depth, CookedHtmlNodeKind::Emoji)
    }
}
