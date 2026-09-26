use fire_models::{BootstrapArtifacts, HomeTopicListScope, TopicCategory};
use fire_uniffi_types::{RequiredTagGroupState, TopicListKindState};

#[derive(uniffi::Record, Debug, Clone)]
pub struct TopicCategoryState {
    pub id: u64,
    pub name: String,
    pub slug: String,
    pub parent_category_id: Option<u64>,
    pub color_hex: Option<String>,
    pub text_color_hex: Option<String>,
    pub topic_template: Option<String>,
    pub minimum_required_tags: u32,
    pub required_tag_groups: Vec<RequiredTagGroupState>,
    pub allowed_tags: Vec<String>,
    pub permission: Option<u32>,
    pub notification_level: Option<i32>,
}

impl From<TopicCategory> for TopicCategoryState {
    fn from(value: TopicCategory) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
            topic_template: value.topic_template,
            minimum_required_tags: value.minimum_required_tags,
            required_tag_groups: value
                .required_tag_groups
                .into_iter()
                .map(Into::into)
                .collect(),
            allowed_tags: value.allowed_tags,
            permission: value.permission,
            notification_level: value.notification_level,
        }
    }
}

impl From<TopicCategoryState> for TopicCategory {
    fn from(value: TopicCategoryState) -> Self {
        Self {
            id: value.id,
            name: value.name,
            slug: value.slug,
            parent_category_id: value.parent_category_id,
            color_hex: value.color_hex,
            text_color_hex: value.text_color_hex,
            topic_template: value.topic_template,
            minimum_required_tags: value.minimum_required_tags,
            required_tag_groups: value
                .required_tag_groups
                .into_iter()
                .map(Into::into)
                .collect(),
            allowed_tags: value.allowed_tags,
            permission: value.permission,
            notification_level: value.notification_level,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct HomeTopicListScopeState {
    pub kind: TopicListKindState,
    pub category_id: Option<u64>,
    pub tags: Vec<String>,
}

impl From<HomeTopicListScope> for HomeTopicListScopeState {
    fn from(value: HomeTopicListScope) -> Self {
        Self {
            kind: value.kind.into(),
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

impl From<HomeTopicListScopeState> for HomeTopicListScope {
    fn from(value: HomeTopicListScopeState) -> Self {
        Self {
            kind: value.kind.into(),
            category_id: value.category_id,
            tags: value.tags,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct BootstrapState {
    pub base_url: String,
    pub discourse_base_uri: Option<String>,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub current_user_id: Option<u64>,
    pub notification_channel_position: Option<i64>,
    pub long_polling_base_url: Option<String>,
    pub turnstile_sitekey: Option<String>,
    pub topic_tracking_state_meta: Option<String>,
    pub preloaded_json: Option<String>,
    pub has_preloaded_data: bool,
    pub has_site_metadata: bool,
    pub top_tags: Vec<String>,
    pub can_tag_topics: bool,
    pub categories: Vec<TopicCategoryState>,
    pub has_site_settings: bool,
    pub enabled_reaction_ids: Vec<String>,
    pub min_post_length: u32,
    pub min_topic_title_length: u32,
    pub min_first_post_length: u32,
    pub min_personal_message_title_length: u32,
    pub min_personal_message_post_length: u32,
    pub default_composer_category: Option<u64>,
    pub polling_interval_ms: u32,
    pub background_polling_interval_ms: u32,
    pub enable_chunked_encoding: bool,
}

impl From<BootstrapArtifacts> for BootstrapState {
    fn from(value: BootstrapArtifacts) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            current_user_id: value.current_user_id,
            notification_channel_position: value.notification_channel_position,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            has_site_metadata: value.has_site_metadata,
            top_tags: value.top_tags,
            can_tag_topics: value.can_tag_topics,
            categories: value.categories.into_iter().map(Into::into).collect(),
            has_site_settings: value.has_site_settings,
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
            min_topic_title_length: value.min_topic_title_length,
            min_first_post_length: value.min_first_post_length,
            min_personal_message_title_length: value.min_personal_message_title_length,
            min_personal_message_post_length: value.min_personal_message_post_length,
            default_composer_category: value.default_composer_category,
            polling_interval_ms: value.polling_interval_ms,
            background_polling_interval_ms: value.background_polling_interval_ms,
            enable_chunked_encoding: value.enable_chunked_encoding,
        }
    }
}

impl From<BootstrapState> for BootstrapArtifacts {
    fn from(value: BootstrapState) -> Self {
        Self {
            base_url: value.base_url,
            discourse_base_uri: value.discourse_base_uri,
            shared_session_key: value.shared_session_key,
            current_username: value.current_username,
            current_user_id: value.current_user_id,
            notification_channel_position: value.notification_channel_position,
            long_polling_base_url: value.long_polling_base_url,
            turnstile_sitekey: value.turnstile_sitekey,
            topic_tracking_state_meta: value.topic_tracking_state_meta,
            preloaded_json: value.preloaded_json,
            has_preloaded_data: value.has_preloaded_data,
            has_site_metadata: value.has_site_metadata,
            top_tags: value.top_tags,
            can_tag_topics: value.can_tag_topics,
            categories: value.categories.into_iter().map(Into::into).collect(),
            has_site_settings: value.has_site_settings,
            enabled_reaction_ids: value.enabled_reaction_ids,
            min_post_length: value.min_post_length,
            min_topic_title_length: value.min_topic_title_length,
            min_first_post_length: value.min_first_post_length,
            min_personal_message_title_length: value.min_personal_message_title_length,
            min_personal_message_post_length: value.min_personal_message_post_length,
            default_composer_category: value.default_composer_category,
            polling_interval_ms: value.polling_interval_ms,
            background_polling_interval_ms: value.background_polling_interval_ms,
            enable_chunked_encoding: value.enable_chunked_encoding,
        }
    }
}
