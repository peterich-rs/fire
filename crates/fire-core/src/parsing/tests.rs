use fire_models::BootstrapArtifacts;

use super::{
    decode_html_entities, hydrate_preloaded_fields, parse_home_state, parse_site_metadata_json,
};

#[test]
fn parse_home_state_skips_meta_tags_without_name() {
    let html = r#"
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="csrf-token" content="csrf-token">
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
</html>
"#;

    let parsed = parse_home_state("https://linux.do/", html);

    assert_eq!(
        parsed.cookies_patch.csrf_token.as_deref(),
        Some("csrf-token")
    );
    assert_eq!(
        parsed.bootstrap_patch.shared_session_key.as_deref(),
        Some("shared-session")
    );
    assert_eq!(
        parsed.bootstrap_patch.current_username.as_deref(),
        Some("alice")
    );
    assert_eq!(
        parsed.bootstrap_patch.discourse_base_uri.as_deref(),
        Some("/")
    );
}

#[test]
fn parse_home_state_decodes_preloaded_json_once() {
    let html = r#"
<!doctype html>
<html>
  <body>
    <div data-preloaded="{&quot;siteSettings&quot;:{&quot;title&quot;:&quot;A &amp;amp; B&quot;,&quot;min_post_length&quot;:18,&quot;min_topic_title_length&quot;:15,&quot;min_first_post_length&quot;:24,&quot;default_composer_category&quot;:7,&quot;discourse_reactions_enabled_reactions&quot;:&quot;heart|clap&quot;},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:7,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;,&quot;color&quot;:&quot;FFFFFF&quot;,&quot;text_color&quot;:&quot;000000&quot;,&quot;topic_template&quot;:&quot;## Template&quot;,&quot;minimum_required_tags&quot;:2,&quot;required_tag_groups&quot;:[{&quot;name&quot;:&quot;platform&quot;,&quot;min_count&quot;:1}],&quot;allowed_tags&quot;:[&quot;swift&quot;,&quot;rust&quot;],&quot;permission&quot;:1,&quot;notification_level&quot;:&quot;4&quot;}],&quot;top_tags&quot;:[{&quot;name&quot;:&quot;swift&quot;},&quot;rust&quot;],&quot;can_tag_topics&quot;:true}}"></div>
  </body>
</html>
"#;

    let parsed = parse_home_state("https://linux.do/", html);

    assert_eq!(
        parsed.bootstrap_patch.preloaded_json.as_deref(),
        Some(
            r###"{"siteSettings":{"title":"A &amp; B","min_post_length":18,"min_topic_title_length":15,"min_first_post_length":24,"default_composer_category":7,"discourse_reactions_enabled_reactions":"heart|clap"},"site":{"categories":[{"id":7,"name":"Rust","slug":"rust","color":"FFFFFF","text_color":"000000","topic_template":"## Template","minimum_required_tags":2,"required_tag_groups":[{"name":"platform","min_count":1}],"allowed_tags":["swift","rust"],"permission":1,"notification_level":"4"}],"top_tags":[{"name":"swift"},"rust"],"can_tag_topics":true}}"###
        )
    );
    assert!(parsed.bootstrap_patch.has_site_settings);
    assert_eq!(parsed.bootstrap_patch.min_post_length, 18);
    assert_eq!(parsed.bootstrap_patch.min_topic_title_length, 15);
    assert_eq!(parsed.bootstrap_patch.min_first_post_length, 24);
    assert_eq!(parsed.bootstrap_patch.default_composer_category, Some(7));
    assert_eq!(
        parsed.bootstrap_patch.enabled_reaction_ids,
        vec!["heart", "clap"]
    );
    assert!(parsed.bootstrap_patch.has_site_metadata);
    assert_eq!(parsed.bootstrap_patch.top_tags, vec!["swift", "rust"]);
    assert!(parsed.bootstrap_patch.can_tag_topics);
    assert_eq!(parsed.bootstrap_patch.categories.len(), 1);
    assert_eq!(parsed.bootstrap_patch.categories[0].id, 7);
    assert_eq!(
        parsed.bootstrap_patch.categories[0]
            .topic_template
            .as_deref(),
        Some("## Template")
    );
    assert_eq!(
        parsed.bootstrap_patch.categories[0].minimum_required_tags,
        2
    );
    assert_eq!(
        parsed.bootstrap_patch.categories[0]
            .required_tag_groups
            .len(),
        1
    );
    assert_eq!(
        parsed.bootstrap_patch.categories[0].allowed_tags,
        vec!["swift", "rust"]
    );
    assert_eq!(parsed.bootstrap_patch.categories[0].permission, Some(1));
    assert_eq!(
        parsed.bootstrap_patch.categories[0].notification_level,
        Some(4)
    );
}

#[test]
fn parse_home_state_marks_partial_preloaded_without_site_as_incomplete() {
    let html = r#"
<!doctype html>
<html>
  <body>
    <div data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;}}"></div>
  </body>
</html>
"#;

    let parsed = parse_home_state("https://linux.do/", html);

    assert!(parsed.bootstrap_patch.has_preloaded_data);
    assert!(!parsed.bootstrap_patch.has_site_metadata);
    assert!(!parsed.bootstrap_patch.has_site_settings);
    assert_eq!(parsed.bootstrap_patch.categories, Vec::new());
    assert_eq!(parsed.bootstrap_patch.top_tags, Vec::<String>::new());
    assert!(!parsed.bootstrap_patch.can_tag_topics);
}

#[test]
fn hydrate_preloaded_fields_unwraps_stringified_root_payloads() {
    let mut bootstrap = BootstrapArtifacts::default();
    hydrate_preloaded_fields(
        r###"{
  "currentUser":"{\"id\":341628,\"username\":\"alice\",\"notification_channel_position\":11}",
  "siteSettings":"{\"long_polling_base_url\":\"https://ping.linux.do\",\"min_post_length\":18,\"min_topic_title_length\":15,\"min_first_post_length\":24,\"default_composer_category\":7,\"discourse_reactions_enabled_reactions\":\"heart|clap\"}",
  "site":"{\"categories\":[{\"id\":7,\"name\":\"Rust\",\"slug\":\"rust\",\"color\":\"FFFFFF\",\"text_color\":\"000000\",\"topic_template\":\"## Template\",\"minimum_required_tags\":2,\"required_tag_groups\":[{\"name\":\"platform\",\"min_count\":1}],\"allowed_tags\":[\"swift\",\"rust\"],\"permission\":1,\"notification_level\":3}],\"top_tags\":[{\"name\":\"swift\"},\"rust\"],\"can_tag_topics\":true}",
  "topicTrackingStateMeta":"{\"/latest\":42,\"/new\":8}"
}"###,
        &mut bootstrap,
    );

    assert_eq!(bootstrap.current_username.as_deref(), Some("alice"));
    assert_eq!(bootstrap.current_user_id, Some(341628));
    assert_eq!(bootstrap.notification_channel_position, Some(11));
    assert_eq!(
        bootstrap.long_polling_base_url.as_deref(),
        Some("https://ping.linux.do")
    );
    assert_eq!(
        bootstrap.topic_tracking_state_meta.as_deref(),
        Some(r#"{"/latest":42,"/new":8}"#)
    );
    assert!(bootstrap.has_site_metadata);
    assert_eq!(bootstrap.top_tags, vec!["swift", "rust"]);
    assert!(bootstrap.can_tag_topics);
    assert_eq!(bootstrap.categories.len(), 1);
    assert_eq!(bootstrap.categories[0].id, 7);
    assert!(bootstrap.has_site_settings);
    assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
    assert_eq!(bootstrap.min_post_length, 18);
    assert_eq!(bootstrap.min_topic_title_length, 15);
    assert_eq!(bootstrap.min_first_post_length, 24);
    assert_eq!(bootstrap.default_composer_category, Some(7));
    assert_eq!(bootstrap.categories[0].minimum_required_tags, 2);
    assert_eq!(bootstrap.categories[0].permission, Some(1));
    assert_eq!(bootstrap.categories[0].notification_level, Some(3));
}

#[test]
fn parse_site_metadata_json_reads_root_site_json_shape() {
    let parsed = parse_site_metadata_json(
        "https://linux.do/",
        r#"{
                "categories": [
                    {"id": 7, "name": "Rust", "slug": "rust", "color": "FFFFFF", "text_color": "000000"}
                ],
                "top_tags": [{"name": "swift"}, "rust"],
                "can_tag_topics": true
            }"#,
    );

    assert!(parsed.has_site_metadata);
    assert_eq!(parsed.categories.len(), 1);
    assert_eq!(parsed.top_tags, vec!["swift", "rust"]);
    assert!(parsed.can_tag_topics);
    assert_eq!(parsed.base_url, "https://linux.do/");
}

#[test]
fn decode_html_entities_supports_named_and_numeric_forms() {
    assert_eq!(
        decode_html_entities("&quot;&amp;&lt;&gt;&#39;&apos;&#x41;&#65;"),
        "\"&<>''AA"
    );
}
