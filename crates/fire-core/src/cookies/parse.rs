fn parse_set_cookie(value: &str, url: &Url) -> Option<fire_models::PlatformCookie> {
    let now_unix_ms = now_unix_ms();
    let mut parts = value.split(';');
    let first = parts.next()?.trim();
    let (name, value) = first.split_once('=')?;
    let mut domain = url.host_str().map(|value| value.to_ascii_lowercase());
    let mut path = Some(default_cookie_path(url.path()));
    let mut expires_at_unix_ms = None;
    let mut max_age_expires_at_unix_ms = None;
    let mut has_domain_attribute = false;

    for attribute in parts {
        let attribute = attribute.trim();
        if let Some((key, raw_value)) = attribute.split_once('=') {
            let key = key.trim();
            let raw_value = raw_value.trim();
            if key.eq_ignore_ascii_case("domain") && !raw_value.is_empty() {
                has_domain_attribute = true;
                let normalized = raw_value.trim_start_matches('.').to_ascii_lowercase();
                if !normalized.is_empty() {
                    domain = Some(format!(".{normalized}"));
                }
            } else if key.eq_ignore_ascii_case("path") && !raw_value.is_empty() {
                path = Some(raw_value.to_string());
            } else if key.eq_ignore_ascii_case("expires") && !raw_value.is_empty() {
                expires_at_unix_ms = parse_cookie_expires_at_unix_ms(raw_value);
            } else if key.eq_ignore_ascii_case("max-age") && !raw_value.is_empty() {
                max_age_expires_at_unix_ms =
                    parse_cookie_max_age_expires_at_unix_ms(raw_value, now_unix_ms);
            }
        }
    }

    if let Some(max_age_expires_at_unix_ms) = max_age_expires_at_unix_ms {
        expires_at_unix_ms = Some(max_age_expires_at_unix_ms);
    }

    if !has_domain_attribute {
        domain = url.host_str().map(|value| value.to_ascii_lowercase());
    }

    let value = if value.trim().is_empty()
        || value.eq_ignore_ascii_case("del")
        || expires_at_unix_ms.is_some_and(|expires_at_unix_ms| expires_at_unix_ms <= now_unix_ms)
    {
        String::new()
    } else {
        value.trim().to_string()
    };

    Some(fire_models::PlatformCookie {
        name: name.trim().to_string(),
        value,
        domain,
        path,
        expires_at_unix_ms,
        same_site: None,
    })
}

fn parse_set_cookie_canonical(value: &str, url: &Url) -> Option<CanonicalCookie> {
    let now_unix_ms = now_unix_ms();
    let mut parts = value.split(';');
    let first = parts.next()?.trim();
    let (name, raw_cookie_value) = first.split_once('=')?;
    let name = name.trim();
    if name.is_empty() {
        return None;
    }

    let mut cookie = CanonicalCookie::new(name, raw_cookie_value.trim(), url.as_str());
    cookie.path = default_cookie_path(url.path());
    cookie.creation_time_unix_ms = now_unix_ms;
    cookie.last_access_time_unix_ms = now_unix_ms;
    cookie.source = CookieSource::NetworkSetCookie;
    cookie.raw_set_cookie = Some(value.to_string());
    let mut max_age_expires_at_unix_ms = None;

    for attribute in parts {
        let attribute = attribute.trim();
        if attribute.eq_ignore_ascii_case("secure") {
            cookie.secure = true;
            continue;
        }
        if attribute.eq_ignore_ascii_case("httponly") {
            cookie.http_only = true;
            continue;
        }
        if attribute.eq_ignore_ascii_case("partitioned") {
            cookie.partitioned = true;
            continue;
        }

        let Some((key, raw_value)) = attribute.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let raw_value = raw_value.trim();
        if key.eq_ignore_ascii_case("domain") && !raw_value.is_empty() {
            let normalized = raw_value.trim_start_matches('.').to_ascii_lowercase();
            if !normalized.is_empty() {
                cookie.host_only = false;
                cookie.domain = Some(format!(".{normalized}"));
            }
        } else if key.eq_ignore_ascii_case("path") && !raw_value.is_empty() {
            cookie.path = raw_value.to_string();
        } else if key.eq_ignore_ascii_case("expires") && !raw_value.is_empty() {
            cookie.expires_at_unix_ms = parse_cookie_expires_at_unix_ms(raw_value);
        } else if key.eq_ignore_ascii_case("max-age") && !raw_value.is_empty() {
            if let Ok(max_age_seconds) = raw_value.parse::<i64>() {
                cookie.max_age_seconds = Some(max_age_seconds);
                max_age_expires_at_unix_ms =
                    parse_cookie_max_age_expires_at_unix_ms(raw_value, now_unix_ms);
            }
        } else if key.eq_ignore_ascii_case("samesite") && !raw_value.is_empty() {
            cookie.same_site = parse_cookie_same_site(raw_value);
        }
    }

    if let Some(max_age_expires_at_unix_ms) = max_age_expires_at_unix_ms {
        cookie.expires_at_unix_ms = Some(max_age_expires_at_unix_ms);
    }

    if raw_cookie_value.trim().is_empty()
        || raw_cookie_value.eq_ignore_ascii_case("del")
        || cookie.is_expired_at(now_unix_ms)
    {
        cookie.value.clear();
    }

    Some(cookie)
}

fn parse_cookie_same_site(value: &str) -> CookieSameSite {
    if value.eq_ignore_ascii_case("lax") {
        CookieSameSite::Lax
    } else if value.eq_ignore_ascii_case("strict") {
        CookieSameSite::Strict
    } else if value.eq_ignore_ascii_case("none") {
        CookieSameSite::None
    } else {
        CookieSameSite::Unspecified
    }
}

fn default_cookie_path(request_path: &str) -> String {
    if request_path.is_empty() || request_path == "/" {
        return "/".to_string();
    }
    match request_path.rsplit_once('/') {
        Some(("", _)) | None => "/".to_string(),
        Some((prefix, _)) => format!("{prefix}/"),
    }
}

fn parse_cookie_expires_at_unix_ms(value: &str) -> Option<i64> {
    let expires_at = OffsetDateTime::parse(value, &Rfc2822).ok()?;
    Some(expires_at.unix_timestamp().saturating_mul(1000))
}

fn parse_cookie_max_age_expires_at_unix_ms(value: &str, now_unix_ms: i64) -> Option<i64> {
    let seconds = value.parse::<i64>().ok()?;
    if seconds <= 0 {
        return Some(now_unix_ms.saturating_sub(1));
    }

    Some(now_unix_ms.saturating_add(seconds.saturating_mul(1000)))
}

fn now_unix_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_millis() as i64)
}

