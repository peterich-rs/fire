use fire_models::{Draft, DraftData, DraftListResponse};

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftDataState {
    pub reply: Option<String>,
    pub title: Option<String>,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub reply_to_post_number: Option<u32>,
    pub action: Option<String>,
    pub recipients: Vec<String>,
    pub archetype_id: Option<String>,
    pub composer_time: Option<u32>,
    pub typing_time: Option<u32>,
}

impl From<DraftData> for DraftDataState {
    fn from(value: DraftData) -> Self {
        Self {
            reply: value.reply,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
            reply_to_post_number: value.reply_to_post_number,
            action: value.action,
            recipients: value.recipients,
            archetype_id: value.archetype_id,
            composer_time: value.composer_time,
            typing_time: value.typing_time,
        }
    }
}

impl From<DraftDataState> for DraftData {
    fn from(value: DraftDataState) -> Self {
        Self {
            reply: value.reply,
            title: value.title,
            category_id: value.category_id,
            tags: value.tags,
            reply_to_post_number: value.reply_to_post_number,
            action: value.action,
            recipients: value.recipients,
            archetype_id: value.archetype_id,
            composer_time: value.composer_time,
            typing_time: value.typing_time,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftState {
    pub draft_key: String,
    pub data: DraftDataState,
    pub sequence: u32,
    pub title: Option<String>,
    pub excerpt: Option<String>,
    pub updated_at: Option<String>,
    pub username: Option<String>,
    pub avatar_template: Option<String>,
    pub topic_id: Option<u64>,
}

impl From<Draft> for DraftState {
    fn from(value: Draft) -> Self {
        Self {
            draft_key: value.draft_key,
            data: value.data.into(),
            sequence: value.sequence,
            title: value.title,
            excerpt: value.excerpt,
            updated_at: value.updated_at,
            username: value.username,
            avatar_template: value.avatar_template,
            topic_id: value.topic_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct DraftListResponseState {
    pub drafts: Vec<DraftState>,
    pub has_more: bool,
}

impl From<DraftListResponse> for DraftListResponseState {
    fn from(value: DraftListResponse) -> Self {
        Self {
            drafts: value.drafts.into_iter().map(Into::into).collect(),
            has_more: value.has_more,
        }
    }
}
