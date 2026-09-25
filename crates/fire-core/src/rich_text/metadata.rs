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

