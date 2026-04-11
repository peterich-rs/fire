mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{CookieSnapshot, TopicTimingEntry, TopicTimingsRequest};

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
