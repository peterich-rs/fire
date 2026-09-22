use tokio::sync::mpsc;

use super::super::FireCore;
use super::*;
use crate::error::FireCoreError;

impl ActorState {
    pub(super) async fn set_liked(
        &mut self,
        core: &FireCore,
        post_id: u64,
        liked: bool,
    ) -> Result<(), FireCoreError> {
        let desired = liked.then(|| HEART_REACTION_ID.to_string());
        self.apply_optimistic_reaction(core, post_id, desired);
        let result = if liked {
            core.like_post(post_id).await
        } else {
            core.unlike_post(post_id).await
        };
        match result {
            Ok(Some(update)) => {
                self.apply_reaction_update(core, post_id, &update);
                Ok(())
            }
            Ok(None) => {
                self.clear_mutation(core, post_id, false);
                self.load_http(
                    core,
                    &mpsc::unbounded_channel().0,
                    None,
                    false,
                    false,
                    false,
                    false,
                )
                .await;
                Ok(())
            }
            Err(error) => {
                self.clear_mutation(core, post_id, true);
                Err(error)
            }
        }
    }

    pub(super) async fn toggle_reaction(
        &mut self,
        core: &FireCore,
        post_id: u64,
        reaction_id: String,
    ) -> Result<(), FireCoreError> {
        let current = core.with_topic_source_session_mut(self.topic_id, None, |session| {
            session.post(post_id).and_then(|post| {
                post.current_user_reaction
                    .as_ref()
                    .map(|reaction| reaction.id.clone())
            })
        });
        let desired = match current.flatten() {
            Some(current) if current == reaction_id => None,
            _ => Some(reaction_id.clone()),
        };
        self.apply_optimistic_reaction(core, post_id, desired);
        match core.toggle_post_reaction(post_id, reaction_id).await {
            Ok(update) => {
                self.apply_reaction_update(core, post_id, &update);
                Ok(())
            }
            Err(error) => {
                self.clear_mutation(core, post_id, true);
                Err(error)
            }
        }
    }

    pub(super) fn apply_optimistic_reaction(
        &mut self,
        core: &FireCore,
        post_id: u64,
        desired: Option<String>,
    ) {
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            let Some(post) = session.post(post_id).cloned() else {
                return;
            };
            self.rollback.insert(post_id, post.clone());
            let mut updated = post;
            let current = updated
                .current_user_reaction
                .as_ref()
                .map(|reaction| reaction.id.clone());
            if current == desired {
                self.inflight_posts.insert(post_id, updated);
                return;
            }
            adjust_reaction_count(&mut updated.reactions, current.as_deref(), -1);
            if let Some(desired_id) = desired.clone() {
                adjust_reaction_count(&mut updated.reactions, Some(&desired_id), 1);
                updated.current_user_reaction = Some(fire_models::TopicReaction {
                    id: desired_id,
                    kind: None,
                    count: 1,
                    can_undo: Some(true),
                });
            } else {
                updated.current_user_reaction = None;
            }
            updated.like_count = updated
                .reactions
                .iter()
                .find(|reaction| reaction.id == HEART_REACTION_ID)
                .map(|reaction| reaction.count)
                .unwrap_or(0);
            self.inflight_posts.insert(post_id, updated.clone());
            session.merge_posts(std::iter::once(updated));
        });
        self.mutating.insert(post_id);
        self.publish(core, false);
    }

    pub(super) fn apply_reaction_update(
        &mut self,
        core: &FireCore,
        post_id: u64,
        update: &fire_models::PostReactionUpdate,
    ) {
        core.with_topic_source_session_mut(self.topic_id, None, |session| {
            if let Some(post) = session.post_mut(post_id) {
                post.reactions = update.reactions.clone();
                post.current_user_reaction = update.current_user_reaction.clone();
                post.like_count = post
                    .reactions
                    .iter()
                    .find(|reaction| reaction.id == HEART_REACTION_ID)
                    .map(|reaction| reaction.count)
                    .unwrap_or(0);
            }
        });
        self.clear_mutation(core, post_id, false);
    }

    pub(super) fn clear_mutation(&mut self, core: &FireCore, post_id: u64, rollback: bool) {
        if rollback {
            if let Some(post) = self.rollback.remove(&post_id) {
                core.with_topic_source_session_mut(self.topic_id, None, |session| {
                    session.merge_posts(std::iter::once(post));
                });
            }
        } else {
            self.rollback.remove(&post_id);
        }
        self.inflight_posts.remove(&post_id);
        self.mutating.remove(&post_id);
        self.publish(core, false);
    }
}

fn adjust_reaction_count(
    reactions: &mut Vec<fire_models::TopicReaction>,
    id: Option<&str>,
    delta: i32,
) {
    let Some(id) = id else {
        return;
    };
    if let Some(index) = reactions.iter().position(|reaction| reaction.id == id) {
        let next = reactions[index].count as i32 + delta;
        if next <= 0 {
            reactions.remove(index);
        } else {
            reactions[index].count = next as u32;
        }
    } else if delta > 0 {
        reactions.push(fire_models::TopicReaction {
            id: id.to_string(),
            kind: None,
            count: delta as u32,
            can_undo: Some(true),
        });
    }
}
