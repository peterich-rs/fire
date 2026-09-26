fn should_ignore_network_auth_cookie_deletion(cookie: &fire_models::PlatformCookie) -> bool {
    cookie.value.is_empty() && matches!(cookie.name.as_str(), "_t" | "_forum_session")
}

fn same_origin_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && base_url.host_str() == request_url.host_str()
        && base_url.port_or_known_default() == request_url.port_or_known_default()
}

fn same_site_scope(base_url: &Url, request_url: &Url) -> bool {
    base_url.scheme() == request_url.scheme()
        && hosts_share_base_domain(base_url.host_str(), request_url.host_str())
}

fn hosts_share_base_domain(base_host: Option<&str>, request_host: Option<&str>) -> bool {
    let Some(base_host) = base_host.map(|value| value.trim_start_matches('.').to_ascii_lowercase())
    else {
        return false;
    };
    let Some(request_host) =
        request_host.map(|value| value.trim_start_matches('.').to_ascii_lowercase())
    else {
        return false;
    };
    request_host == base_host || request_host.ends_with(&format!(".{base_host}"))
}

fn build_cookie_header(cookies: &CookieSnapshot, base_url: &Url, request_url: &Url) -> String {
    let canonical_known_names = canonical_cookie_names(cookies);
    let canonical_header = build_canonical_cookie_header(cookies, request_url);
    if !canonical_header.is_empty() && cookies.platform_cookies.is_empty() {
        return canonical_header;
    }

    if !cookies.platform_cookies.is_empty() {
        let request_host = request_url
            .host_str()
            .map(|value| value.to_ascii_lowercase());
        let mut matching = cookies
            .platform_cookies
            .iter()
            .enumerate()
            .filter(|(_, cookie)| {
                !canonical_known_names.contains(&cookie.name)
                    && cookie_matches_url(cookie, base_url, request_url)
            })
            .collect::<Vec<_>>();
        matching.sort_by(|(left_index, left), (right_index, right)| {
            let left_path_len = left.path.as_deref().unwrap_or("/").len();
            let right_path_len = right.path.as_deref().unwrap_or("/").len();
            right_path_len
                .cmp(&left_path_len)
                .then_with(|| {
                    cookie_send_precedence(right, request_host.as_deref())
                        .cmp(&cookie_send_precedence(left, request_host.as_deref()))
                })
                .then_with(|| right_index.cmp(left_index))
        });

        let mut seen = HashSet::new();
        let joined = matching
            .into_iter()
            .filter_map(|(_, cookie)| {
                let value = cookie.value.trim();
                if value.is_empty() {
                    return None;
                }

                let dedupe_key = (
                    cookie.name.clone(),
                    cookie.path.as_deref().unwrap_or("/").to_string(),
                );
                if !seen.insert(dedupe_key) {
                    return None;
                }

                Some(format!("{}={}", cookie.name, value))
            })
            .collect::<Vec<_>>()
            .join("; ");
        return join_cookie_headers(&canonical_header, &joined);
    }

    if !canonical_header.is_empty() {
        return canonical_header;
    }

    let mut pairs = Vec::new();
    if !canonical_known_names.contains("_t") {
        push_cookie_pair(&mut pairs, "_t", cookies.t_token.as_deref());
    }
    if !canonical_known_names.contains("_forum_session") {
        push_cookie_pair(
            &mut pairs,
            "_forum_session",
            cookies.forum_session.as_deref(),
        );
    }
    if !canonical_known_names.contains("cf_clearance") {
        push_cookie_pair(&mut pairs, "cf_clearance", cookies.cf_clearance.as_deref());
    }
    pairs.join("; ")
}

fn build_canonical_cookie_header(cookies: &CookieSnapshot, request_url: &Url) -> String {
    if cookies.canonical_cookies.is_empty() {
        return String::new();
    }

    let store = CanonicalCookieStore::from_cookies(cookies.canonical_cookies.clone());
    let mut seen_critical_names = HashSet::new();
    store
        .load_for_request(request_url)
        .into_iter()
        .filter_map(|cookie| {
            let value = cookie.value.trim();
            if value.is_empty() {
                return None;
            }
            if is_critical_cookie_name(&cookie.name)
                && !seen_critical_names.insert(cookie.name.clone())
            {
                return None;
            }
            Some(format!("{}={}", cookie.name, value))
        })
        .collect::<Vec<_>>()
        .join("; ")
}

fn canonical_cookie_names(cookies: &CookieSnapshot) -> HashSet<String> {
    cookies
        .canonical_cookies
        .iter()
        .filter(|cookie| !cookie.is_expired_now() && !cookie.value.trim().is_empty())
        .map(|cookie| cookie.name.clone())
        .collect()
}

fn join_cookie_headers(left: &str, right: &str) -> String {
    match (left.is_empty(), right.is_empty()) {
        (true, true) => String::new(),
        (false, true) => left.to_string(),
        (true, false) => right.to_string(),
        (false, false) => format!("{left}; {right}"),
    }
}

fn is_critical_cookie_name(name: &str) -> bool {
    matches!(
        name,
        "_t" | "_forum_session" | "cf_clearance" | "_cfuvid" | "h_captcha_temp_id"
    )
}

fn push_cookie_pair(pairs: &mut Vec<String>, name: &str, value: Option<&str>) {
    let Some(value) = value.filter(|value| !value.is_empty()) else {
        return;
    };
    pairs.push(format!("{name}={value}"));
}

fn is_stale_request_epoch(
    session: &Arc<RwLock<FireSessionRuntimeState>>,
    request_epoch: Option<u64>,
) -> bool {
    let Some(request_epoch) = request_epoch else {
        return false;
    };
    let current_epoch = read_rwlock(session, "session").epoch;
    current_epoch != request_epoch
}

fn cookie_send_precedence(
    cookie: &fire_models::PlatformCookie,
    request_host: Option<&str>,
) -> (u8, usize) {
    let Some(domain) = cookie
        .domain
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    else {
        return (3, request_host.map_or(0, str::len));
    };

    let normalized_domain = domain.trim_start_matches('.');
    let exact_host_match = request_host
        .is_some_and(|request_host| request_host.eq_ignore_ascii_case(normalized_domain));
    let rank = if domain.starts_with('.') {
        if exact_host_match {
            2
        } else {
            1
        }
    } else if exact_host_match {
        3
    } else {
        2
    };
    (rank, normalized_domain.len())
}

fn replace_cookie_pair(header: &str, name: &str, value: &str) -> String {
    let mut pairs = Vec::new();
    let mut replaced = false;
    for part in header.split(';') {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            continue;
        }
        let (pair_name, _) = trimmed.split_once('=').unwrap_or((trimmed, ""));
        if pair_name.eq_ignore_ascii_case(name) {
            pairs.push(format!("{name}={value}"));
            replaced = true;
        } else {
            pairs.push(trimmed.to_string());
        }
    }
    if !replaced && !value.is_empty() {
        pairs.push(format!("{name}={value}"));
    }
    pairs.join("; ")
}

