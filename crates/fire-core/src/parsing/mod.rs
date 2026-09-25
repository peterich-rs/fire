mod home;
mod html_meta;
mod preloaded;
mod site_metadata;
mod site_settings;

#[allow(unused_imports)]
pub(crate) use home::{parse_home_state, ParsedHomeState};
#[allow(unused_imports)]
pub(crate) use html_meta::decode_html_entities;
pub(crate) use preloaded::{hydrate_preloaded_fields, parse_preloaded_payload};
#[allow(unused_imports)]
pub(crate) use site_metadata::{hydrate_site_metadata_fields, parse_site_metadata_json};
#[allow(unused_imports)]
pub(crate) use site_settings::hydrate_site_settings_fields;

#[cfg(test)]
mod tests;
