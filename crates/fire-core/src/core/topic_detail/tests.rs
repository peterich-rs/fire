use std::sync::{Arc, Mutex as StdMutex};

use fire_models::{TopicDetailUiSnapshot, TopicHeader, TopicPost};

use super::super::FireCore;
use super::{TopicDetailObserver, TopicDetailOpenRequest};
use crate::config::FireCoreConfig;

struct RecordingObserver {
    snapshots: StdMutex<Vec<TopicDetailUiSnapshot>>,
}

impl TopicDetailObserver for RecordingObserver {
    fn on_snapshot(&self, snapshot: TopicDetailUiSnapshot) {
        self.snapshots.lock().expect("observer").push(snapshot);
    }
}

fn test_core() -> FireCore {
    FireCore::new(FireCoreConfig::default()).expect("core")
}

fn seed(core: &FireCore) {
    let body = TopicPost {
        id: 1,
        username: "alice".into(),
        cooked: "<p>op</p>".into(),
        post_number: 1,
        ..TopicPost::default()
    };
    core.seed_topic_detail_source_for_test(
        TopicHeader {
            topic_id: 42,
            title: "topic".into(),
            slug: "topic".into(),
            posts_count: 1,
            ..TopicHeader::default()
        },
        body,
        Vec::new(),
        vec![1],
    );
}

fn open_request(owner: &str) -> TopicDetailOpenRequest {
    TopicDetailOpenRequest {
        topic_id: 42,
        owner_token: owner.into(),
        slug_hint: None,
        target_post_number: None,
        bypass_cache: false,
        force_load: false,
        track_visit: false,
        allow_suggested_unread_root: false,
    }
}

#[tokio::test]
async fn same_owner_reopen_replaces_observer_and_release_keeps_the_other() {
    let core = test_core();
    seed(&core);
    let first = Arc::new(RecordingObserver {
        snapshots: StdMutex::new(Vec::new()),
    });
    let second = Arc::new(RecordingObserver {
        snapshots: StdMutex::new(Vec::new()),
    });
    let third = Arc::new(RecordingObserver {
        snapshots: StdMutex::new(Vec::new()),
    });
    let session = core.topic_detail_sessions.open(
        &core,
        open_request("owner-a"),
        first.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    let first_count = first.snapshots.lock().expect("first").len();
    assert!(first_count >= 1);

    core.topic_detail_sessions.open(
        &core,
        open_request("owner-a"),
        second.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    let first_after_replace = first.snapshots.lock().expect("first").len();
    assert!(!second.snapshots.lock().expect("second").is_empty());

    core.topic_detail_sessions.open(
        &core,
        open_request("owner-b"),
        third.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    assert_eq!(core.topic_detail_sessions.session_count(), 1);

    core.topic_detail_sessions.release(42, "owner-a");
    session.sync_for_test().await;
    assert_eq!(core.topic_detail_sessions.session_count(), 1);
    let third_before = third.snapshots.lock().expect("third").len();
    session.clear_scroll_target();
    session.sync_for_test().await;
    assert!(third.snapshots.lock().expect("third").len() > third_before);
    assert_eq!(
        first.snapshots.lock().expect("first").len(),
        first_after_replace
    );

    core.topic_detail_sessions.release(42, "owner-b");
    session.sync_for_test().await;
    assert_eq!(core.topic_detail_sessions.session_count(), 0);
}
