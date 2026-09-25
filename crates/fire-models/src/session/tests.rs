use super::*;
use crate::{CookieSnapshot, PlatformCookie, TopicCategory};

#[test]
fn readiness_ignores_expired_platform_auth_cookies() {
    let cookies = CookieSnapshot {
        t_token: Some("stale-token".into()),
        forum_session: Some("stale-forum".into()),
        cf_clearance: Some("stale-clearance".into()),
        csrf_token: None,
        last_challenged_cf_clearance: None,
        platform_cookies: vec![
            PlatformCookie {
                name: "_t".into(),
                value: "expired-token".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: Some(1),
                same_site: None,
            },
            PlatformCookie {
                name: "_forum_session".into(),
                value: "expired-forum".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: Some(1),
                same_site: None,
            },
            PlatformCookie {
                name: "cf_clearance".into(),
                value: "expired-clearance".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: Some(1),
                same_site: None,
            },
        ],
        canonical_cookies: Vec::new(),
    };

    assert!(!cookies.has_login_session());
    assert!(!cookies.has_forum_session());
    assert!(!cookies.has_cloudflare_clearance());
    assert!(!cookies.can_authenticate_requests());
}

#[test]
fn login_phase_advances_with_bootstrap_and_csrf() {
    let mut snapshot = SessionSnapshot::default();
    assert_eq!(snapshot.login_phase(), LoginPhase::Anonymous);

    snapshot.cookies.t_token = Some("token".into());
    assert_eq!(snapshot.login_phase(), LoginPhase::CookiesCaptured);

    snapshot.cookies.forum_session = Some("forum".into());
    snapshot.bootstrap.current_username = Some("alice".into());
    assert_eq!(snapshot.login_phase(), LoginPhase::BootstrapCaptured);

    snapshot.cookies.csrf_token = Some("csrf".into());
    snapshot.bootstrap.preloaded_json = Some("{\"currentUser\":{\"username\":\"alice\"}}".into());
    snapshot.bootstrap.has_preloaded_data = true;
    snapshot.bootstrap.has_site_metadata = true;
    snapshot.bootstrap.has_site_settings = true;
    assert_eq!(snapshot.login_phase(), LoginPhase::Ready);
}

#[test]
fn merge_patch_keeps_existing_site_metadata_when_partial_preloaded_lacks_site() {
    let mut bootstrap = BootstrapArtifacts {
        preloaded_json: Some("{\"site\":{\"categories\":[{\"id\":2}]}}".into()),
        has_preloaded_data: true,
        has_site_metadata: true,
        top_tags: vec!["swift".into()],
        can_tag_topics: true,
        categories: vec![TopicCategory {
            id: 2,
            name: "Rust".into(),
            slug: "rust".into(),
            parent_category_id: None,
            color_hex: Some("FFFFFF".into()),
            text_color_hex: Some("000000".into()),
            ..TopicCategory::default()
        }],
        has_site_settings: true,
        enabled_reaction_ids: vec!["heart".into(), "clap".into()],
        min_post_length: 20,
        min_topic_title_length: 15,
        min_first_post_length: 20,
        default_composer_category: Some(2),
        ..BootstrapArtifacts::default()
    };

    bootstrap.merge_patch(&BootstrapArtifacts {
        preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    });

    assert!(bootstrap.has_site_metadata);
    assert_eq!(bootstrap.top_tags, vec!["swift"]);
    assert!(bootstrap.can_tag_topics);
    assert_eq!(bootstrap.categories.len(), 1);
    assert!(bootstrap.has_site_settings);
    assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
    assert_eq!(bootstrap.min_post_length, 20);
    assert_eq!(bootstrap.min_topic_title_length, 15);
    assert_eq!(bootstrap.min_first_post_length, 20);
    assert_eq!(bootstrap.default_composer_category, Some(2));
}

#[test]
fn merge_patch_updates_site_metadata_and_settings_when_present() {
    let mut bootstrap = BootstrapArtifacts::default();

    bootstrap.merge_patch(&BootstrapArtifacts {
        preloaded_json: Some("{\"site\":{},\"siteSettings\":{}}".into()),
        has_preloaded_data: true,
        has_site_metadata: true,
        top_tags: vec!["rust".into(), "swift".into(), "rust".into()],
        can_tag_topics: true,
        categories: vec![TopicCategory {
            id: 2,
            name: "Rust".into(),
            slug: "rust".into(),
            parent_category_id: None,
            color_hex: None,
            text_color_hex: None,
            ..TopicCategory::default()
        }],
        has_site_settings: true,
        enabled_reaction_ids: vec!["heart".into(), "clap".into(), "heart".into()],
        min_post_length: 18,
        min_topic_title_length: 16,
        min_first_post_length: 24,
        default_composer_category: Some(2),
        ..BootstrapArtifacts::default()
    });

    assert!(bootstrap.has_site_metadata);
    assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
    assert!(bootstrap.can_tag_topics);
    assert_eq!(bootstrap.categories.len(), 1);
    assert!(bootstrap.has_site_settings);
    assert_eq!(bootstrap.enabled_reaction_ids, vec!["heart", "clap"]);
    assert_eq!(bootstrap.min_post_length, 18);
    assert_eq!(bootstrap.min_topic_title_length, 16);
    assert_eq!(bootstrap.min_first_post_length, 24);
    assert_eq!(bootstrap.default_composer_category, Some(2));
}

#[test]
fn merge_patch_applies_site_metadata_without_preloaded_payload() {
    let mut bootstrap = BootstrapArtifacts {
        preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    };

    bootstrap.merge_patch(&BootstrapArtifacts {
        has_site_metadata: true,
        top_tags: vec!["rust".into(), "swift".into()],
        can_tag_topics: true,
        categories: vec![TopicCategory {
            id: 2,
            name: "Rust".into(),
            slug: "rust".into(),
            parent_category_id: None,
            color_hex: None,
            text_color_hex: None,
            ..TopicCategory::default()
        }],
        ..BootstrapArtifacts::default()
    });

    assert!(bootstrap.has_site_metadata);
    assert_eq!(bootstrap.top_tags, vec!["rust", "swift"]);
    assert!(bootstrap.can_tag_topics);
    assert_eq!(bootstrap.categories.len(), 1);
    assert!(bootstrap.has_preloaded_data);
}

#[test]
fn same_origin_message_bus_does_not_require_shared_session_key() {
    let snapshot = SessionSnapshot {
        cookies: CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            ..CookieSnapshot::default()
        },
        bootstrap: BootstrapArtifacts {
            base_url: "https://linux.do".into(),
            long_polling_base_url: Some("https://linux.do".into()),
            current_username: Some("alice".into()),
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        },
        browser_user_agent: None,
        read_path_login_request: None,
    };

    let readiness = snapshot.readiness();

    assert!(!readiness.has_shared_session_key);
    assert!(readiness.can_open_message_bus);
}

#[test]
fn cross_origin_message_bus_requires_shared_session_key() {
    let snapshot = SessionSnapshot {
        cookies: CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            ..CookieSnapshot::default()
        },
        bootstrap: BootstrapArtifacts {
            base_url: "https://linux.do".into(),
            long_polling_base_url: Some("https://poll.linux.do".into()),
            current_username: Some("alice".into()),
            preloaded_json: Some("{\"currentUser\":{\"username\":\"alice\"}}".into()),
            has_preloaded_data: true,
            ..BootstrapArtifacts::default()
        },
        browser_user_agent: None,
        read_path_login_request: None,
    };

    let readiness = snapshot.readiness();

    assert!(!readiness.has_shared_session_key);
    assert!(!readiness.can_open_message_bus);
}

#[test]
fn clear_login_state_preserves_cf_when_requested() {
    let mut snapshot = SessionSnapshot {
        cookies: CookieSnapshot {
            t_token: Some("token".into()),
            forum_session: Some("forum".into()),
            cf_clearance: Some("clearance".into()),
            csrf_token: Some("csrf".into()),
            last_challenged_cf_clearance: None,
            platform_cookies: Vec::new(),
            canonical_cookies: Vec::new(),
        },
        bootstrap: BootstrapArtifacts {
            base_url: "https://linux.do".into(),
            discourse_base_uri: Some("/".into()),
            shared_session_key: Some("shared".into()),
            current_username: Some("alice".into()),
            current_user_id: Some(1),
            notification_channel_position: Some(42),
            long_polling_base_url: Some("https://linux.do".into()),
            turnstile_sitekey: Some("sitekey".into()),
            topic_tracking_state_meta: Some("{\"seq\":1}".into()),
            preloaded_json: Some("{\"ok\":true}".into()),
            has_preloaded_data: true,
            has_site_metadata: true,
            top_tags: vec!["rust".into()],
            can_tag_topics: true,
            categories: Vec::new(),
            has_site_settings: true,
            enabled_reaction_ids: vec!["heart".into(), "clap".into()],
            min_post_length: 20,
            min_topic_title_length: 15,
            min_first_post_length: 20,
            min_personal_message_title_length: 2,
            min_personal_message_post_length: 10,
            default_composer_category: Some(2),
        },
        browser_user_agent: None,
        read_path_login_request: None,
    };

    snapshot.clear_login_state(true);

    assert_eq!(snapshot.cookies.cf_clearance.as_deref(), Some("clearance"));
    assert_eq!(snapshot.cookies.t_token, None);
    assert_eq!(snapshot.bootstrap.current_username, None);
    assert_eq!(snapshot.bootstrap.current_user_id, None);
    assert_eq!(snapshot.bootstrap.notification_channel_position, None);
    assert_eq!(snapshot.bootstrap.shared_session_key, None);
    assert_eq!(snapshot.bootstrap.preloaded_json, None);
    assert!(!snapshot.bootstrap.has_preloaded_data);
    assert_eq!(
        snapshot.bootstrap.turnstile_sitekey.as_deref(),
        Some("sitekey")
    );
    assert!(!snapshot.bootstrap.has_site_metadata);
    assert_eq!(snapshot.bootstrap.top_tags, Vec::<String>::new());
    assert!(!snapshot.bootstrap.can_tag_topics);
    assert_eq!(snapshot.bootstrap.categories, Vec::new());
    assert!(!snapshot.bootstrap.has_site_settings);
    assert_eq!(snapshot.bootstrap.enabled_reaction_ids, vec!["heart"]);
    assert_eq!(snapshot.bootstrap.min_post_length, 1);
    assert_eq!(snapshot.bootstrap.min_topic_title_length, 15);
    assert_eq!(snapshot.bootstrap.min_first_post_length, 20);
    assert_eq!(snapshot.bootstrap.default_composer_category, None);
}
