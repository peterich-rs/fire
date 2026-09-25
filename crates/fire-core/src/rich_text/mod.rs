use std::collections::BTreeMap;

use ego_tree::NodeRef;
use fire_models::{CookedHtmlDocument, CookedHtmlNode, CookedHtmlNodeKind, RenderDocument};
use std::sync::Arc;

use fire_models::{
    AttachedPresentation, ChatMessage, PresentedDocument, TopicPost, TopicPostBoost,
};
use fire_rich_text::{present_owned_document, render_document as shared_render_document};
use html5ever::tendril::TendrilSink;
use html5ever::{local_name, ns, QualName};
use scraper::{ElementRef, Html, HtmlTreeSink, Node as ScraperNode};

include!("parse.rs");
include!("attach.rs");
include!("builder.rs");
include!("metadata.rs");
include!("classify.rs");
include!("tests.rs");
