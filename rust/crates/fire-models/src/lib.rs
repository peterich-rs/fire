use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CookieSnapshot {
    pub t_token: Option<String>,
    pub forum_session: Option<String>,
    pub cf_clearance: Option<String>,
    pub csrf_token: Option<String>,
}

impl CookieSnapshot {
    pub fn has_login_session(&self) -> bool {
        self.t_token.as_deref().is_some_and(|value| !value.is_empty())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BootstrapArtifacts {
    pub base_url: String,
    pub shared_session_key: Option<String>,
    pub current_username: Option<String>,
    pub long_polling_base_url: Option<String>,
    pub has_preloaded_data: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionSnapshot {
    pub cookies: CookieSnapshot,
    pub bootstrap: BootstrapArtifacts,
}

#[cfg(test)]
mod tests {
    use super::CookieSnapshot;

    #[test]
    fn login_session_requires_t_token() {
        let mut cookies = CookieSnapshot::default();
        assert!(!cookies.has_login_session());

        cookies.t_token = Some("token".into());
        assert!(cookies.has_login_session());
    }
}
