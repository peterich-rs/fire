#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<ChatUser> for ChatUserState {
    fn from(value: ChatUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelMembershipState {
    pub following: bool,
    pub muted: bool,
    pub starred: bool,
    pub notification_level: Option<String>,
    pub last_read_message_id: Option<u64>,
    pub last_viewed_at: Option<String>,
}

impl From<ChatChannelMembership> for ChatChannelMembershipState {
    fn from(value: ChatChannelMembership) -> Self {
        Self {
            following: value.following,
            muted: value.muted,
            starred: value.starred,
            notification_level: value.notification_level,
            last_read_message_id: value.last_read_message_id,
            last_viewed_at: value.last_viewed_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatChannelBusLastIdsState {
    pub channel_message_bus_last_id: Option<i64>,
    pub new_messages: Option<i64>,
    pub new_mentions: Option<i64>,
    pub kick: Option<i64>,
}

impl From<ChatChannelBusLastIds> for ChatChannelBusLastIdsState {
    fn from(value: ChatChannelBusLastIds) -> Self {
        Self {
            channel_message_bus_last_id: value.channel_message_bus_last_id,
            new_messages: value.new_messages,
            new_mentions: value.new_mentions,
            kick: value.kick,
        }
    }
}

