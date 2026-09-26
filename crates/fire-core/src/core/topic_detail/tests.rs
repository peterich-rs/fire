use std::sync::{Arc, Mutex as StdMutex};

use fire_models::{TopicDetailSnapshotChange, TopicDetailUiSnapshot, TopicHeader, TopicPost};
use tokio::sync::mpsc;

use super::super::FireCore;
use super::project::{
    apply_change, snapshot_change,
    test_support::{post, snapshot},
};
use super::{
    ActorState, TopicDetailObserver, TopicDetailOpenRequest, TOPIC_DETAIL_DEFER_PUBLISH_TIMEOUT,
};
use crate::config::FireCoreConfig;

#[derive(Default)]
struct RecordingObserver {
    snapshots: StdMutex<Vec<TopicDetailUiSnapshot>>,
}

impl RecordingObserver {
    fn count(&self) -> usize {
        self.snapshots.lock().expect("observer").len()
    }

    fn last_generation(&self) -> u64 {
        self.snapshots
            .lock()
            .expect("observer")
            .last()
            .map(|snapshot| snapshot.generation)
            .unwrap_or_default()
    }
}

impl TopicDetailObserver for RecordingObserver {
    fn on_change(&self, change: &TopicDetailSnapshotChange) {
        self.snapshots
            .lock()
            .expect("observer")
            .push(change.snapshot.as_ref().clone());
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
    session.set_submitting_for_test(true);
    session.sync_for_test().await;
    assert!(!second.snapshots.lock().expect("second").is_empty());
    assert_eq!(
        first.snapshots.lock().expect("first").len(),
        first_after_replace
    );

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
    session.set_submitting_for_test(false);
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

#[tokio::test(start_paused = true)]
async fn scroll_defers_publish_and_scroll_end_publishes_a_fresh_generation() {
    let core = test_core();
    seed(&core);
    let observer = Arc::new(RecordingObserver::default());
    let session = core.topic_detail_sessions.open(
        &core,
        open_request("owner-a"),
        observer.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    let count = observer.count();
    let generation = observer.last_generation();

    session.note_scroll_interaction(true);
    session.set_submitting_for_test(true);
    session.set_submitting_for_test(true);
    session.sync_for_test().await;
    assert_eq!(observer.count(), count);

    session.note_scroll_interaction(false);
    session.sync_for_test().await;
    assert_eq!(observer.count(), count + 1);
    assert!(observer.last_generation() > generation);
}

#[tokio::test(start_paused = true)]
async fn deferred_publish_fires_after_timeout_while_still_scrolling() {
    let core = test_core();
    seed(&core);
    let observer = Arc::new(RecordingObserver::default());
    let session = core.topic_detail_sessions.open(
        &core,
        open_request("owner-a"),
        observer.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    let count = observer.count();

    session.note_scroll_interaction(true);
    session.set_submitting_for_test(true);
    session.sync_for_test().await;
    assert_eq!(observer.count(), count);

    tokio::time::advance(TOPIC_DETAIL_DEFER_PUBLISH_TIMEOUT * 2).await;
    session.sync_for_test().await;
    assert_eq!(observer.count(), count + 1);

    session.note_scroll_interaction(false);
    session.sync_for_test().await;
    assert_eq!(observer.count(), count + 1);
}

#[tokio::test]
async fn revisions_track_their_own_region() {
    let (tx, _rx) = mpsc::unbounded_channel();
    let mut state = ActorState::new(42, tx);
    let posts = [post(1, None), post(2, Some(1))];
    let mut first = snapshot(&posts);
    state.assign_revisions(&mut first);
    state.published = Some(Arc::new(first.clone()));

    let mut typing = first.clone();
    typing.composer.is_submitting = true;
    state.assign_revisions(&mut typing);
    assert!(typing.composer_revision > first.composer_revision);
    assert_eq!(typing.interaction_revision, first.interaction_revision);
    assert_eq!(typing.collection_revision, first.collection_revision);
    state.published = Some(Arc::new(typing.clone()));

    let mut voted = posts.clone();
    voted[1].polls = vec![fire_models::Poll {
        id: 7,
        name: "poll".into(),
        voters: 1,
        ..fire_models::Poll::default()
    }];
    let mut poll = snapshot(&voted);
    poll.composer = typing.composer.clone();
    state.assign_revisions(&mut poll);
    assert!(poll.interaction_revision > typing.interaction_revision);
    assert_eq!(poll.collection_revision, typing.collection_revision);
    assert_eq!(poll.composer_revision, typing.composer_revision);
}

#[tokio::test]
async fn empty_publish_does_not_cross_owners() {
    let core = test_core();
    seed(&core);
    let observer = Arc::new(RecordingObserver::default());
    let session = core.topic_detail_sessions.open(
        &core,
        open_request("owner-a"),
        observer.clone() as Arc<dyn TopicDetailObserver>,
    );
    session.sync_for_test().await;
    let count = observer.count();
    let generation = observer.last_generation();

    session.clear_scroll_target();
    session.set_submitting_for_test(false);
    session.sync_for_test().await;
    assert_eq!(observer.count(), count);
    assert_eq!(observer.last_generation(), generation);
}

#[test]
fn incremental_fold_matches_published_snapshot() {
    let first = snapshot(&[post(1, None), post(2, Some(1))]);
    let mut liked = [post(1, None), post(2, Some(1))];
    liked[1].like_count = 5;
    let second = snapshot(&liked);
    let change = snapshot_change(
        Arc::new({
            let mut stamped = second.clone();
            stamped.generation = 2;
            stamped
        }),
        Some(1),
        super::project::diff_snapshots(Some(&first), None, &second).expect("liked"),
    );
    let mut baseline = first;
    baseline.generation = 1;
    let applied = apply_change(Some(baseline), &change);
    assert_eq!(applied.rows[1].like_count, 5);
    assert_eq!(applied.rows.len(), 2);
}
