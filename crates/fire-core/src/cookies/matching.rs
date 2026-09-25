fn cookie_matches_url(
    cookie: &fire_models::PlatformCookie,
    base_url: &Url,
    request_url: &Url,
) -> bool {
    if cookie.is_expired_now() {
        return false;
    }

    if request_url.scheme() != base_url.scheme() {
        return false;
    }

    let Some(request_host) = request_url
        .host_str()
        .map(|value| value.to_ascii_lowercase())
    else {
        return false;
    };
    let base_host = base_url.host_str().map(|value| value.to_ascii_lowercase());
    let raw_cookie_domain = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let allows_subdomains = raw_cookie_domain
        .as_deref()
        .is_some_and(|value| value.starts_with('.'));
    let cookie_domain = raw_cookie_domain
        .as_deref()
        .map(|value| value.trim_start_matches('.').to_string())
        .or(base_host);

    let Some(cookie_domain) = cookie_domain else {
        return false;
    };
    if allows_subdomains {
        if request_host != cookie_domain && !request_host.ends_with(&format!(".{cookie_domain}")) {
            return false;
        }
    } else if request_host != cookie_domain {
        return false;
    }

    let request_path = request_url.path();
    let cookie_path = cookie.path.as_deref().unwrap_or("/");
    request_path.starts_with(cookie_path)
}

