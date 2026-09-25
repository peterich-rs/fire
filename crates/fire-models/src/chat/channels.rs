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
        let title = self
            .unicode_title
            .as_ref()
            .or(self.title.as_ref())
            .cloned()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| format!("#{}", self.id));
        let Some(emoji) = self.formatted_emoji() else {
            return title;
        };
        if title.contains(&emoji) || title.contains(&format!(":{}:", emoji.trim_matches(':'))) {
            return title;
        }
        format!("{emoji} {title}")
    }

    /// Leading glyph for public-channel inbox rows (unicode or `:shortcode:`).
    pub fn formatted_emoji(&self) -> Option<String> {
        let raw = self.emoji.as_deref()?.trim();
        if raw.is_empty() {
            return None;
        }
        let name = raw.trim_matches(':');
        if name
            .chars()
            .any(|ch| !ch.is_ascii_alphanumeric() && ch != '_')
        {
            return Some(name.to_string());
        }
        Some(
            emoji_shortcode_to_unicode(name)
                .map(str::to_string)
                .unwrap_or_else(|| format!(":{name}:")),
        )
    }

    pub fn last_activity_at(&self) -> Option<&str> {
        self.last_message
            .as_ref()
            .and_then(|message| message.created_at.as_deref())
    }
}

fn emoji_shortcode_to_unicode(name: &str) -> Option<&'static str> {
    Some(match name {
        "smile" | "slightly_smiling_face" => "🙂",
        "grinning" | "grin" => "😀",
        "joy" => "😂",
        "heart" | "red_heart" => "❤️",
        "fire" => "🔥",
        "tada" => "🎉",
        "rocket" => "🚀",
        "star" => "⭐",
        "warning" => "⚠️",
        "speech_balloon" | "speech_left" => "💬",
        "loudspeaker" | "mega" => "📢",
        "bell" => "🔔",
        "bulb" => "💡",
        "computer" | "desktop_computer" => "💻",
        "earth_asia" | "globe_with_meridians" => "🌏",
        "link" => "🔗",
        "memo" | "pencil" => "📝",
        "books" => "📚",
        "gear" => "⚙️",
        "hammer_and_wrench" | "hammer" => "🛠️",
        "bug" => "🐛",
        "tv" => "📺",
        "game_die" | "video_game" => "🎮",
        "coffee" => "☕",
        "seedling" => "🌱",
        "pushpin" => "📌",
        "eyes" => "👀",
        "wave" => "👋",
        "thumbsup" | "+1" => "👍",
        "clap" => "👏",
        "100" => "💯",
        _ => return None,
    })
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

    /// WeChat-style inbox: DMs and public channels sorted by last activity.
    pub fn inbox_channels(&self) -> Vec<&ChatChannel> {
        let mut channels: Vec<&ChatChannel> = self
            .direct_message_channels
            .iter()
            .chain(self.public_channels.iter())
            .collect();
        channels.sort_by(|left, right| {
            right
                .last_activity_at()
                .unwrap_or("")
                .cmp(left.last_activity_at().unwrap_or(""))
                .then_with(|| right.id.cmp(&left.id))
        });
        channels
    }
}

