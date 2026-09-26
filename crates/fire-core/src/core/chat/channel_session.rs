use std::collections::HashMap;

use fire_models::{apply_chat_channel_bus_event, ChatBusEvent, ChatMessage, ChatMessagesResponse};

use super::super::FireCore;

#[derive(Debug, Clone, Default)]
pub struct ChatChannelRuntimeSnapshot {
    pub messages: Vec<ChatMessage>,
    pub pins: Vec<ChatMessage>,
    pub can_load_more_past: bool,
}

#[derive(Debug, Default)]
struct ChannelSlot {
    messages: Vec<ChatMessage>,
    pins: Vec<ChatMessage>,
    can_load_more_past: bool,
}

impl ChannelSlot {
    fn snapshot(&self) -> ChatChannelRuntimeSnapshot {
        ChatChannelRuntimeSnapshot {
            messages: self.messages.clone(),
            pins: self.pins.clone(),
            can_load_more_past: self.can_load_more_past,
        }
    }
}

#[derive(Debug, Default)]
pub(crate) struct FireChatChannelRuntime {
    slots: HashMap<(u64, u64), ChannelSlot>,
}

fn slot_key(channel_id: u64, thread_id: Option<u64>) -> (u64, u64) {
    (channel_id, thread_id.unwrap_or(0))
}

impl FireChatChannelRuntime {
    fn slot(&mut self, channel_id: u64, thread_id: Option<u64>) -> &mut ChannelSlot {
        self.slots
            .entry(slot_key(channel_id, thread_id))
            .or_default()
    }

    fn snapshot(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
    ) -> Option<ChatChannelRuntimeSnapshot> {
        self.slots
            .get(&slot_key(channel_id, thread_id))
            .map(ChannelSlot::snapshot)
    }
}

impl FireCore {
    pub fn chat_channel_runtime_snapshot(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
    ) -> Option<ChatChannelRuntimeSnapshot> {
        self.chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned")
            .snapshot(channel_id, thread_id)
    }

    pub fn replace_chat_channel_messages(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
        page: &ChatMessagesResponse,
    ) {
        let mut runtime = self
            .chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned");
        let slot = runtime.slot(channel_id, thread_id);
        slot.messages = page.messages.clone();
        slot.can_load_more_past = page.can_load_more_past;
    }

    pub fn prepend_chat_channel_messages(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
        page: &ChatMessagesResponse,
    ) {
        let mut runtime = self
            .chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned");
        let slot = runtime.slot(channel_id, thread_id);
        let existing_ids: std::collections::HashSet<u64> = slot
            .messages
            .iter()
            .map(|message| message.id)
            .filter(|id| *id > 0)
            .collect();
        let mut next: Vec<ChatMessage> = page
            .messages
            .iter()
            .filter(|message| message.id == 0 || !existing_ids.contains(&message.id))
            .cloned()
            .collect();
        next.extend(slot.messages.iter().cloned());
        slot.messages = next;
        slot.can_load_more_past = page.can_load_more_past;
    }

    pub fn replace_chat_channel_pins(&self, channel_id: u64, pins: Vec<ChatMessage>) {
        let mut runtime = self
            .chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned");
        runtime.slot(channel_id, None).pins = pins;
    }

    pub fn apply_chat_channel_bus_event(
        &self,
        channel_id: u64,
        thread_id: Option<u64>,
        event: ChatBusEvent,
        event_type: Option<&str>,
    ) -> ChatChannelRuntimeSnapshot {
        let current_user_id = self.snapshot().bootstrap.current_user_id;
        let mut runtime = self
            .chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned");
        let slot = runtime.slot(channel_id, thread_id);
        apply_chat_channel_bus_event(
            &mut slot.messages,
            &mut slot.pins,
            event,
            event_type,
            current_user_id,
        );
        slot.snapshot()
    }

    pub fn close_chat_channel_runtime(&self, channel_id: u64, thread_id: Option<u64>) {
        self.chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned")
            .slots
            .remove(&slot_key(channel_id, thread_id));
    }

    pub fn clear_chat_channel_runtime(&self) {
        *self
            .chat_channels
            .lock()
            .expect("chat channel runtime lock poisoned") = FireChatChannelRuntime::default();
    }
}
