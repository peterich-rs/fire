mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{CookieSnapshot, DraftData, TopicCreateRequest, TopicTimingEntry, TopicTimingsRequest};

#[tokio::test]
async fn report_topic_timings_posts_form_payload_with_background_headers() {
    let server = TestServer::spawn(vec![raw_json_response(200, "application/json", "{}")])
        .await
        .expect("server");
    let core = authenticated_core(&server.base_url());

    let accepted = core
        .report_topic_timings(TopicTimingsRequest {
            topic_id: 123,
            topic_time_ms: 15_000,
            timings: vec![
                TopicTimingEntry {
                    post_number: 1,
                    milliseconds: 5_000,
                },
                TopicTimingEntry {
                    post_number: 2,
                    milliseconds: 10_000,
                },
            ],
        })
        .await
        .expect("report timings");
    assert!(accepted);

    let requests = server.shutdown_with_requests().await;
    let request = requests[0].to_ascii_lowercase();
    assert!(request.contains("post /topics/timings"));
    assert!(request.contains("x-csrf-token: csrf-token"));
    assert!(request.contains("x-silence-logger: true"));
    assert!(request.contains("discourse-background: true"));
    assert!(request.contains("topic_id=123"));
    assert!(request.contains("topic_time=15000"));
    assert!(request.contains("timings%5b1%5d=5000"));
    assert!(request.contains("timings%5b2%5d=10000"));
}

#[tokio::test]
async fn report_topic_timings_returns_false_on_429_and_respects_cooldown() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            429,
            "application/json",
            r#"{"errors":"You have performed this action too many times.","extras":{"wait_seconds":0.05}}"#,
        ),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let first = core
        .report_topic_timings(TopicTimingsRequest {
            topic_id: 123,
            topic_time_ms: 15_000,
            timings: vec![TopicTimingEntry {
                post_number: 1,
                milliseconds: 5_000,
            }],
        })
        .await
        .expect("first report");
    assert!(!first);

    let second = core
        .report_topic_timings(TopicTimingsRequest {
            topic_id: 123,
            topic_time_ms: 15_000,
            timings: vec![TopicTimingEntry {
                post_number: 1,
                milliseconds: 5_000,
            }],
        })
        .await
        .expect("cooldown report");
    assert!(!second);

    tokio::time::sleep(Duration::from_millis(70)).await;

    let third = core
        .report_topic_timings(TopicTimingsRequest {
            topic_id: 123,
            topic_time_ms: 15_000,
            timings: vec![TopicTimingEntry {
                post_number: 1,
                milliseconds: 5_000,
            }],
        })
        .await
        .expect("post-cooldown report");
    assert!(third);

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 2);
    assert!(requests[0].contains("POST /topics/timings"));
    assert!(requests[1].contains("POST /topics/timings"));
}

#[tokio::test]
async fn create_bookmark_posts_form_payload() {
    let server = TestServer::spawn(vec![raw_json_response(
        200,
        "application/json",
        r#"{"id": 901}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let bookmark_id = core
        .create_bookmark(
            123,
            "Topic",
            Some("稍后细读"),
            Some("2026-03-29T09:00:00Z"),
            Some(0),
        )
        .await
        .expect("bookmark");
    assert_eq!(bookmark_id, 901);

    let requests = server.shutdown_with_requests().await;
    let request = requests[0].to_ascii_lowercase();
    assert!(request.contains("post /bookmarks.json"));
    assert!(request.contains("x-csrf-token: csrf-token"));
    assert!(request.contains("bookmarkable_id=123"));
    assert!(request.contains("bookmarkable_type=topic"));
    assert!(request.contains("%e7%a8%8d%e5%90%8e%e7%bb%86%e8%af%bb"));
    assert!(request.contains("reminder_at=2026-03-29t09%3a00%3a00z"));
}

#[tokio::test]
async fn update_and_delete_bookmark_and_topic_notification_level_use_expected_endpoints() {
    let server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    core.update_bookmark(
        901,
        Some("新的备注".into()),
        Some("2026-03-30T10:00:00Z".into()),
        Some(1),
    )
    .await
    .expect("update bookmark");
    core.delete_bookmark(901).await.expect("delete bookmark");
    core.set_topic_notification_level(123, 3)
        .await
        .expect("set topic notification level");

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 3);
    assert!(requests[0].contains("PUT /bookmarks/901.json HTTP/1.1"));
    assert!(requests[0].contains("\"name\":\"新的备注\""));
    assert!(requests[0].contains("\"auto_delete_preference\":1"));
    assert!(requests[1].contains("DELETE /bookmarks/901.json HTTP/1.1"));
    let third = requests[2].to_ascii_lowercase();
    assert!(third.contains("post /t/123/notifications"));
    assert!(third.contains("notification_level=3"));
}

#[tokio::test]
async fn draft_apis_parse_payloads_and_handle_sequence_updates() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
              "drafts": [
                {
                  "draft_key": "topic_123_post_2",
                  "data": "{\"reply\":\"hello\",\"replyToPostNumber\":2,\"action\":\"reply\",\"composerTime\":1200}",
                  "draft_sequence": 4,
                  "title": "Fire topic",
                  "excerpt": "hello",
                  "updated_at": "2026-04-11T01:00:00Z",
                  "username": "alice",
                  "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
                }
              ],
              "has_more": false
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "draft": "{\"reply\":\"hello\",\"replyToPostNumber\":2,\"action\":\"reply\",\"composerTime\":1200}",
              "draft_sequence": 6
            }"#,
        ),
        raw_json_response(
            409,
            "application/json",
            r#"{"draft_sequence": 7}"#,
        ),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let list = core.fetch_drafts(Some(0), Some(20)).await.expect("draft list");
    assert_eq!(list.drafts.len(), 1);
    assert_eq!(list.drafts[0].draft_key, "topic_123_post_2");
    assert_eq!(list.drafts[0].data.reply.as_deref(), Some("hello"));
    assert_eq!(list.drafts[0].data.reply_to_post_number, Some(2));
    assert_eq!(list.drafts[0].topic_id, Some(123));

    let draft = core
        .fetch_draft("topic_123_post_2")
        .await
        .expect("draft detail")
        .expect("draft");
    assert_eq!(draft.sequence, 6);
    assert_eq!(draft.data.reply.as_deref(), Some("hello"));

    let sequence = core
        .save_draft(
            "topic_123_post_2",
            DraftData {
                reply: Some("updated".into()),
                reply_to_post_number: Some(2),
                action: Some("reply".into()),
                composer_time: Some(2400),
                ..DraftData::default()
            },
            6,
        )
        .await
        .expect("save draft");
    assert_eq!(sequence, 7);

    core.delete_draft("topic_123_post_2", Some(sequence))
        .await
        .expect("delete draft");

    let requests = server.shutdown_with_requests().await;
    assert!(requests[0].contains("GET /drafts.json?offset=0&limit=20 HTTP/1.1"));
    assert!(requests[1].contains("GET /drafts/topic_123_post_2.json HTTP/1.1"));
    assert!(requests[2].contains("POST /drafts.json HTTP/1.1"));
    assert!(requests[2].contains("draft_key=topic_123_post_2"));
    assert!(requests[2].contains("replyToPostNumber"));
    assert!(requests[3].contains("DELETE /drafts/topic_123_post_2.json?sequence=7 HTTP/1.1"));
}

#[tokio::test]
async fn create_topic_and_upload_surfaces_use_expected_requests() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{"post":{"topic_id":321}}"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "short_url": "upload://fire.png",
              "url": "/uploads/default/original/1X/fire.png",
              "original_filename": "fire.png",
              "width": 1200,
              "height": 800
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"[
              {
                "short_url": "upload://fire.png",
                "short_path": "/uploads/short-url/fire.png",
                "url": "/uploads/default/original/1X/fire.png"
              }
            ]"#,
        ),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let topic_id = core
        .create_topic(TopicCreateRequest {
            title: "Hello Fire".into(),
            raw: "Body".into(),
            category_id: 2,
            tags: vec!["rust".into(), "ios".into()],
        })
        .await
        .expect("create topic");
    assert_eq!(topic_id, 321);

    let upload = core
        .upload_image("fire.png", Some("image/png"), vec![0x89, 0x50, 0x4E, 0x47])
        .await
        .expect("upload image");
    assert_eq!(upload.short_url, "upload://fire.png");

    let resolved = core
        .lookup_upload_urls(vec!["upload://fire.png".into()])
        .await
        .expect("lookup uploads");
    assert_eq!(resolved.len(), 1);
    assert_eq!(
        resolved[0].short_path.as_deref(),
        Some("/uploads/short-url/fire.png")
    );

    let requests = server.shutdown_with_requests().await;
    let create_request = requests[0].to_ascii_lowercase();
    assert!(create_request.contains("post /posts.json"));
    assert!(create_request.contains("title=hello+fire"));
    assert!(create_request.contains("category=2"));
    assert!(create_request.contains("tags%5b%5d=rust"));
    assert!(create_request.contains("tags%5b%5d=ios"));

    let upload_request = requests[1].to_ascii_lowercase();
    assert!(upload_request.contains("post /uploads.json?"));
    assert!(upload_request.contains("client_id="));
    assert!(upload_request.contains("content-type: multipart/form-data; boundary="));
    assert!(upload_request.contains("name=\"upload_type\""));
    assert!(upload_request.contains("name=\"synchronous\""));
    assert!(upload_request.contains("filename=\"fire.png\""));
    assert!(upload_request.contains("content-type: image/png"));

    let lookup_request = &requests[2];
    assert!(lookup_request.contains("POST /uploads/lookup-urls HTTP/1.1"));
    assert!(lookup_request.contains("\"short_urls\":[\"upload://fire.png\"]"));
}

fn authenticated_core(base_url: &str) -> FireCore {
    let core = FireCore::new(FireCoreConfig {
        base_url: base_url.to_string(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_cookies(CookieSnapshot {
        t_token: Some("token".into()),
        forum_session: Some("forum".into()),
        csrf_token: Some("csrf-token".into()),
        ..CookieSnapshot::default()
    });
    core
}
