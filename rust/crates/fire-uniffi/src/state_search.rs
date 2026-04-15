use fire_models::{
    GroupedSearchResult, RequiredTagGroup, SearchPost, SearchQuery, SearchResult, SearchTopic,
    SearchTypeFilter, SearchUser, TagSearchItem, TagSearchQuery, TagSearchResult, UserMentionGroup,
    UserMentionQuery, UserMentionResult, UserMentionUser,
};

#[derive(uniffi::Enum, Debug, Clone, Copy)]
pub enum SearchTypeFilterState {
    Topic,
    Post,
    User,
    Category,
    Tag,
}

impl From<SearchTypeFilter> for SearchTypeFilterState {
    fn from(value: SearchTypeFilter) -> Self {
        match value {
            SearchTypeFilter::Topic => Self::Topic,
            SearchTypeFilter::Post => Self::Post,
            SearchTypeFilter::User => Self::User,
            SearchTypeFilter::Category => Self::Category,
            SearchTypeFilter::Tag => Self::Tag,
        }
    }
}

impl From<SearchTypeFilterState> for SearchTypeFilter {
    fn from(value: SearchTypeFilterState) -> Self {
        match value {
            SearchTypeFilterState::Topic => Self::Topic,
            SearchTypeFilterState::Post => Self::Post,
            SearchTypeFilterState::User => Self::User,
            SearchTypeFilterState::Category => Self::Category,
            SearchTypeFilterState::Tag => Self::Tag,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchQueryState {
    pub q: String,
    pub page: Option<u32>,
    pub type_filter: Option<SearchTypeFilterState>,
}

impl From<SearchQuery> for SearchQueryState {
    fn from(value: SearchQuery) -> Self {
        Self {
            q: value.q,
            page: value.page,
            type_filter: value.type_filter.map(Into::into),
        }
    }
}

impl From<SearchQueryState> for SearchQuery {
    fn from(value: SearchQueryState) -> Self {
        Self {
            q: value.q,
            page: value.page,
            type_filter: value.type_filter.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchTopicState {
    pub id: u64,
    pub title: String,
    pub slug: String,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
    pub posts_count: u32,
    pub views: u32,
    pub closed: bool,
    pub archived: bool,
}

impl From<SearchTopic> for SearchTopicState {
    fn from(value: SearchTopic) -> Self {
        Self {
            id: value.id,
            title: value.title,
            slug: value.slug,
            category_id: value.category_id,
            tags: value.tags,
            posts_count: value.posts_count,
            views: value.views,
            closed: value.closed,
            archived: value.archived,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchPostState {
    pub id: u64,
    pub topic_id: Option<u64>,
    pub username: String,
    pub avatar_template: Option<String>,
    pub created_at: Option<String>,
    pub created_timestamp_unix_ms: Option<u64>,
    pub like_count: u32,
    pub blurb: String,
    pub post_number: u32,
    pub topic_title_headline: Option<String>,
}

impl From<SearchPost> for SearchPostState {
    fn from(value: SearchPost) -> Self {
        Self {
            id: value.id,
            topic_id: value.topic_id,
            username: value.username,
            avatar_template: value.avatar_template,
            created_at: value.created_at,
            created_timestamp_unix_ms: value.created_timestamp_unix_ms,
            like_count: value.like_count,
            blurb: value.blurb,
            post_number: value.post_number,
            topic_title_headline: value.topic_title_headline,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchUserState {
    pub id: u64,
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
}

impl From<SearchUser> for SearchUserState {
    fn from(value: SearchUser) -> Self {
        Self {
            id: value.id,
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct GroupedSearchResultState {
    pub term: String,
    pub more_posts: bool,
    pub more_users: bool,
    pub more_categories: bool,
    pub more_full_page_results: bool,
    pub search_log_id: Option<u64>,
}

impl From<GroupedSearchResult> for GroupedSearchResultState {
    fn from(value: GroupedSearchResult) -> Self {
        Self {
            term: value.term,
            more_posts: value.more_posts,
            more_users: value.more_users,
            more_categories: value.more_categories,
            more_full_page_results: value.more_full_page_results,
            search_log_id: value.search_log_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct SearchResultState {
    pub posts: Vec<SearchPostState>,
    pub topics: Vec<SearchTopicState>,
    pub users: Vec<SearchUserState>,
    pub grouped_result: GroupedSearchResultState,
}

impl From<SearchResult> for SearchResultState {
    fn from(value: SearchResult) -> Self {
        Self {
            posts: value.posts.into_iter().map(Into::into).collect(),
            topics: value.topics.into_iter().map(Into::into).collect(),
            users: value.users.into_iter().map(Into::into).collect(),
            grouped_result: value.grouped_result.into(),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchQueryState {
    pub q: Option<String>,
    pub filter_for_input: bool,
    pub limit: Option<u32>,
    pub category_id: Option<u64>,
    pub selected_tags: Vec<String>,
}

impl From<TagSearchQuery> for TagSearchQueryState {
    fn from(value: TagSearchQuery) -> Self {
        Self {
            q: value.q,
            filter_for_input: value.filter_for_input,
            limit: value.limit,
            category_id: value.category_id,
            selected_tags: value.selected_tags,
        }
    }
}

impl From<TagSearchQueryState> for TagSearchQuery {
    fn from(value: TagSearchQueryState) -> Self {
        Self {
            q: value.q,
            filter_for_input: value.filter_for_input,
            limit: value.limit,
            category_id: value.category_id,
            selected_tags: value.selected_tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchItemState {
    pub name: String,
    pub text: String,
    pub count: u32,
}

impl From<TagSearchItem> for TagSearchItemState {
    fn from(value: TagSearchItem) -> Self {
        Self {
            name: value.name,
            text: value.text,
            count: value.count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct RequiredTagGroupState {
    pub name: String,
    pub min_count: u32,
}

impl From<RequiredTagGroup> for RequiredTagGroupState {
    fn from(value: RequiredTagGroup) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

impl From<RequiredTagGroupState> for RequiredTagGroup {
    fn from(value: RequiredTagGroupState) -> Self {
        Self {
            name: value.name,
            min_count: value.min_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct TagSearchResultState {
    pub results: Vec<TagSearchItemState>,
    pub required_tag_group: Option<RequiredTagGroupState>,
}

impl From<TagSearchResult> for TagSearchResultState {
    fn from(value: TagSearchResult) -> Self {
        Self {
            results: value.results.into_iter().map(Into::into).collect(),
            required_tag_group: value.required_tag_group.map(Into::into),
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionQueryState {
    pub term: String,
    pub include_groups: bool,
    pub limit: u32,
    pub topic_id: Option<u64>,
    pub category_id: Option<u64>,
}

impl From<UserMentionQuery> for UserMentionQueryState {
    fn from(value: UserMentionQuery) -> Self {
        Self {
            term: value.term,
            include_groups: value.include_groups,
            limit: value.limit,
            topic_id: value.topic_id,
            category_id: value.category_id,
        }
    }
}

impl From<UserMentionQueryState> for UserMentionQuery {
    fn from(value: UserMentionQueryState) -> Self {
        Self {
            term: value.term,
            include_groups: value.include_groups,
            limit: value.limit,
            topic_id: value.topic_id,
            category_id: value.category_id,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionUserState {
    pub username: String,
    pub name: Option<String>,
    pub avatar_template: Option<String>,
    pub priority_group: Option<u32>,
}

impl From<UserMentionUser> for UserMentionUserState {
    fn from(value: UserMentionUser) -> Self {
        Self {
            username: value.username,
            name: value.name,
            avatar_template: value.avatar_template,
            priority_group: value.priority_group,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionGroupState {
    pub name: String,
    pub full_name: Option<String>,
    pub flair_url: Option<String>,
    pub flair_bg_color: Option<String>,
    pub flair_color: Option<String>,
    pub user_count: Option<u32>,
}

impl From<UserMentionGroup> for UserMentionGroupState {
    fn from(value: UserMentionGroup) -> Self {
        Self {
            name: value.name,
            full_name: value.full_name,
            flair_url: value.flair_url,
            flair_bg_color: value.flair_bg_color,
            flair_color: value.flair_color,
            user_count: value.user_count,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct UserMentionResultState {
    pub users: Vec<UserMentionUserState>,
    pub groups: Vec<UserMentionGroupState>,
}

impl From<UserMentionResult> for UserMentionResultState {
    fn from(value: UserMentionResult) -> Self {
        Self {
            users: value.users.into_iter().map(Into::into).collect(),
            groups: value.groups.into_iter().map(Into::into).collect(),
        }
    }
}
