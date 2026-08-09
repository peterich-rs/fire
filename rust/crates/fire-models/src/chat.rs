use serde::{Deserialize, Serialize};

/// Discourse Chat 用户摘要（频道成员 / 消息作者）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatUser {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

/// 当前用户在频道上的成员关系。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannelMembership {
    pub following: bool,
    pub muted: bool,
    pub starred: bool,
    pub notification_level: Option<String>,
    pub last_read_message_id: Option<u64>,
    pub last_viewed_at: Option<String>,
}

/// 频道 MessageBus 订阅起始位点（`meta.message_bus_last_ids`）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannelBusLastIds {
    pub channel_message_bus_last_id: Option<i64>,
    pub new_messages: Option<i64>,
    pub new_mentions: Option<i64>,
    pub kick: Option<i64>,
}

/// 单频道未读 tracking。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannelTracking {
    pub unread_count: u32,
    pub mention_count: u32,
}

/// Chat 频道（公共 Category 频道或 DirectMessage）。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannel {
    pub id: u64,
    pub title: Option<String>,
    pub unicode_title: Option<String>,
    pub slug: Option<String>,
    pub description: Option<String>,
    /// `DirectMessage` 或 `Category`
    pub chatable_type: String,
    pub status: Option<String>,
    pub threading_enabled: bool,
    pub memberships_count: Option<u32>,
    pub is_group_dm: bool,
    pub dm_users: Vec<ChatUser>,
    pub category_color: Option<String>,
    pub category_name: Option<String>,
    pub emoji: Option<String>,
    pub current_user_membership: Option<ChatChannelMembership>,
    pub last_message: Option<ChatMessage>,
    pub bus_last_ids: ChatChannelBusLastIds,
    pub can_moderate: bool,
    pub can_manage_pins: bool,
    pub can_delete_self: bool,
    pub can_delete_others: bool,
    pub can_remove_members: bool,
    pub can_flag: bool,
}

impl ChatChannel {
    pub fn is_direct_message(&self) -> bool {
        self.chatable_type.eq_ignore_ascii_case("DirectMessage")
    }

    pub fn is_public_channel(&self) -> bool {
        self.chatable_type.eq_ignore_ascii_case("Category")
    }

    pub fn display_title(&self) -> String {
        self.unicode_title
            .as_ref()
            .or(self.title.as_ref())
            .cloned()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| format!("#{}", self.id))
    }
}

/// GET `/chat/api/me/channels` 响应。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MyChatChannelsResponse {
    pub public_channels: Vec<ChatChannel>,
    pub direct_message_channels: Vec<ChatChannel>,
    /// channel_id → tracking
    pub channel_tracking: Vec<ChatChannelTrackingEntry>,
    /// 全局 MessageBus 通道起始位点（key/value 扁平列表）
    pub global_bus_last_ids: Vec<ChatBusLastIdEntry>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannelTrackingEntry {
    pub channel_id: u64,
    pub unread_count: u32,
    pub mention_count: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatBusLastIdEntry {
    pub channel: String,
    pub last_id: i64,
}

impl MyChatChannelsResponse {
    /// 底栏徽章口径（对齐官方 web / fluxdo）：
    /// - DM：unread + mention
    /// - 公共频道：仅 mention
    /// - muted 不计
    pub fn total_unread_badge(&self) -> u32 {
        let tracking_for = |channel_id: u64| -> (u32, u32) {
            self.channel_tracking
                .iter()
                .find(|entry| entry.channel_id == channel_id)
                .map(|entry| (entry.unread_count, entry.mention_count))
                .unwrap_or((0, 0))
        };

        let mut sum = 0u32;
        for channel in &self.direct_message_channels {
            if channel
                .current_user_membership
                .as_ref()
                .is_some_and(|m| m.muted)
            {
                continue;
            }
            let (unread, mention) = tracking_for(channel.id);
            sum = sum.saturating_add(unread).saturating_add(mention);
        }
        for channel in &self.public_channels {
            if channel
                .current_user_membership
                .as_ref()
                .is_some_and(|m| m.muted)
            {
                continue;
            }
            let (_, mention) = tracking_for(channel.id);
            sum = sum.saturating_add(mention);
        }
        sum
    }
}

/// Chat 消息附件。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatUpload {
    pub id: u64,
    pub url: Option<String>,
    pub short_url: Option<String>,
    pub original_filename: Option<String>,
    pub extension: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
    pub dominant_color: Option<String>,
}

/// 消息表情回应聚合。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessageReaction {
    pub emoji: String,
    pub count: u32,
    pub reacted: bool,
    pub users: Vec<ChatUser>,
}

/// 被回复消息摘要。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessageReplyRef {
    pub id: u64,
    pub excerpt: Option<String>,
    pub user: Option<ChatUser>,
}

/// 消息串摘要。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatThreadRef {
    pub id: u64,
    pub title: Option<String>,
    pub reply_count: u32,
    pub last_reply_created_at: Option<String>,
    pub last_reply_excerpt: Option<String>,
    pub last_reply_user: Option<ChatUser>,
    pub participants: Vec<ChatUser>,
}

/// 消息收藏。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessageBookmark {
    pub id: u64,
    pub name: Option<String>,
    pub reminder_at: Option<String>,
}

/// Chat 消息。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: u64,
    pub channel_id: u64,
    pub message: String,
    pub cooked: String,
    pub excerpt: Option<String>,
    pub created_at: Option<String>,
    pub deleted_at: Option<String>,
    pub deleted_by_id: Option<u64>,
    pub edited: bool,
    pub thread_id: Option<u64>,
    pub thread: Option<ChatThreadRef>,
    pub user: Option<ChatUser>,
    pub mentioned_users: Vec<ChatUser>,
    pub reactions: Vec<ChatMessageReaction>,
    pub uploads: Vec<ChatUpload>,
    pub in_reply_to: Option<ChatMessageReplyRef>,
    pub streaming: bool,
    pub available_flags: Vec<String>,
    pub user_flag_status: Option<i32>,
    pub bookmark: Option<ChatMessageBookmark>,
    pub pinned: bool,
}

impl ChatMessage {
    pub fn is_deleted(&self) -> bool {
        self.deleted_at.is_some()
    }

    pub fn preview_text(&self) -> String {
        if let Some(excerpt) = self
            .excerpt
            .as_ref()
            .map(|value| value.trim())
            .filter(|value| !value.is_empty())
        {
            return excerpt.to_string();
        }
        let plain = self.message.trim();
        if !plain.is_empty() {
            return plain.to_string();
        }
        if !self.uploads.is_empty() {
            return "[附件]".to_string();
        }
        String::new()
    }
}

/// GET `/chat/api/channels/:id/messages` 响应。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessagesResponse {
    pub messages: Vec<ChatMessage>,
    pub can_load_more_past: bool,
    pub can_load_more_future: bool,
    pub target_message_id: Option<u64>,
}

/// 消息列表查询。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessagesQuery {
    pub channel_id: u64,
    pub direction: Option<String>,
    pub target_message_id: Option<u64>,
    pub fetch_from_last_read: bool,
    pub page_size: Option<u32>,
}

/// 创建/复用 DM 频道。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateDirectMessageChannelRequest {
    pub target_usernames: Vec<String>,
    pub name: Option<String>,
    pub upsert: bool,
}

/// 发送消息。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendChatMessageRequest {
    pub channel_id: u64,
    pub message: String,
    pub staged_id: Option<String>,
    pub in_reply_to_id: Option<u64>,
    pub thread_id: Option<u64>,
    pub upload_ids: Vec<u64>,
}

/// 发送消息结果。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendChatMessageResult {
    pub message_id: Option<u64>,
}

/// 频道成员。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatChannelMember {
    pub user: ChatUser,
    pub following: bool,
    pub muted: bool,
}

/// 浏览公共频道查询。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BrowseChatChannelsQuery {
    pub filter: Option<String>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

/// 搜索聊天消息。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatSearchQuery {
    pub query: String,
    pub channel_id: Option<u64>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatSearchResult {
    pub messages: Vec<ChatMessage>,
    pub has_more: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn total_unread_badge_matches_official_rules() {
        let response = MyChatChannelsResponse {
            public_channels: vec![ChatChannel {
                id: 1,
                chatable_type: "Category".into(),
                current_user_membership: Some(ChatChannelMembership {
                    muted: false,
                    ..Default::default()
                }),
                ..Default::default()
            }],
            direct_message_channels: vec![
                ChatChannel {
                    id: 2,
                    chatable_type: "DirectMessage".into(),
                    current_user_membership: Some(ChatChannelMembership {
                        muted: false,
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                ChatChannel {
                    id: 3,
                    chatable_type: "DirectMessage".into(),
                    current_user_membership: Some(ChatChannelMembership {
                        muted: true,
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            ],
            channel_tracking: vec![
                ChatChannelTrackingEntry {
                    channel_id: 1,
                    unread_count: 9,
                    mention_count: 2,
                },
                ChatChannelTrackingEntry {
                    channel_id: 2,
                    unread_count: 3,
                    mention_count: 1,
                },
                ChatChannelTrackingEntry {
                    channel_id: 3,
                    unread_count: 100,
                    mention_count: 50,
                },
            ],
            global_bus_last_ids: Vec::new(),
        };

        // public: only mention (2); dm2: 3+1; muted dm3: 0 → 6
        assert_eq!(response.total_unread_badge(), 6);
    }
}
