use fire_models::{BootstrapArtifacts, CookieSnapshot};

use super::{
    html_meta::{find_first_attr, find_meta_content},
    preloaded::hydrate_preloaded_fields,
};

#[derive(Debug, Default)]
pub(crate) struct ParsedHomeState {
    pub(crate) cookies_patch: CookieSnapshot,
    pub(crate) bootstrap_patch: BootstrapArtifacts,
}

pub(crate) fn parse_home_state(base_url: &str, html: &str) -> ParsedHomeState {
    let mut parsed = ParsedHomeState {
        bootstrap_patch: BootstrapArtifacts {
            base_url: base_url.to_string(),
            ..BootstrapArtifacts::default()
        },
        ..ParsedHomeState::default()
    };

    parsed.cookies_patch.csrf_token = find_meta_content(html, "csrf-token");
    parsed.bootstrap_patch.shared_session_key = find_meta_content(html, "shared_session_key");
    parsed.bootstrap_patch.current_username = find_meta_content(html, "current-username");
    parsed.bootstrap_patch.discourse_base_uri = find_meta_content(html, "discourse-base-uri");
    parsed.bootstrap_patch.turnstile_sitekey = find_first_attr(html, "data-sitekey");

    if let Some(preloaded_json) = find_first_attr(html, "data-preloaded") {
        parsed.bootstrap_patch.preloaded_json = Some(preloaded_json.clone());
        parsed.bootstrap_patch.has_preloaded_data = true;
        hydrate_preloaded_fields(&preloaded_json, &mut parsed.bootstrap_patch);
    }

    parsed
}
