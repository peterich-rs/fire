#[derive(Debug, Clone)]
pub struct FireCoreConfig {
    pub base_url: String,
    pub workspace_path: Option<String>,
}

impl Default for FireCoreConfig {
    fn default() -> Self {
        Self {
            base_url: "https://linux.do".to_string(),
            workspace_path: None,
        }
    }
}
