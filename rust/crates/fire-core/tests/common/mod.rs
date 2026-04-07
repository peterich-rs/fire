#![allow(dead_code)]

use std::{
    env, fs, io,
    net::SocketAddr,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::TcpListener,
    task::JoinHandle,
};

pub(crate) fn sample_home_html() -> String {
    r#"
<!doctype html>
<html>
  <head>
    <meta name="csrf-token" content="csrf-token">
    <meta name="shared_session_key" content="shared-session">
    <meta name="current-username" content="alice">
    <meta name="discourse-base-uri" content="/">
  </head>
  <body>
    <div data-sitekey="turnstile-key"></div>
    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;id&quot;:1,&quot;username&quot;:&quot;alice&quot;,&quot;notification_channel_position&quot;:42},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://linux.do&quot;,&quot;min_post_length&quot;:20,&quot;discourse_reactions_enabled_reactions&quot;:&quot;heart|clap|tada&quot;},&quot;topicTrackingStateMeta&quot;:{&quot;message_bus_last_id&quot;:42},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:2,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;,&quot;parent_category_id&quot;:1,&quot;color&quot;:&quot;FFFFFF&quot;,&quot;text_color&quot;:&quot;000000&quot;}],&quot;top_tags&quot;:[{&quot;name&quot;:&quot;swift&quot;},&quot;rust&quot;],&quot;can_tag_topics&quot;:true}}"></div>
  </body>
</html>
"#
    .to_string()
}

pub(crate) fn sample_latest_json() -> String {
    r#"{
  "topic_list": {
    "topics": [
      {
        "id": 123,
        "title": "Fire topic",
        "slug": "fire-topic",
        "posts_count": 12,
        "reply_count": 11,
        "views": 345,
        "like_count": 21,
        "excerpt": "topic excerpt",
        "created_at": "2026-03-28T00:00:00Z",
        "last_posted_at": "2026-03-28T01:00:00Z",
        "last_poster_username": "alice",
        "category_id": 2,
        "pinned": false,
        "visible": true,
        "closed": false,
        "archived": false,
        "tags": ["rust", "linuxdo"],
        "posters": [
          {
            "user_id": 1,
            "description": "Original Poster",
            "extras": "latest"
          }
        ],
        "unseen": false,
        "unread_posts": 2,
        "new_posts": 1,
        "last_read_post_number": 10,
        "highest_post_number": 12,
        "has_accepted_answer": false,
        "can_have_answer": true
      }
    ],
    "more_topics_url": "/latest?page=1"
  },
  "users": [
    {
      "id": 1,
      "username": "alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
    }
  ]
}"#
    .to_string()
}

pub(crate) fn sample_topic_detail_json() -> String {
    r#"{
  "id": 123,
  "title": "Fire topic",
  "slug": "fire-topic",
  "posts_count": 12,
  "category_id": 2,
  "tags": ["rust", "linuxdo"],
  "views": 345,
  "like_count": 21,
  "created_at": "2026-03-28T00:00:00Z",
  "last_read_post_number": 10,
  "bookmarks": [],
  "accepted_answer": false,
  "has_accepted_answer": false,
  "can_vote": false,
  "vote_count": 0,
  "user_voted": false,
  "summarizable": true,
  "has_cached_summary": false,
  "has_summary": false,
  "archetype": "regular",
  "post_stream": {
    "posts": [
      {
        "id": 9001,
        "username": "alice",
        "name": "Alice",
        "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
        "cooked": "<p>Hello Fire</p>",
        "post_number": 1,
        "post_type": 1,
        "created_at": "2026-03-28T00:00:00Z",
        "updated_at": "2026-03-28T00:00:00Z",
        "like_count": 3,
        "reply_count": 0,
        "reply_to_post_number": null,
        "bookmarked": false,
        "bookmark_id": null,
        "reactions": [
          {
            "id": "heart",
            "type": "emoji",
            "count": 3
          }
        ],
        "current_user_reaction": null,
        "accepted_answer": false,
        "can_edit": true,
        "can_delete": true,
        "can_recover": false,
        "hidden": false
      }
    ],
    "stream": [9001]
  },
  "details": {
    "notification_level": 1,
    "can_edit": true,
    "created_by": {
      "id": 1,
      "username": "alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
    }
  }
}"#
    .to_string()
}

pub(crate) fn sample_search_json() -> String {
    r#"{
  "posts": [
    {
      "id": 9001,
      "username": "alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
      "created_at": "2026-03-28T00:00:00Z",
      "like_count": 3,
      "blurb": "<p>Hello Fire</p>",
      "post_number": 1,
      "topic_id": 123,
      "topic_title_headline": "Fire topic"
    }
  ],
  "topics": [
    {
      "id": 123,
      "title": "Fire topic",
      "slug": "fire-topic",
      "category_id": 2,
      "tags": ["rust", "linuxdo"],
      "posts_count": 12,
      "views": 345,
      "closed": false,
      "archived": false
    }
  ],
  "users": [
    {
      "id": 1,
      "username": "alice",
      "name": "Alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png"
    }
  ],
  "grouped_search_result": {
    "term": "fire",
    "more_posts": true,
    "more_users": false,
    "more_categories": false,
    "more_full_page_results": true,
    "search_log_id": 42
  }
}"#
    .to_string()
}

pub(crate) fn sample_tag_search_json() -> String {
    r#"{
  "results": [
    {
      "name": "rust",
      "text": "Rust",
      "count": 100
    }
  ],
  "required_tag_group": {
    "name": "platform",
    "min_count": 1
  }
}"#
    .to_string()
}

pub(crate) fn sample_user_mention_json() -> String {
    r#"{
  "users": [
    {
      "username": "alice",
      "name": "Alice",
      "avatar_template": "/user_avatar/linux.do/alice/{size}/1_2.png",
      "priority_group": 1
    }
  ],
  "groups": [
    {
      "name": "staff",
      "full_name": "Staff",
      "flair_url": "/images/flair.png",
      "flair_bg_color": "FFFFFF",
      "flair_color": "000000",
      "user_count": 3
    }
  ]
}"#
    .to_string()
}

pub(crate) fn raw_json_response(status: u16, content_type: &str, body: &str) -> String {
    format!(
        "HTTP/1.1 {status} TEST\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )
}

pub(crate) fn raw_text_response(status: u16, body: &str) -> String {
    raw_json_response(status, "application/json", body)
}

pub(crate) struct TestServer {
    addr: SocketAddr,
    requests: Arc<AtomicUsize>,
    captured_requests: Arc<Mutex<Vec<String>>>,
    handle: JoinHandle<()>,
}

#[derive(Clone)]
pub(crate) struct TestServerStep {
    response: String,
    delay_before_write: Duration,
}

impl TestServerStep {
    pub(crate) fn immediate(response: String) -> Self {
        Self {
            response,
            delay_before_write: Duration::ZERO,
        }
    }

    pub(crate) fn delayed(response: String, delay_before_write: Duration) -> Self {
        Self {
            response,
            delay_before_write,
        }
    }
}

impl TestServer {
    pub(crate) async fn spawn(responses: Vec<String>) -> io::Result<Self> {
        let steps = responses
            .into_iter()
            .map(TestServerStep::immediate)
            .collect::<Vec<_>>();
        Self::spawn_scripted(steps).await
    }

    pub(crate) async fn spawn_scripted(steps: Vec<TestServerStep>) -> io::Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let addr = listener.local_addr()?;
        let requests = Arc::new(AtomicUsize::new(0));
        let captured_requests = Arc::new(Mutex::new(Vec::new()));
        let requests_handle = requests.clone();
        let captured_requests_handle = captured_requests.clone();
        let handle = tokio::spawn(async move {
            let mut writers = Vec::new();
            for step in steps {
                let Ok((mut stream, _)) = listener.accept().await else {
                    return;
                };
                let mut buffer = vec![0_u8; 16_384];
                let bytes_read = stream.read(&mut buffer).await.unwrap_or_default();
                requests_handle.fetch_add(1, Ordering::SeqCst);
                if let Ok(request) = String::from_utf8(buffer[..bytes_read].to_vec()) {
                    if let Ok(mut captured_requests) = captured_requests_handle.lock() {
                        captured_requests.push(request);
                    }
                }
                writers.push(tokio::spawn(async move {
                    if !step.delay_before_write.is_zero() {
                        tokio::time::sleep(step.delay_before_write).await;
                    }
                    let _ = stream.write_all(step.response.as_bytes()).await;
                    let _ = stream.shutdown().await;
                }));
            }

            for writer in writers {
                let _ = writer.await;
            }
        });

        Ok(Self {
            addr,
            requests,
            captured_requests,
            handle,
        })
    }

    pub(crate) fn base_url(&self) -> String {
        format!("http://{}", self.addr)
    }

    pub(crate) async fn shutdown(self) -> Arc<AtomicUsize> {
        let _ = self.handle.await;
        self.requests
    }

    pub(crate) async fn shutdown_with_requests(self) -> Vec<String> {
        let _ = self.handle.await;
        self.captured_requests
            .lock()
            .map(|requests| requests.clone())
            .unwrap_or_default()
    }
}

pub(crate) fn temp_session_file(name: &str) -> PathBuf {
    let mut path = env::temp_dir();
    path.push(format!("fire-tests-{}", std::process::id()));
    fs::create_dir_all(&path).expect("temp dir");
    path.push(name);
    path
}

pub(crate) fn temp_workspace_dir(name: &str) -> PathBuf {
    let mut path = env::temp_dir();
    path.push(format!("fire-tests-{}", std::process::id()));
    path.push(name);
    fs::create_dir_all(&path).expect("temp workspace dir");
    path
}
