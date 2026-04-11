mod common;

use std::time::Duration;

use common::{raw_json_response, TestServer};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{
    CookieSnapshot, DraftData, InviteCreateRequest, PostUpdateRequest, TopicCreateRequest,
    TopicTimingEntry, TopicTimingsRequest, TopicUpdateRequest,
};

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
async fn report_topic_timings_surfaces_login_required_when_server_session_is_invalid() {
    let server = TestServer::spawn(vec![raw_json_response(
        403,
        "application/json",
        r#"{"errors":["您需要登录才能执行此操作。"],"error_type":"not_logged_in"}"#,
    )])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let error = core
        .report_topic_timings(TopicTimingsRequest {
            topic_id: 123,
            topic_time_ms: 15_000,
            timings: vec![TopicTimingEntry {
                post_number: 1,
                milliseconds: 5_000,
            }],
        })
        .await
        .expect_err("login invalidation should surface");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::LoginRequired { message, .. }
            if message == "您需要登录才能执行此操作。"
    ));
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

    let list = core
        .fetch_drafts(Some(0), Some(20))
        .await
        .expect("draft list");
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
async fn stage3_edit_vote_and_poll_surfaces_use_expected_requests() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
              "post": {
                "id": 9001,
                "username": "alice",
                "cooked": "<p>Hello</p>",
                "raw": "Hello",
                "post_number": 1,
                "post_type": 1,
                "created_at": "2026-04-11T00:00:00Z",
                "updated_at": "2026-04-11T00:00:00Z",
                "like_count": 1,
                "reply_count": 0,
                "reactions": [],
                "polls": [],
                "accepted_answer": false,
                "can_edit": true,
                "can_delete": true,
                "can_recover": false,
                "hidden": false
              }
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "post": {
                "id": 9001,
                "username": "alice",
                "cooked": "<p>Updated</p>",
                "raw": "Updated",
                "post_number": 1,
                "post_type": 1,
                "created_at": "2026-04-11T00:00:00Z",
                "updated_at": "2026-04-11T00:10:00Z",
                "like_count": 1,
                "reply_count": 0,
                "reactions": [],
                "polls": [],
                "accepted_answer": false,
                "can_edit": true,
                "can_delete": true,
                "can_recover": false,
                "hidden": false
              }
            }"#,
        ),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "poll": {
                "id": 1,
                "name": "poll",
                "type": "regular",
                "status": "open",
                "results": "always",
                "options": [{"id": "1", "html": "<p>Rust</p>", "votes": 3}],
                "voters": 3
              }
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "poll": {
                "id": 1,
                "name": "poll",
                "type": "regular",
                "status": "open",
                "results": "always",
                "options": [{"id": "1", "html": "<p>Rust</p>", "votes": 2}],
                "voters": 2
              }
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{"can_vote":true,"vote_limit":10,"vote_count":5,"votes_left":4,"alert":false}"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{"can_vote":true,"vote_limit":10,"vote_count":4,"votes_left":5,"alert":false}"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"[{"id":1,"username":"alice","avatar_template":"/user_avatar/linux.do/alice/{size}/1_2.png"}]"#,
        ),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let post = core.fetch_post(9001).await.expect("fetch post");
    assert_eq!(post.raw.as_deref(), Some("Hello"));

    let updated_post = core
        .update_post(PostUpdateRequest {
            post_id: 9001,
            raw: "Updated".into(),
            edit_reason: Some("clarify".into()),
        })
        .await
        .expect("update post");
    assert_eq!(updated_post.raw.as_deref(), Some("Updated"));

    core.update_topic(TopicUpdateRequest {
        topic_id: 123,
        title: "Fire topic".into(),
        category_id: 2,
        tags: vec!["rust".into(), "ios".into()],
    })
    .await
    .expect("update topic");

    let poll = core
        .vote_poll(9001, "poll", vec!["1".into()])
        .await
        .expect("vote poll");
    assert_eq!(poll.options[0].votes, 3);

    let removed_poll = core.unvote_poll(9001, "poll").await.expect("unvote poll");
    assert_eq!(removed_poll.voters, 2);

    let vote_response = core.vote_topic(123).await.expect("vote topic");
    assert_eq!(vote_response.vote_count, 5);

    let unvote_response = core.unvote_topic(123).await.expect("unvote topic");
    assert_eq!(unvote_response.votes_left, 5);

    let voters = core.fetch_topic_voters(123).await.expect("fetch voters");
    assert_eq!(voters.len(), 1);
    assert_eq!(voters[0].username, "alice");

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 8);
    assert!(requests[0].contains("GET /posts/9001.json HTTP/1.1"));
    assert!(requests[1].contains("PUT /posts/9001.json HTTP/1.1"));
    assert!(requests[1].contains("post%5Braw%5D=Updated"));
    assert!(requests[1].contains("post%5Bedit_reason%5D=clarify"));
    assert!(requests[2].contains("PUT /t/-/123.json HTTP/1.1"));
    assert!(requests[2].contains("title=Fire+topic"));
    assert!(requests[2].contains("category_id=2"));
    assert!(requests[2].contains("tags%5B%5D=rust"));
    assert!(requests[2].contains("tags%5B%5D=ios"));
    assert!(requests[3].contains("PUT /polls/vote HTTP/1.1"));
    assert!(requests[3].contains("post_id=9001"));
    assert!(requests[3].contains("poll_name=poll"));
    assert!(requests[3].contains("options%5B%5D=1"));
    assert!(requests[4].contains("DELETE /polls/vote HTTP/1.1"));
    assert!(requests[5].contains("POST /voting/vote HTTP/1.1"));
    assert!(requests[5].contains("topic_id=123"));
    assert!(requests[6].contains("POST /voting/unvote HTTP/1.1"));
    assert!(requests[7].contains("GET /voting/who?topic_id=123 HTTP/1.1"));
}

#[tokio::test]
async fn vote_endpoints_skip_malformed_voter_items() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{"can_vote":true,"who_voted":[1,{"id":"1","username":"alice","avatar_template":"/user_avatar/linux.do/alice/{size}/1_2.png"}]}"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"[1,{"id":"2","username":"bob","avatar_template":"/user_avatar/linux.do/bob/{size}/1_2.png"}]"#,
        ),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let vote_response = core.vote_topic(123).await.expect("vote topic");
    let voters = core.fetch_topic_voters(123).await.expect("fetch voters");

    let _ = server.shutdown().await;
    assert_eq!(vote_response.who_voted.len(), 1);
    assert_eq!(vote_response.who_voted[0].username, "alice");
    assert_eq!(voters.len(), 1);
    assert_eq!(voters[0].username, "bob");
}

#[tokio::test]
async fn stage3_history_follow_and_invite_surfaces_parse_payloads() {
    let server = TestServer::spawn(vec![
        raw_json_response(
            200,
            "application/json",
            r#"{
              "topic_list": {
                "topics": [{
                  "id": 123,
                  "title": "History topic",
                  "slug": "history-topic",
                  "posts_count": 2,
                  "reply_count": 1,
                  "views": 10,
                  "like_count": 1,
                  "category_id": 2,
                  "created_at": "2026-04-11T00:00:00Z",
                  "last_posted_at": "2026-04-11T00:10:00Z",
                  "posters": [],
                  "tags": []
                }],
                "more_topics_url": "/read?page=2"
              },
              "users": []
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"[{"id":1,"username":"alice","name":"Alice","avatar_template":"/user_avatar/linux.do/alice/{size}/1_2.png"}]"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{
              "pending_invites": [{
                "invite_url": "https://linux.do/invites/fire",
                "invite": {
                  "id": 9,
                  "invite_key": "fire",
                  "max_redemptions_allowed": 5,
                  "redemption_count": 1,
                  "expired": false
                }
              }]
            }"#,
        ),
        raw_json_response(
            200,
            "application/json",
            r#"{"invite_key":"fresh","max_redemptions_allowed":3,"redemption_count":0}"#,
        ),
        raw_json_response(200, "application/json", "{}"),
        raw_json_response(200, "application/json", "{}"),
    ])
    .await
    .expect("server");
    let core = authenticated_core(&server.base_url());

    let history = core
        .fetch_read_history(Some(2))
        .await
        .expect("read history");
    assert_eq!(history.topics.len(), 1);
    assert_eq!(history.next_page, Some(2));

    let following = core.fetch_following("alice").await.expect("following");
    assert_eq!(following[0].username, "alice");

    let invites = core
        .fetch_pending_invites("alice")
        .await
        .expect("pending invites");
    assert_eq!(invites[0].invite_link, "https://linux.do/invites/fire");

    let created = core
        .create_invite_link(InviteCreateRequest {
            max_redemptions_allowed: 3,
            expires_at: None,
            description: Some("beta".into()),
            email: None,
        })
        .await
        .expect("create invite");
    assert_eq!(
        created
            .invite
            .as_ref()
            .and_then(|invite| invite.invite_key.as_deref()),
        Some("fresh")
    );

    core.follow_user("bob").await.expect("follow user");
    core.unfollow_user("bob").await.expect("unfollow user");

    let requests = server.shutdown_with_requests().await;
    assert_eq!(requests.len(), 6);
    assert!(requests[0].contains("GET /read.json?page=2 HTTP/1.1"));
    assert!(requests[1].contains("GET /u/alice/follow/following HTTP/1.1"));
    assert!(requests[2].contains("GET /u/alice/invited/pending HTTP/1.1"));
    assert!(requests[3].contains("POST /invites HTTP/1.1"));
    assert!(requests[3].contains("\"max_redemptions_allowed\":3"));
    assert!(requests[4].contains("PUT /follow/bob HTTP/1.1"));
    assert!(requests[5].contains("DELETE /follow/bob HTTP/1.1"));
}

#[tokio::test]
async fn create_topic_and_upload_surfaces_use_expected_requests() {
    let server = TestServer::spawn(vec![
        raw_json_response(200, "application/json", r#"{"post":{"topic_id":321}}"#),
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
    let create_request = requests
        .iter()
        .find(|request| request.to_ascii_lowercase().contains("/posts.json"))
        .expect("create topic request")
        .to_ascii_lowercase();
    assert!(create_request.contains("post /posts.json"));
    assert!(create_request.contains("title=hello+fire"));
    assert!(create_request.contains("category=2"));
    assert!(create_request.contains("tags%5b%5d=rust"));
    assert!(create_request.contains("tags%5b%5d=ios"));

    let lookup_request = requests
        .iter()
        .find(|request| request.contains("/uploads/lookup-urls"))
        .expect("lookup upload urls request");
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
