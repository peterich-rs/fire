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
    #[serde(default)]
    pub presented: AttachedPresentation,
}

impl ChatMessage {
    pub fn reuse_presentation_from(&mut self, previous: &Self) {
        if self.cooked == previous.cooked {
            if let Some(presented) = previous.presented.arc() {
                self.presented = AttachedPresentation::some(presented);
            }
        }
    }

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

