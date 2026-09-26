use std::collections::HashMap;

use fire_models::{
    apply_chat_new_message_unread, apply_chat_unread, merge_chat_channel_edit, ChatBusEvent,
    ChatChannel, ChatChannelTracking, ChatChannelTrackingEntry, ChatMessage,
    MyChatChannelsResponse,
};

use super::super::FireCore;

#[derive(Debug, Default)]
pub(crate) struct FireChatListRuntime {
    public_channels: Vec<ChatChannel>,
    direct_message_channels: Vec<ChatChannel>,
    tracking: HashMap<u64, ChatChannelTracking>,
    global_bus_last_ids: Vec<fire_models::ChatBusLastIdEntry>,
}

impl FireChatListRuntime {
    fn hydrate(&mut self, response: MyChatChannelsResponse) {
        self.public_channels = response.public_channels;
        self.direct_message_channels = response.direct_message_channels;
        self.tracking = response
            .channel_tracking
            .into_iter()
            .map(|entry| {
                (
                    entry.channel_id,
                    ChatChannelTracking {
                        unread_count: entry.unread_count,
                        mention_count: entry.mention_count,
                    },
                )
            })
            .collect();
        self.global_bus_last_ids = response.global_bus_last_ids;
    }

    fn snapshot(&self) -> MyChatChannelsResponse {
        MyChatChannelsResponse {
            public_channels: self.public_channels.clone(),
            direct_message_channels: self.direct_message_channels.clone(),
            channel_tracking: self
                .tracking
                .iter()
                .map(|(&channel_id, tracking)| ChatChannelTrackingEntry {
                    channel_id,
                    unread_count: tracking.unread_count,
                    mention_count: tracking.mention_count,
                })
                .collect(),
            global_bus_last_ids: self.global_bus_last_ids.clone(),
        }
    }

    fn apply_tracking(
        &mut self,
        channel_id: u64,
        incoming: ChatChannelTracking,
        explicit_mark_read: bool,
    ) {
        let local = self.tracking.get(&channel_id).cloned().unwrap_or_default();
        self.tracking.insert(
            channel_id,
            apply_chat_unread(local, incoming, explicit_mark_read),
        );
    }

    fn apply_new_message(&mut self, channel_id: u64, message: Option<ChatMessage>, is_self: bool) {
        let local = self.tracking.get(&channel_id).cloned().unwrap_or_default();
        self.tracking
            .insert(channel_id, apply_chat_new_message_unread(local, is_self));
        if let Some(message) = message {
            self.set_last_message(channel_id, message);
        }
    }

    fn set_last_message(&mut self, channel_id: u64, message: ChatMessage) {
        for channel in self
            .direct_message_channels
            .iter_mut()
            .chain(self.public_channels.iter_mut())
        {
            if channel.id == channel_id {
                channel.last_message = Some(message);
                return;
            }
        }
    }

    fn upsert_channel(&mut self, channel: ChatChannel) {
        let list = if channel.is_direct_message() {
            &mut self.direct_message_channels
        } else {
            &mut self.public_channels
        };
        if let Some(existing) = list.iter_mut().find(|item| item.id == channel.id) {
            *existing = merge_chat_channel_edit(existing.clone(), &channel);
        } else {
            list.insert(0, channel);
        }
    }

    fn apply_bus_event(&mut self, event: ChatBusEvent, current_user_id: Option<u64>) {
        match event {
            ChatBusEvent::Tracking {
                channel_id,
                unread,
                mention,
                thread_id,
            } if thread_id.is_none() && channel_id > 0 => {
                self.apply_tracking(
                    channel_id,
                    ChatChannelTracking {
                        unread_count: unread,
                        mention_count: mention,
                    },
                    false,
                );
            }
            ChatBusEvent::NewMessages {
                channel_id,
                is_channel_level,
                message,
                actor_id,
            } if is_channel_level && channel_id > 0 => {
                self.apply_new_message(
                    channel_id,
                    message.map(|value| *value),
                    actor_id.is_some_and(|id| Some(id) == current_user_id),
                );
            }
            ChatBusEvent::ChannelUpsert { channel } => {
                self.upsert_channel(*channel);
            }
            ChatBusEvent::MessageUpsert { message } => {
                let channel_id = message.channel_id;
                let is_self = message
                    .user
                    .as_ref()
                    .is_some_and(|user| Some(user.id) == current_user_id);
                self.apply_new_message(channel_id, Some(*message), is_self);
            }
            _ => {}
        }
    }
}

impl FireCore {
    pub(crate) fn hydrate_chat_list(&self, response: &MyChatChannelsResponse) {
        self.chat_list
            .lock()
            .expect("chat list runtime lock poisoned")
            .hydrate(response.clone());
    }

    pub fn chat_list_snapshot(&self) -> Option<MyChatChannelsResponse> {
        let runtime = self
            .chat_list
            .lock()
            .expect("chat list runtime lock poisoned");
        if runtime.public_channels.is_empty() && runtime.direct_message_channels.is_empty() {
            None
        } else {
            Some(runtime.snapshot())
        }
    }

    pub fn apply_chat_list_tracking(
        &self,
        channel_id: u64,
        unread: u32,
        mention: u32,
        explicit_mark_read: bool,
    ) -> MyChatChannelsResponse {
        let mut runtime = self
            .chat_list
            .lock()
            .expect("chat list runtime lock poisoned");
        runtime.apply_tracking(
            channel_id,
            ChatChannelTracking {
                unread_count: unread,
                mention_count: mention,
            },
            explicit_mark_read,
        );
        runtime.snapshot()
    }

    pub fn apply_chat_list_bus_event(&self, event: ChatBusEvent) -> MyChatChannelsResponse {
        let current_user_id = self.snapshot().bootstrap.current_user_id;
        let mut runtime = self
            .chat_list
            .lock()
            .expect("chat list runtime lock poisoned");
        runtime.apply_bus_event(event, current_user_id);
        runtime.snapshot()
    }

    pub fn clear_chat_list_runtime(&self) {
        *self
            .chat_list
            .lock()
            .expect("chat list runtime lock poisoned") = FireChatListRuntime::default();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use fire_models::ChatChannelMembership;

    fn dm(id: u64, muted: bool) -> ChatChannel {
        ChatChannel {
            id,
            chatable_type: "DirectMessage".into(),
            current_user_membership: Some(ChatChannelMembership {
                muted,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    fn public_channel(id: u64, title: &str) -> ChatChannel {
        ChatChannel {
            id,
            title: Some(title.into()),
            chatable_type: "Category".into(),
            current_user_membership: Some(ChatChannelMembership {
                muted: false,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn new_messages_then_smaller_tracking_keeps_high_unread() {
        let mut runtime = FireChatListRuntime::default();
        runtime.hydrate(MyChatChannelsResponse {
            public_channels: vec![],
            direct_message_channels: vec![dm(20, false)],
            channel_tracking: vec![ChatChannelTrackingEntry {
                channel_id: 20,
                unread_count: 1,
                mention_count: 0,
            }],
            global_bus_last_ids: Vec::new(),
        });
        runtime.apply_bus_event(
            ChatBusEvent::NewMessages {
                channel_id: 20,
                is_channel_level: true,
                message: Some(Box::new(ChatMessage {
                    id: 9,
                    channel_id: 20,
                    message: "hi".into(),
                    ..Default::default()
                })),
                actor_id: Some(8),
            },
            Some(1),
        );
        runtime.apply_tracking(
            20,
            ChatChannelTracking {
                unread_count: 1,
                mention_count: 0,
            },
            false,
        );
        let snapshot = runtime.snapshot();
        let unread = snapshot
            .channel_tracking
            .iter()
            .find(|entry| entry.channel_id == 20)
            .expect("channel 20")
            .unread_count;
        assert_eq!(unread, 2);
        assert_eq!(snapshot.total_unread_badge(), 2);
    }

    #[test]
    fn channel_edits_update_title_without_replacing_list() {
        let mut runtime = FireChatListRuntime::default();
        runtime.hydrate(MyChatChannelsResponse {
            public_channels: vec![public_channel(3, "旧标题")],
            direct_message_channels: vec![],
            channel_tracking: Vec::new(),
            global_bus_last_ids: Vec::new(),
        });
        runtime.apply_bus_event(
            ChatBusEvent::ChannelUpsert {
                channel: Box::new(ChatChannel {
                    id: 3,
                    title: Some("新标题".into()),
                    chatable_type: "Category".into(),
                    ..Default::default()
                }),
            },
            None,
        );
        assert_eq!(runtime.public_channels.len(), 1);
        assert_eq!(runtime.public_channels[0].title.as_deref(), Some("新标题"));
    }

    #[test]
    fn muted_channel_does_not_count_in_badge() {
        let mut runtime = FireChatListRuntime::default();
        runtime.hydrate(MyChatChannelsResponse {
            public_channels: vec![],
            direct_message_channels: vec![dm(4, true)],
            channel_tracking: vec![ChatChannelTrackingEntry {
                channel_id: 4,
                unread_count: 12,
                mention_count: 3,
            }],
            global_bus_last_ids: Vec::new(),
        });
        assert_eq!(runtime.snapshot().total_unread_badge(), 0);
    }
}
