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
