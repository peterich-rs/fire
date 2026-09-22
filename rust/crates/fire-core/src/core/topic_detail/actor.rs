use std::collections::{HashMap, HashSet};

use fire_models::TopicDetailPhase;
use tokio::sync::mpsc;

use super::super::FireCore;
use super::bus::presence_channel;
use super::*;

impl ActorState {
    pub(super) fn new(topic_id: u64) -> Self {
        Self {
            topic_id,
            owners: HashMap::new(),
            slug_hint: None,
            generation: 0,
            collection_revision: 0,
            chrome_revision: 0,
            sidecar_revision: 0,
            interaction_revision: 0,
            phase: TopicDetailPhase::Loading,
            load_error: None,
            notice: None,
            scroll_target: None,
            scroll_exhausted: false,
            window: TopicWindow {
                requested: 0..0,
                anchor: None,
            },
            scroll_active: false,
            deferred: DeferredRefresh::None,
            defer_publish: false,
            refresh_inflight: false,
            loading_more: false,
            load_more_error: None,
            summary: None,
            summary_loading: false,
            summary_error: None,
            typing_users: Vec::new(),
            submitting: false,
            mutating: HashSet::new(),
            loading_reply_context: HashSet::new(),
            reply_context: None,
            flag_types: Vec::new(),
            rollback: HashMap::new(),
            inflight_posts: HashMap::new(),
            http_epoch: 0,
            visible_generation: 0,
            refresh_generation: 0,
            pending_visible: Vec::new(),
            track_visit: true,
            published: None,
            header: None,
            bus_listener_id: None,
            bus_subscribed: false,
            typing: false,
            alive: true,
        }
    }

    pub(super) async fn handle(
        &mut self,
        core: &FireCore,
        tx: &mpsc::UnboundedSender<Command>,
        command: Command,
    ) -> bool {
        match command {
            Command::Shutdown => {
                self.alive = false;
                return false;
            }
            Command::Flush(reply) => {
                let _ = reply.send(());
            }
            Command::SyncOwners { owners, open } => {
                self.owners = owners;
                if let Some(request) = open {
                    self.slug_hint = request.slug_hint.clone().or(self.slug_hint.clone());
                    self.open(core, tx, request).await;
                }
            }
            Command::CancelHttp => {
                self.http_epoch = self.http_epoch.saturating_add(1);
                self.refresh_inflight = false;
                if self.phase == TopicDetailPhase::Loading
                    && self
                        .published
                        .as_ref()
                        .is_some_and(|snapshot| snapshot.phase == TopicDetailPhase::Ready)
                {
                    self.phase = TopicDetailPhase::Ready;
                    self.load_error = None;
                    self.publish(core, false);
                }
            }
            Command::Reload {
                target_post_number,
                force_load,
                track_visit,
                allow_suggested_unread_root,
            } => {
                self.scroll_target = target_post_number.or(self.scroll_target);
                self.load_http(
                    core,
                    tx,
                    target_post_number,
                    force_load,
                    track_visit,
                    allow_suggested_unread_root,
                    false,
                )
                .await;
            }
            Command::LoginReload { track_visit } => {
                self.load_http(core, tx, None, true, track_visit, false, false)
                    .await;
            }
            Command::LoadMore => {
                self.load_more(core).await;
            }
            Command::NoteVisible(post_numbers) => {
                self.pending_visible = post_numbers;
                self.visible_generation = self.visible_generation.saturating_add(1);
                let generation = self.visible_generation;
                let tx = tx.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(TOPIC_DETAIL_VISIBLE_DEBOUNCE).await;
                    let _ = tx.send(Command::VisibleFired(generation));
                });
            }
            Command::VisibleFired(generation) if generation == self.visible_generation => {
                let posts = self.pending_visible.clone();
                self.hydrate_visible(core, &posts).await;
            }
            Command::VisibleFired(_) => {}
            Command::NoteTail {
                item_count,
                visible_max_item,
            } => {
                if self.should_load_tail(item_count, visible_max_item) {
                    self.load_more(core).await;
                }
            }
            Command::NoteScroll(active) => {
                self.scroll_active = active;
                if !active {
                    match std::mem::replace(&mut self.deferred, DeferredRefresh::None) {
                        DeferredRefresh::Ready(snapshot) => {
                            self.defer_publish = false;
                            self.publish_snapshot(core, *snapshot);
                        }
                        DeferredRefresh::Pending => {
                            self.arm_refresh(tx);
                        }
                        DeferredRefresh::None => {}
                    }
                }
            }
            Command::AckScroll(post_number) => {
                if self.scroll_target == Some(post_number) {
                    self.scroll_target = None;
                    self.publish(core, false);
                }
            }
            Command::ClearScroll => {
                self.scroll_target = None;
                self.scroll_exhausted = false;
                self.publish(core, false);
            }
            Command::BeginTyping => {
                self.typing = true;
                let topic_id = self.topic_id;
                let _ = core
                    .bootstrap_topic_reply_presence(topic_id, self.bus_owner())
                    .await;
                let _ = core.update_topic_reply_presence(topic_id, true).await;
                self.refresh_presence(core);
                let tx = tx.clone();
                tokio::spawn(async move {
                    tokio::time::sleep(TOPIC_DETAIL_PRESENCE_HEARTBEAT).await;
                    let _ = tx.send(Command::PresenceHeartbeat);
                });
            }
            Command::EndTyping => {
                self.typing = false;
                let _ = core.update_topic_reply_presence(self.topic_id, false).await;
                let _ = core.unsubscribe_message_bus_channel(
                    self.bus_owner(),
                    presence_channel(self.topic_id),
                );
                self.refresh_presence(core);
            }
            Command::PresenceHeartbeat => {
                if self.typing {
                    let _ = core.update_topic_reply_presence(self.topic_id, true).await;
                    let tx = tx.clone();
                    tokio::spawn(async move {
                        tokio::time::sleep(TOPIC_DETAIL_PRESENCE_HEARTBEAT).await;
                        let _ = tx.send(Command::PresenceHeartbeat);
                    });
                }
            }
            Command::BusRefresh => {
                if self.scroll_active {
                    if self.refresh_inflight {
                        self.deferred = DeferredRefresh::Pending;
                    } else {
                        self.defer_publish = true;
                        self.load_http(core, tx, None, false, false, false, true)
                            .await;
                    }
                } else {
                    self.arm_refresh(tx);
                }
            }
            Command::RefreshFired(generation) if generation == self.refresh_generation => {
                if self.scroll_active {
                    self.deferred = DeferredRefresh::Pending;
                } else {
                    self.load_http(core, tx, None, false, false, false, true)
                        .await;
                }
            }
            Command::RefreshFired(_) => {}
            Command::BusStarted => {
                self.subscribe_channels(core);
            }
            Command::RefreshPresence => {
                self.refresh_presence(core);
            }
            Command::ReloadAi { skip_age_check } => {
                self.fetch_summary(core, skip_age_check).await;
            }
            Command::LoadReplyContext(post_id) => {
                self.load_reply_context(core, post_id).await;
            }
            Command::PrepareEdit { post_id, reply } => {
                let _ = reply.send(self.prepare_edit(core, post_id).await);
            }
            Command::EnsureFlags { reply } => {
                let _ = reply.send(self.ensure_flags(core).await);
            }
            Command::SubmitReply {
                raw,
                reply_to_post_number,
                scroll_to_created,
                reply,
            } => {
                let _ = reply.send(
                    self.submit_reply(core, tx, raw, reply_to_post_number, scroll_to_created)
                        .await,
                );
            }
            Command::CreateBoost {
                post_id,
                raw,
                reply,
            } => {
                let _ = reply.send(self.create_boost(core, tx, post_id, raw).await);
            }
            Command::DeleteBoost {
                post_id,
                boost_id,
                reply,
            } => {
                let _ = reply.send(self.delete_boost(core, tx, post_id, boost_id).await);
            }
            Command::UpdatePost {
                post_id,
                raw,
                edit_reason,
                reply,
            } => {
                let _ = reply.send(self.update_post(core, tx, post_id, raw, edit_reason).await);
            }
            Command::DeletePost { post_id, reply } => {
                let _ = reply.send(self.delete_post(core, tx, post_id).await);
            }
            Command::RecoverPost { post_id, reply } => {
                let _ = reply.send(self.recover_post(core, tx, post_id).await);
            }
            Command::FlagPost {
                post_id,
                flag_type_id,
                message,
                reply,
            } => {
                let _ = reply.send(
                    self.flag_post(core, tx, post_id, flag_type_id, message)
                        .await,
                );
            }
            Command::SetLiked {
                post_id,
                liked,
                reply,
            } => {
                let _ = reply.send(self.set_liked(core, post_id, liked).await);
            }
            Command::ToggleReaction {
                post_id,
                reaction_id,
                reply,
            } => {
                let _ = reply.send(self.toggle_reaction(core, post_id, reaction_id).await);
            }
            Command::VotePoll {
                post_id,
                poll_name,
                options,
                reply,
            } => {
                let _ = reply.send(self.vote_poll(core, tx, post_id, poll_name, options).await);
            }
            Command::UnvotePoll {
                post_id,
                poll_name,
                reply,
            } => {
                let _ = reply.send(self.unvote_poll(core, tx, post_id, poll_name).await);
            }
            Command::VoteTopic { voted, reply } => {
                let _ = reply.send(self.vote_topic(core, tx, voted).await);
            }
            Command::AcceptSolution {
                post_id,
                accepted,
                reply,
            } => {
                let _ = reply.send(self.accept_solution(core, tx, post_id, accepted).await);
            }
            Command::CreateBookmark {
                bookmarkable_id,
                bookmarkable_type,
                name,
                reminder_at,
                auto_delete_preference,
                reply,
            } => {
                let _ = reply.send(
                    self.create_bookmark(
                        core,
                        tx,
                        bookmarkable_id,
                        bookmarkable_type,
                        name,
                        reminder_at,
                        auto_delete_preference,
                    )
                    .await,
                );
            }
            Command::UpdateBookmark {
                bookmark_id,
                name,
                reminder_at,
                auto_delete_preference,
                reply,
            } => {
                let _ = reply.send(
                    self.update_bookmark(
                        core,
                        tx,
                        bookmark_id,
                        name,
                        reminder_at,
                        auto_delete_preference,
                    )
                    .await,
                );
            }
            Command::DeleteBookmark { bookmark_id, reply } => {
                let _ = reply.send(self.delete_bookmark(core, tx, bookmark_id).await);
            }
            Command::SetNotificationLevel { level, reply } => {
                let _ = reply.send(self.set_notification_level(core, tx, level).await);
            }
            Command::UpdateTopic {
                title,
                category_id,
                tags,
                reply,
            } => {
                let _ = reply.send(self.update_topic(core, tx, title, category_id, tags).await);
            }
            Command::ReportTimings {
                topic_time_ms,
                timings,
                reply,
            } => {
                let result = core
                    .report_topic_timings(fire_models::TopicTimingsRequest {
                        topic_id: self.topic_id,
                        topic_time_ms,
                        timings,
                    })
                    .await
                    .unwrap_or(false);
                let _ = reply.send(Ok(result));
            }
        }
        true
    }
}

pub(super) async fn run_actor(
    core: FireCore,
    topic_id: u64,
    tx: mpsc::UnboundedSender<Command>,
    mut rx: mpsc::UnboundedReceiver<Command>,
) {
    let mut state = ActorState::new(topic_id);
    state.install_bus_listener(&core, tx.clone());
    while let Some(command) = rx.recv().await {
        let keep_running = state.handle(&core, &tx, command).await;
        if !keep_running || !state.alive {
            break;
        }
    }
    state.unsubscribe(&core);
    if let Some(id) = state.bus_listener_id.take() {
        core.remove_message_bus_internal_listener(id);
    }
}
