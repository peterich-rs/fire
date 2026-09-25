use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UploadResult {
    /// Discourse upload id (used by Chat `upload_ids` and similar write APIs).
    pub id: Option<u64>,
    pub short_url: String,
    pub url: Option<String>,
    pub original_filename: Option<String>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub thumbnail_width: Option<u32>,
    pub thumbnail_height: Option<u32>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResolvedUploadUrl {
    pub short_url: String,
    pub short_path: Option<String>,
    pub url: Option<String>,
}
