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

