mod canonical;
mod snapshot;
mod sweep;

#[cfg(test)]
mod tests;

pub use canonical::{
    canonical_cookie_from_platform, canonical_cookies_from_platform, current_unix_ms,
    score_platform_cookie, CanonicalCookie, CanonicalCookieStore, CookieSameSite, CookieSource,
    CookieTrust, PlatformCookie,
};
pub use snapshot::CookieSnapshot;
pub use sweep::{
    CookieSweepIntent, CookieSweepPlan, NuclearResetPlan, WebViewCookieAction, WebViewCookieInfo,
};

pub(crate) use snapshot::{is_non_empty, merge_string_patch};
