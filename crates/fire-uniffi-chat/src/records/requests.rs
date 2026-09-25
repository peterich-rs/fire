#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatSearchQueryState {
    pub query: String,
    pub channel_id: Option<u64>,
    pub offset: Option<u32>,
    pub limit: Option<u32>,
}

impl From<ChatSearchQueryState> for ChatSearchQuery {
    fn from(value: ChatSearchQueryState) -> Self {
        Self {
            query: value.query,
            channel_id: value.channel_id,
            offset: value.offset,
            limit: value.limit,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ChatSearchResultState {
    pub messages: Vec<ChatMessageState>,
    pub has_more: bool,
}

