mod common;

use common::{
    raw_json_response, sample_search_json, sample_tag_search_json, sample_user_mention_json,
    TestServer,
};
use fire_core::{FireCore, FireCoreConfig, FireCoreError};
use fire_models::{SearchQuery, SearchTypeFilter, TagSearchQuery, UserMentionQuery};

#[tokio::test]
async fn search_parses_payload_and_builds_query_parameters() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_search_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search(SearchQuery {
            q: "fire".into(),
            page: Some(2),
            type_filter: Some(SearchTypeFilter::Post),
        })
        .await
        .expect("search");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.posts.len(), 1);
    assert_eq!(response.posts[0].id, 9001);
    assert_eq!(response.posts[0].topic_id, Some(123));
    assert_eq!(response.posts[0].post_number, 1);
    assert_eq!(
        response.posts[0].created_timestamp_unix_ms,
        Some(1_774_656_000_000)
    );
    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].tags, vec!["rust", "linuxdo"]);
    assert_eq!(response.users.len(), 1);
    assert_eq!(response.users[0].username, "alice");
    assert_eq!(response.grouped_result.term, "fire");
    assert!(response.grouped_result.more_posts);
    assert!(response.grouped_result.more_full_page_results);

    let request = requests.first().expect("captured request");
    assert!(request.contains("GET /search.json?q=fire&page=2&type_filter=post HTTP/1.1"));
}

#[tokio::test]
async fn search_coerces_scalar_fields_from_strings() {
    let body = r#"{
  "posts": [
    {
      "id": "9001",
      "username": "alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
      "created_at": "2026-03-28T00:00:00Z",
      "like_count": "3",
      "blurb": "<p>Hello Fire</p>",
      "post_number": "1",
      "topic_id": "123",
      "topic_title_headline": "Fire topic"
    }
  ],
  "topics": [
    {
      "id": "123",
      "title": "Fire topic",
      "slug": "fire-topic",
      "category_id": "2",
      "tags": [{"name": "rust"}, {"slug": "linuxdo"}],
      "posts_count": "12",
      "views": "345",
      "closed": "1",
      "archived": "0"
    }
  ],
  "users": [
    {
      "id": "1",
      "username": "alice",
      "name": "Alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
    }
  ],
  "grouped_search_result": {
    "term": "fire",
    "more_posts": "true",
    "more_users": "0",
    "more_categories": 0,
    "more_full_page_results": "1",
    "search_log_id": "42"
  }
}"#;
    let responses = vec![raw_json_response(200, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search(SearchQuery {
            q: "fire".into(),
            page: Some(1),
            type_filter: None,
        })
        .await
        .expect("search");

    server.shutdown_with_requests().await;

    assert_eq!(response.posts[0].id, 9001);
    assert_eq!(response.posts[0].topic_id, Some(123));
    assert_eq!(response.topics[0].category_id, Some(2));
    assert_eq!(response.topics[0].tags, vec!["rust", "linuxdo"]);
    assert!(response.topics[0].closed);
    assert!(!response.topics[0].archived);
    assert_eq!(response.users[0].id, 1);
    assert!(response.grouped_result.more_posts);
    assert!(!response.grouped_result.more_users);
    assert!(response.grouped_result.more_full_page_results);
    assert_eq!(response.grouped_result.search_log_id, Some(42));
}

#[tokio::test]
async fn search_tags_parses_payload_and_repeats_selected_tags() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_tag_search_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search_tags(TagSearchQuery {
            q: Some("ru".into()),
            filter_for_input: true,
            limit: Some(10),
            category_id: Some(2),
            selected_tags: vec!["rust".into(), "linuxdo".into()],
        })
        .await
        .expect("tag search");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.results.len(), 1);
    assert_eq!(response.results[0].name, "rust");
    assert_eq!(response.results[0].text, "Rust");
    assert_eq!(
        response.required_tag_group.expect("required group").name,
        "platform"
    );

    let request = requests.first().expect("captured request");
    assert!(request.contains("GET /tags/filter/search?"));
    assert!(request.contains("q=ru"));
    assert!(request.contains("filterForInput=true"));
    assert!(request.contains("limit=10"));
    assert!(request.contains("categoryId=2"));
    assert!(request.contains("selected_tags%5B%5D=rust"));
    assert!(request.contains("selected_tags%5B%5D=linuxdo"));
}

#[tokio::test]
async fn search_users_parses_payload_and_builds_query_parameters() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        &sample_user_mention_json(),
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search_users(UserMentionQuery {
            term: "ali".into(),
            include_groups: true,
            limit: 6,
            topic_id: Some(123),
            category_id: Some(2),
        })
        .await
        .expect("user search");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.users.len(), 1);
    assert_eq!(response.users[0].username, "alice");
    assert_eq!(response.groups.len(), 1);
    assert_eq!(response.groups[0].name, "staff");
    assert_eq!(response.groups[0].user_count, Some(3));

    let request = requests.first().expect("captured request");
    assert!(request.contains("GET /u/search/users?term=ali&include_groups=true&limit=6&topic_id=123&category_id=2 HTTP/1.1"));
}

#[tokio::test]
async fn search_tags_coerce_scalar_fields_from_strings() {
    let body = r#"{
  "results": [
    {
      "name": "rust",
      "text": "Rust",
      "count": "100"
    }
  ],
  "required_tag_group": {
    "name": "platform",
    "min_count": "2"
  }
}"#;
    let responses = vec![raw_json_response(200, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search_tags(TagSearchQuery {
            q: Some("ru".into()),
            filter_for_input: true,
            limit: Some(10),
            category_id: Some(2),
            selected_tags: vec!["rust".into()],
        })
        .await
        .expect("tag search");

    server.shutdown_with_requests().await;

    assert_eq!(response.results[0].count, 100);
    assert_eq!(
        response
            .required_tag_group
            .expect("required group")
            .min_count,
        2
    );
}

#[tokio::test]
async fn search_users_coerce_scalar_fields_from_strings() {
    let body = r#"{
  "users": [
    {
      "username": "alice",
      "name": "Alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
      "priority_group": "1"
    }
  ],
  "groups": [
    {
      "name": "staff",
      "full_name": "Staff",
      "flair_url": "/images/flair.png",
      "flair_bg_color": "FFFFFF",
      "flair_color": "000000",
      "user_count": "3"
    }
  ]
}"#;
    let responses = vec![raw_json_response(200, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search_users(UserMentionQuery {
            term: "ali".into(),
            include_groups: true,
            limit: 6,
            topic_id: None,
            category_id: None,
        })
        .await
        .expect("user search");

    server.shutdown_with_requests().await;

    assert_eq!(response.users[0].priority_group, Some(1));
    assert_eq!(response.groups[0].user_count, Some(3));
}

#[tokio::test]
async fn search_returns_deserialize_error_for_missing_grouped_result() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{"posts":[],"topics":[],"users":[]}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .search(SearchQuery {
            q: "fire".into(),
            page: Some(1),
            type_filter: None,
        })
        .await
        .expect_err("search should fail");

    server.shutdown_with_requests().await;

    match error {
        FireCoreError::ResponseDeserialize { operation, source } => {
            assert_eq!(operation, "search");
            assert!(source.to_string().contains("grouped_search_result"));
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[tokio::test]
async fn search_tags_returns_deserialize_error_for_invalid_root_shape() {
    let responses = vec![raw_json_response(200, "application/json", r#"[]"#)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .search_tags(TagSearchQuery {
            q: Some("ru".into()),
            filter_for_input: false,
            limit: None,
            category_id: None,
            selected_tags: vec![],
        })
        .await
        .expect_err("tag search should fail");

    server.shutdown_with_requests().await;

    match error {
        FireCoreError::ResponseDeserialize { operation, source } => {
            assert_eq!(operation, "search tags");
            assert!(source.to_string().contains("tag search response root"));
        }
        other => panic!("unexpected error: {other:?}"),
    }
}

#[tokio::test]
async fn search_users_skips_malformed_group_item() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{"users":[{"username":"alice","priority_group":"1"}],"groups":[1,{"name":"staff","user_count":"3"}]}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search_users(UserMentionQuery {
            term: "ali".into(),
            include_groups: true,
            limit: 6,
            topic_id: None,
            category_id: None,
        })
        .await
        .expect("user search");

    server.shutdown_with_requests().await;

    assert_eq!(response.users.len(), 1);
    assert_eq!(response.users[0].username, "alice");
    assert_eq!(response.groups.len(), 1);
    assert_eq!(response.groups[0].name, "staff");
    assert_eq!(response.groups[0].user_count, Some(3));
}

#[tokio::test]
async fn search_skips_malformed_items() {
    let responses = vec![raw_json_response(
        200,
        "application/json",
        r#"{
  "posts": [1, {"id":"9001","username":"alice","post_number":"1","topic_id":"123"}],
  "topics": [1, {"id":"123","title":"Fire topic","tags":["rust"]}],
  "users": [1, {"id":"1","username":"alice"}],
  "grouped_search_result": {"term":"fire"}
}"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let response = core
        .search(SearchQuery {
            q: "fire".into(),
            page: Some(1),
            type_filter: None,
        })
        .await
        .expect("search");

    server.shutdown_with_requests().await;

    assert_eq!(response.posts.len(), 1);
    assert_eq!(response.posts[0].id, 9001);
    assert_eq!(response.topics.len(), 1);
    assert_eq!(response.topics[0].id, 123);
    assert_eq!(response.users.len(), 1);
    assert_eq!(response.users[0].id, 1);
}
