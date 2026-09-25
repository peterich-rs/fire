use serde::{Deserialize, Serialize};
use url::Url;

use super::bootstrap::BootstrapArtifacts;
use crate::cookie::{is_non_empty, CookieSnapshot};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub enum LoginPhase {
    #[default]
    Anonymous,
    CookiesCaptured,
    BootstrapCaptured,
    Ready,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionReadiness {
    pub has_login_cookie: bool,
    pub has_forum_session: bool,
    pub has_cloudflare_clearance: bool,
    pub has_csrf_token: bool,
    pub has_current_user: bool,
    pub has_preloaded_data: bool,
    pub has_shared_session_key: bool,
    pub can_read_authenticated_api: bool,
    pub can_write_authenticated_api: bool,
    pub can_open_message_bus: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionSnapshot {
    pub cookies: CookieSnapshot,
    pub bootstrap: BootstrapArtifacts,
    #[serde(default)]
    pub browser_user_agent: Option<String>,
    /// Wake-up copy for `SessionState::from_snapshot`. Not persisted and not part of
    /// `snapshot_revision`. The authoritative value lives on `FireSessionRuntimeState`.
    #[serde(skip)]
    pub read_path_login_request: Option<crate::ReadPathLoginRequest>,
}

impl SessionSnapshot {
    pub fn readiness(&self) -> SessionReadiness {
        let has_login_cookie = self.cookies.has_login_session();
        let has_forum_session = self.cookies.has_forum_session();
        let has_cloudflare_clearance = self.cookies.has_cloudflare_clearance();
        let has_csrf_token = self.cookies.has_csrf_token();
        let has_current_user = self.bootstrap.has_identity();
        let has_preloaded_data = self.bootstrap.has_preloaded_data;
        let has_shared_session_key = is_non_empty(self.bootstrap.shared_session_key.as_deref());
        let can_read_authenticated_api = self.cookies.can_authenticate_requests();
        let can_write_authenticated_api = can_read_authenticated_api && has_csrf_token;
        let can_open_message_bus = can_read_authenticated_api
            && (!message_bus_requires_shared_session_key(&self.bootstrap)
                || has_shared_session_key);

        SessionReadiness {
            has_login_cookie,
            has_forum_session,
            has_cloudflare_clearance,
            has_csrf_token,
            has_current_user,
            has_preloaded_data,
            has_shared_session_key,
            can_read_authenticated_api,
            can_write_authenticated_api,
            can_open_message_bus,
        }
    }

    pub fn login_phase(&self) -> LoginPhase {
        let readiness = self.readiness();
        if !readiness.has_login_cookie {
            return LoginPhase::Anonymous;
        }
        if !readiness.can_read_authenticated_api || !readiness.has_current_user {
            return LoginPhase::CookiesCaptured;
        }
        if !readiness.can_write_authenticated_api
            || !readiness.has_preloaded_data
            || !self.bootstrap.has_site_metadata
            || !self.bootstrap.has_site_settings
        {
            return LoginPhase::BootstrapCaptured;
        }
        LoginPhase::Ready
    }

    pub fn profile_display_name(&self) -> String {
        if let Some(current_username) = self
            .bootstrap
            .current_username
            .as_deref()
            .filter(|value| !value.is_empty())
        {
            return current_username.to_string();
        }

        let readiness = self.readiness();
        if readiness.can_read_authenticated_api || self.cookies.has_login_session() {
            "会话已连接".to_string()
        } else {
            "未登录".to_string()
        }
    }

    pub fn login_phase_label(&self) -> String {
        let readiness = self.readiness();
        if readiness.can_read_authenticated_api && !readiness.has_current_user {
            "账号信息同步中".to_string()
        } else {
            self.login_phase().title().to_string()
        }
    }

    pub fn clear_login_state(&mut self, preserve_cf_clearance: bool) {
        self.cookies.clear_login_state(preserve_cf_clearance);
        self.bootstrap.clear_login_state();
    }
}

impl LoginPhase {
    pub fn title(self) -> &'static str {
        match self {
            Self::Anonymous => "未登录",
            Self::CookiesCaptured => "Cookie 已同步",
            Self::BootstrapCaptured => "会话初始化中",
            Self::Ready => "已就绪",
        }
    }
}

fn message_bus_requires_shared_session_key(bootstrap: &BootstrapArtifacts) -> bool {
    let Some(base_origin) = request_origin(&bootstrap.base_url) else {
        return false;
    };
    let Some(long_polling_base_url) = bootstrap
        .long_polling_base_url
        .as_deref()
        .filter(|value| !value.is_empty())
    else {
        return false;
    };
    let Some(poll_origin) = request_origin(long_polling_base_url) else {
        return false;
    };

    base_origin != poll_origin
}

fn request_origin(value: &str) -> Option<String> {
    let mut url = Url::parse(value).ok()?;
    url.set_path("");
    url.set_query(None);
    url.set_fragment(None);
    Some(url.as_str().trim_end_matches('/').to_string())
}
