#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatUploadState {
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

impl From<ChatUpload> for ChatUploadState {
    fn from(value: ChatUpload) -> Self {
        Self {
            id: value.id,
            url: value.url,
            short_url: value.short_url,
            original_filename: value.original_filename,
            extension: value.extension,
            width: value.width,
            height: value.height,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
            dominant_color: value.dominant_color,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageReactionState {
    pub emoji: String,
    pub count: u32,
    pub reacted: bool,
    pub users: Vec<ChatUserState>,
}

impl From<ChatMessageReaction> for ChatMessageReactionState {
    fn from(value: ChatMessageReaction) -> Self {
        Self {
            emoji: value.emoji,
            count: value.count,
            reacted: value.reacted,
            users: value.users.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageReplyRefState {
    pub id: u64,
    pub excerpt: Option<String>,
    pub user: Option<ChatUserState>,
}

impl From<ChatMessageReplyRef> for ChatMessageReplyRefState {
    fn from(value: ChatMessageReplyRef) -> Self {
        Self {
            id: value.id,
            excerpt: value.excerpt,
            user: value.user.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatThreadRefState {
    pub id: u64,
    pub title: Option<String>,
    pub reply_count: u32,
    pub last_reply_created_at: Option<String>,
    pub last_reply_excerpt: Option<String>,
    pub last_reply_user: Option<ChatUserState>,
    pub participants: Vec<ChatUserState>,
}

impl From<ChatThreadRef> for ChatThreadRefState {
    fn from(value: ChatThreadRef) -> Self {
        Self {
            id: value.id,
            title: value.title,
            reply_count: value.reply_count,
            last_reply_created_at: value.last_reply_created_at,
            last_reply_excerpt: value.last_reply_excerpt,
            last_reply_user: value.last_reply_user.map(Into::into),
            participants: value.participants.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatMessageBookmarkState {
    pub id: u64,
    pub name: Option<String>,
    pub reminder_at: Option<String>,
}

impl From<ChatMessageBookmark> for ChatMessageBookmarkState {
    fn from(value: ChatMessageBookmark) -> Self {
        Self {
            id: value.id,
            name: value.name,
            reminder_at: value.reminder_at,
        }
    }
}

