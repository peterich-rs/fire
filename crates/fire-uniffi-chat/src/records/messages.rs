#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageState {
    pub id: u64,
    pub channel_id: u64,
    pub message: String,
    pub presentation: Option<Arc<RenderDocumentHandle>>,
    pub excerpt: Option<String>,
    pub preview_text: String,
    pub created_at: Option<String>,
    pub deleted_at: Option<String>,
    pub deleted_by_id: Option<u64>,
    pub edited: bool,
    pub thread_id: Option<u64>,
    pub thread: Option<ChatThreadRefState>,
    pub user: Option<ChatUserState>,
    pub mentioned_users: Vec<ChatUserState>,
    pub reactions: Vec<ChatMessageReactionState>,
    pub uploads: Vec<ChatUploadState>,
    pub in_reply_to: Option<ChatMessageReplyRefState>,
    pub streaming: bool,
    pub available_flags: Vec<String>,
    pub user_flag_status: Option<i32>,
    pub bookmark: Option<ChatMessageBookmarkState>,
    pub pinned: bool,
    pub is_deleted: bool,
    pub staged_id: Option<String>,
}

fn chat_message_state_from_model(value: ChatMessage, _base_url: &str) -> ChatMessageState {
    let preview_text = value.preview_text();
    let is_deleted = value.is_deleted();
    let presentation = value.presented.arc().map(intern_presented_handle);
    ChatMessageState {
        id: value.id,
        channel_id: value.channel_id,
        message: value.message,
        presentation,
        excerpt: value.excerpt,
        preview_text,
        created_at: value.created_at,
        deleted_at: value.deleted_at,
        deleted_by_id: value.deleted_by_id,
        edited: value.edited,
        thread_id: value.thread_id,
        thread: value.thread.map(Into::into),
        user: value.user.map(Into::into),
        mentioned_users: value.mentioned_users.into_iter().map(Into::into).collect(),
        reactions: value.reactions.into_iter().map(Into::into).collect(),
        uploads: value.uploads.into_iter().map(Into::into).collect(),
        in_reply_to: value.in_reply_to.map(Into::into),
        streaming: value.streaming,
        available_flags: value.available_flags,
        user_flag_status: value.user_flag_status,
        bookmark: value.bookmark.map(Into::into),
        pinned: value.pinned,
        is_deleted,
        staged_id: value.staged_id,
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessagesQueryState {
    pub channel_id: u64,
    pub direction: Option<String>,
    pub target_message_id: Option<u64>,
    pub fetch_from_last_read: bool,
    pub page_size: Option<u32>,
}

impl From<ChatMessagesQueryState> for ChatMessagesQuery {
    fn from(value: ChatMessagesQueryState) -> Self {
        Self {
            channel_id: value.channel_id,
            direction: value.direction,
            target_message_id: value.target_message_id,
            fetch_from_last_read: value.fetch_from_last_read,
            page_size: value.page_size,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessagesState {
    pub messages: Vec<ChatMessageState>,
    pub can_load_more_past: bool,
    pub can_load_more_future: bool,
    pub target_message_id: Option<u64>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SendChatMessageRequestState {
    pub channel_id: u64,
    pub message: String,
    pub staged_id: Option<String>,
    pub in_reply_to_id: Option<u64>,
    pub thread_id: Option<u64>,
    pub upload_ids: Vec<u64>,
}

impl From<SendChatMessageRequestState> for SendChatMessageRequest {
    fn from(value: SendChatMessageRequestState) -> Self {
        Self {
            channel_id: value.channel_id,
            message: value.message,
            staged_id: value.staged_id,
            in_reply_to_id: value.in_reply_to_id,
            thread_id: value.thread_id,
            upload_ids: value.upload_ids,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SendChatMessageResultState {
    pub message_id: Option<u64>,
}

impl From<SendChatMessageResult> for SendChatMessageResultState {
    fn from(value: SendChatMessageResult) -> Self {
        Self {
            message_id: value.message_id,
        }
    }
}

