use fire_core::{FireCore, FireCoreConfig};
use fire_models::{BootstrapArtifacts, TopicNotificationLevel};
use serde_json::json;

fn test_core() -> FireCore {
    FireCore::new(FireCoreConfig::default()).expect("core")
}

fn bootstrap_with_states(states: serde_json::Value) -> BootstrapArtifacts {
    let preloaded = json!({
        "topicTrackingStates": states
    });
    BootstrapArtifacts {
        preloaded_json: Some(preloaded.to_string()),
        has_preloaded_data: true,
        ..BootstrapArtifacts::default()
    }
}

#[test]
fn hydrates_preloaded_tracking_states() {
    let core = test_core();
    core.hydrate_topic_tracking(&bootstrap_with_states(json!({
        "11": {
            "topic_id": 11,
            "last_read_post_number": 3,
            "highest_post_number": 8,
            "notification_level": 2
        }
    })));
    let state = core.topic_tracking_state(11).expect("hydrated");
    assert_eq!(state.last_read_post_number, Some(3));
    assert_eq!(state.highest_post_number, 8);
    assert_eq!(state.notification_level, TopicNotificationLevel::Tracking);
    assert!(state.is_unread());
}

#[test]
fn logout_clears_tracking() {
    let core = test_core();
    core.hydrate_topic_tracking(&bootstrap_with_states(json!([
        {
            "topic_id": 22,
            "highest_post_number": 4,
            "created_in_new_period": true
        }
    ])));
    assert!(core.topic_tracking_state(22).is_some());
    let _ = core.logout_local(true);
    assert!(core.topic_tracking_state(22).is_none());
}

#[test]
fn local_read_wins_over_late_unread() {
    let core = test_core();
    core.note_local_topic_read(33, Some(12), 12);
    core.apply_topic_tracking_payload(
        "unread",
        &json!({
            "topic_id": 33,
            "payload": {
                "last_read_post_number": 4,
                "highest_post_number": 9
            }
        }),
    );
    let state = core.topic_tracking_state(33).expect("tracked");
    assert_eq!(state.last_read_post_number, Some(12));
    assert_eq!(state.highest_post_number, 12);
    assert!(!state.is_unread());
}
