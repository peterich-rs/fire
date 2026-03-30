#![allow(dead_code)]

use std::{
    env, fs, io,
    net::SocketAddr,
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
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
    <div id="data-discourse-setup" data-preloaded="{&quot;currentUser&quot;:{&quot;username&quot;:&quot;alice&quot;},&quot;siteSettings&quot;:{&quot;long_polling_base_url&quot;:&quot;https://linux.do&quot;,&quot;min_post_length&quot;:20,&quot;discourse_reactions_enabled_reactions&quot;:&quot;heart|clap|tada&quot;},&quot;topicTrackingStateMeta&quot;:{&quot;message_bus_last_id&quot;:42},&quot;site&quot;:{&quot;categories&quot;:[{&quot;id&quot;:2,&quot;name&quot;:&quot;Rust&quot;,&quot;slug&quot;:&quot;rust&quot;,&quot;parent_category_id&quot;:1,&quot;color&quot;:&quot;FFFFFF&quot;,&quot;text_color&quot;:&quot;000000&quot;}]}}"></div>
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

impl TestServer {
    pub(crate) async fn spawn(responses: Vec<String>) -> io::Result<Self> {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        let addr = listener.local_addr()?;
        let requests = Arc::new(AtomicUsize::new(0));
        let captured_requests = Arc::new(Mutex::new(Vec::new()));
        let requests_handle = requests.clone();
        let captured_requests_handle = captured_requests.clone();
        let responses = Arc::new(responses);
        let handle = tokio::spawn(async move {
            for response in responses.iter() {
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
                let _ = stream.write_all(response.as_bytes()).await;
                let _ = stream.shutdown().await;
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
