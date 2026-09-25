use fire_models::{
    ResolvedUploadUrl, TopicAiSummary, TopicTimingEntry, TopicTimingsRequest, UploadResult,
    VoteResponse, VotedUser,
};

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicAiSummaryState {
    pub summarized_text: String,
    pub algorithm: Option<String>,
    pub outdated: bool,
    pub can_regenerate: bool,
    pub new_posts_since_summary: u32,
    pub updated_at: Option<String>,
}

impl From<TopicAiSummary> for TopicAiSummaryState {
    fn from(value: TopicAiSummary) -> Self {
        Self {
            summarized_text: value.summarized_text,
            algorithm: value.algorithm,
            outdated: value.outdated,
            can_regenerate: value.can_regenerate,
            new_posts_since_summary: value.new_posts_since_summary,
            updated_at: value.updated_at,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadImageRequestState {
    pub file_name: String,
    pub mime_type: Option<String>,
    pub bytes: Vec<u8>,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UploadResultState {
    pub id: Option<u64>,
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

impl From<UploadResult> for UploadResultState {
    fn from(value: UploadResult) -> Self {
        Self {
            id: value.id,
            short_url: value.short_url,
            url: value.url,
            original_filename: value.original_filename,
            width: value.width,
            height: value.height,
            thumbnail_width: value.thumbnail_width,
            thumbnail_height: value.thumbnail_height,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct ResolvedUploadUrlState {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}

impl From<ResolvedUploadUrl> for ResolvedUploadUrlState {
    fn from(value: ResolvedUploadUrl) -> Self {
        Self {
            short_url: value.short_url,
            short_path: value.short_path,
            url: value.url,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingEntryState {
    pub post_number: u32,
    pub milliseconds: u32,
}

impl From<TopicTimingEntryState> for TopicTimingEntry {
    fn from(value: TopicTimingEntryState) -> Self {
        Self {
            post_number: value.post_number,
            milliseconds: value.milliseconds,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicTimingsRequestState {
    pub topic_id: u64,
    pub topic_time_ms: u32,
    pub timings: Vec<TopicTimingEntryState>,
}

impl From<TopicTimingsRequestState> for TopicTimingsRequest {
    fn from(value: TopicTimingsRequestState) -> Self {
        Self {
            topic_id: value.topic_id,
            topic_time_ms: value.topic_time_ms,
            timings: value.timings.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VotedUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<VotedUser> for VotedUserState {
    fn from(value: VotedUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct VoteResponseState {
    pub can_vote: bool,
    pub vote_limit: u32,
    pub vote_count: i32,
    pub votes_left: i32,
    pub alert: bool,
    pub who_voted: Vec<VotedUserState>,
}

impl From<VoteResponse> for VoteResponseState {
    fn from(value: VoteResponse) -> Self {
        Self {
            can_vote: value.can_vote,
            vote_limit: value.vote_limit,
            vote_count: value.vote_count,
            votes_left: value.votes_left,
            alert: value.alert,
            who_voted: value.who_voted.into_iter().map(Into::into).collect(),
        }
    }
}
