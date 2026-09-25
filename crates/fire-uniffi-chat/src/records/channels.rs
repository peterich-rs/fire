#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelState {
    pub id: u64,
    pub title: Option<String>,
    pub unicode_title: Option<String>,
    pub display_title: String,
    pub slug: Option<String>,
    pub description: Option<String>,
    pub chatable_type: String,
    pub status: Option<String>,
    pub threading_enabled: bool,
    pub memberships_count: Option<u32>,
    pub is_group_dm: bool,
    pub is_direct_message: bool,
    pub is_public_channel: bool,
    pub dm_users: Vec<ChatUserState>,
    pub category_color: Option<String>,
    pub category_name: Option<String>,
    pub emoji: Option<String>,
    pub formatted_emoji: Option<String>,
    pub current_user_membership: Option<ChatChannelMembershipState>,
    pub last_message: Option<ChatMessageState>,
    pub bus_last_ids: ChatChannelBusLastIdsState,
    pub can_moderate: bool,
    pub can_manage_pins: bool,
    pub can_delete_self: bool,
    pub can_delete_others: bool,
    pub can_remove_members: bool,
    pub can_flag: bool,
}

fn chat_channel_state_from_model(value: ChatChannel, base_url: &str) -> ChatChannelState {
    let display_title = value.display_title();
    let is_direct_message = value.is_direct_message();
    let is_public_channel = value.is_public_channel();
    let formatted_emoji = value.formatted_emoji();
    ChatChannelState {
        id: value.id,
        title: value.title,
        unicode_title: value.unicode_title,
        display_title,
        slug: value.slug,
        description: value.description,
        chatable_type: value.chatable_type,
        status: value.status,
        threading_enabled: value.threading_enabled,
        memberships_count: value.memberships_count,
        is_group_dm: value.is_group_dm,
        is_direct_message,
        is_public_channel,
        dm_users: value.dm_users.into_iter().map(Into::into).collect(),
        category_color: value.category_color,
        category_name: value.category_name,
        emoji: value.emoji,
        formatted_emoji,
        current_user_membership: value.current_user_membership.map(Into::into),
        last_message: value
            .last_message
            .map(|message| chat_message_state_from_model(message, base_url)),
        bus_last_ids: value.bus_last_ids.into(),
        can_moderate: value.can_moderate,
        can_manage_pins: value.can_manage_pins,
        can_delete_self: value.can_delete_self,
        can_delete_others: value.can_delete_others,
        can_remove_members: value.can_remove_members,
        can_flag: value.can_flag,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelTrackingEntryState {
    pub channel_id: u64,
    pub unread_count: u32,
    pub mention_count: u32,
}

impl From<ChatChannelTrackingEntry> for ChatChannelTrackingEntryState {
    fn from(value: ChatChannelTrackingEntry) -> Self {
        Self {
            channel_id: value.channel_id,
            unread_count: value.unread_count,
            mention_count: value.mention_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatBusLastIdEntryState {
    pub channel: String,
    pub last_id: i64,
}

impl From<ChatBusLastIdEntry> for ChatBusLastIdEntryState {
    fn from(value: ChatBusLastIdEntry) -> Self {
        Self {
            channel: value.channel,
            last_id: value.last_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct MyChatChannelsState {
    pub public_channels: Vec<ChatChannelState>,
    pub direct_message_channels: Vec<ChatChannelState>,
    pub inbox_channels: Vec<ChatChannelState>,
    pub channel_tracking: Vec<ChatChannelTrackingEntryState>,
    pub global_bus_last_ids: Vec<ChatBusLastIdEntryState>,
    pub total_unread_badge: u32,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CreateDirectMessageChannelRequestState {
    pub target_usernames: Vec<String>,
    pub name: Option<String>,
    pub upsert: bool,
}

impl From<CreateDirectMessageChannelRequestState> for CreateDirectMessageChannelRequest {
    fn from(value: CreateDirectMessageChannelRequestState) -> Self {
        Self {
            target_usernames: value.target_usernames,
            name: value.name,
            upsert: value.upsert,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BrowseChatChannelsQueryState {
    pub filter: Option<String>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

impl From<BrowseChatChannelsQueryState> for BrowseChatChannelsQuery {
    fn from(value: BrowseChatChannelsQueryState) -> Self {
        Self {
            filter: value.filter,
            offset: value.offset,
            limit: value.limit,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelMemberState {
    pub user: ChatUserState,
    pub following: bool,
    pub muted: bool,
}

impl From<ChatChannelMember> for ChatChannelMemberState {
    fn from(value: ChatChannelMember) -> Self {
        Self {
            user: value.user.into(),
            following: value.following,
            muted: value.muted,
        }
    }
}

