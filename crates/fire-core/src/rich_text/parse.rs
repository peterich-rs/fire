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

