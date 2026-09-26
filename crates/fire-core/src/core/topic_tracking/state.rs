use fire_models::{
    BootstrapArtifacts, TopicHomeRowCountPatch, TopicListRowPatchBatch, TrackedTopicState,
};
use serde_json::Value;

use super::super::FireCore;
use super::{
    apply_topic_tracking_event, apply_topic_tracking_value, hydrate_topic_tracking_states,
    note_local_topic_read, project_tracking_to_home, FireTopicTrackingRuntime,
};

impl FireCore {
    pub fn clear_topic_tracking_state(&self) {
        let mut runtime = self
            .topic_tracking
            .lock()
            .expect("topic tracking runtime lock poisoned");
        *runtime = FireTopicTrackingRuntime::default();
    }

    pub fn topic_tracking_state(&self, topic_id: u64) -> Option<TrackedTopicState> {
        self.topic_tracking
            .lock()
            .expect("topic tracking runtime lock poisoned")
            .topics
            .get(&topic_id)
            .cloned()
    }

    pub fn note_local_topic_read(
        &self,
        topic_id: u64,
        last_read_post_number: Option<u32>,
        highest_post_number: u32,
    ) -> Option<TopicHomeRowCountPatch> {
        note_local_topic_read(
            &self.topic_tracking,
            topic_id,
            last_read_post_number,
            highest_post_number,
        );
        self.project_and_notify_topic_tracking(topic_id)
    }

    pub fn hydrate_topic_tracking(&self, bootstrap: &BootstrapArtifacts) {
        let auth_scope_hash = self.current_auth_scope_hash();
        let states = hydrate_topic_tracking_states(bootstrap);
        let mut runtime = self
            .topic_tracking
            .lock()
            .expect("topic tracking runtime lock poisoned");
        if runtime.auth_scope_hash != auth_scope_hash {
            runtime.topics.clear();
            runtime.auth_scope_hash = auth_scope_hash;
        }
        if !states.is_empty() {
            runtime.topics = states;
        } else if !bootstrap.has_preloaded_data {
            runtime.topics.clear();
        }
    }

    pub(crate) fn apply_topic_tracking_bus_event(
        &self,
        channel: &str,
        data: &Value,
    ) -> Vec<TopicHomeRowCountPatch> {
        let changed = apply_topic_tracking_event(&self.topic_tracking, channel, data);
        changed
            .into_iter()
            .filter_map(|topic_id| self.project_and_notify_topic_tracking(topic_id))
            .collect()
    }

    pub fn apply_topic_tracking_payload(&self, message_type: &str, payload: &Value) -> Vec<u64> {
        apply_topic_tracking_value(&self.topic_tracking, message_type, payload)
    }

    fn project_and_notify_topic_tracking(&self, topic_id: u64) -> Option<TopicHomeRowCountPatch> {
        let patch = project_tracking_to_home(self, topic_id)?;
        self.patch_cached_home_topic_counts(&patch);
        self.state_observers()
            .notify_topic_list_patches(TopicListRowPatchBatch {
                scope: self.current_home_topic_list_scope(),
                patches: vec![patch.clone()],
            });
        Some(patch)
    }
}
