mod common;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig};
use fire_models::{CookieSnapshot, TopicTimingEntry, TopicTimingsRequest};

#[tokio::test]
async fn report_topic_timings_posts_form_payload_with_background_headers() {
    let server = TestServer::spawn(vec![raw_json_response(200, "application/json", "{}")])
        .await
        .expect("server");
    let core = authenticated_core(&server.base_url());

    core.report_topic_timings(TopicTimingsRequest {
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
