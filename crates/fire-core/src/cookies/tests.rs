#[cfg(test)]
mod tests {
    use url::Url;

    use super::{
        build_cookie_header, cookie_matches_url, now_unix_ms, parse_set_cookie,
        parse_set_cookie_canonical,
    };
    use fire_models::{CanonicalCookie, CookieSameSite, CookieSnapshot, PlatformCookie};

    #[test]
    fn parse_set_cookie_preserves_leading_dot_and_expiry() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie(
            "_t=fresh; Domain=.linux.do; Path=/; Expires=Tue, 01 Jan 2030 00:00:00 GMT",
            &url,
        )
        .expect("cookie");

        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
        assert_eq!(cookie.path.as_deref(), Some("/"));
        assert!(cookie.expires_at_unix_ms.is_some());
    }

    #[test]
    fn parse_set_cookie_prefers_max_age_over_expires() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie(
            "_t=fresh; Expires=Tue, 01 Jan 2030 00:00:00 GMT; Max-Age=1",
            &url,
        )
        .expect("cookie");

        let expires_at_unix_ms = cookie.expires_at_unix_ms.expect("max-age expiry");
        let now_unix_ms = super::now_unix_ms();
        assert!(expires_at_unix_ms >= now_unix_ms);
        assert!(expires_at_unix_ms <= now_unix_ms + 5_000);
    }

    #[test]
    fn parse_set_cookie_canonicalizes_domain_attribute_without_leading_dot() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie("_t=fresh; Domain=linux.do; Path=/", &url).expect("cookie");

        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
    }

    #[test]
    fn parse_set_cookie_clears_immediately_expired_auth_values() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie("_t=fresh; Max-Age=0; Path=/", &url).expect("cookie");

        assert!(cookie.value.is_empty());
        assert!(cookie
            .expires_at_unix_ms
            .is_some_and(|expires_at_unix_ms| expires_at_unix_ms < now_unix_ms()));
    }

    #[test]
    fn parse_set_cookie_canonical_preserves_browser_metadata() {
        let url = Url::parse("https://linux.do/latest").expect("url");
        let cookie = parse_set_cookie_canonical(
            "cf_clearance=fresh; Domain=.linux.do; Path=/; Max-Age=120; Secure; HttpOnly; SameSite=None; Partitioned",
            &url,
        )
        .expect("cookie");

        assert_eq!(cookie.name, "cf_clearance");
        assert_eq!(cookie.value, "fresh");
        assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
        assert!(!cookie.host_only);
        assert!(cookie.secure);
        assert!(cookie.http_only);
        assert_eq!(cookie.same_site, CookieSameSite::None);
        assert!(cookie.partitioned);
        assert_eq!(cookie.max_age_seconds, Some(120));
        assert!(cookie.expires_at_unix_ms.is_some());
        assert_eq!(
            cookie.raw_set_cookie.as_deref(),
            Some("cf_clearance=fresh; Domain=.linux.do; Path=/; Max-Age=120; Secure; HttpOnly; SameSite=None; Partitioned")
        );
    }

    #[test]
    fn cookie_matching_distinguishes_host_only_and_domain_scope() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://meta.linux.do/latest").expect("request url");
        let host_only_cookie = PlatformCookie {
            name: "_t".into(),
            value: "host-only".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };
        let domain_cookie = PlatformCookie {
            name: "_t".into(),
            value: "domain-scope".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        };

        assert!(!cookie_matches_url(
            &host_only_cookie,
            &base_url,
            &request_url
        ));
        assert!(cookie_matches_url(&domain_cookie, &base_url, &request_url));
    }

    #[test]
    fn build_cookie_header_skips_expired_platform_cookies() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            platform_cookies: vec![
                fire_models::PlatformCookie {
                    name: "_t".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
                fire_models::PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        assert_eq!(
            build_cookie_header(&cookies, &base_url, &request_url),
            "_forum_session=forum"
        );
    }

    #[test]
    fn build_cookie_header_does_not_fallback_to_stale_scalar_auth_fields() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            t_token: Some("stale-token".into()),
            forum_session: Some("stale-forum".into()),
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "expired".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: Some(1),
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        assert!(build_cookie_header(&cookies, &base_url, &request_url).is_empty());
    }

    #[test]
    fn build_cookie_header_prefers_host_only_cookie_over_domain_variant_with_same_name_and_path() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let request_url = Url::parse("https://linux.do/latest").expect("request url");
        let cookies = CookieSnapshot {
            platform_cookies: vec![
                PlatformCookie {
                    name: "_t".into(),
                    value: "fresh-host".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "_t".into(),
                    value: "stale-domain".into(),
                    domain: Some(".linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "_forum_session".into(),
                    value: "forum".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            ..CookieSnapshot::default()
        };

        let header = build_cookie_header(&cookies, &base_url, &request_url);
        let t_pairs = header
            .split("; ")
            .filter(|pair| pair.starts_with("_t="))
            .collect::<Vec<_>>();

        assert_eq!(t_pairs, vec!["_t=fresh-host"]);
        assert!(!header.contains("stale-domain"));
        assert!(header
            .split("; ")
            .any(|pair| pair == "_forum_session=forum"));
    }

    #[test]
    fn build_cookie_header_prefers_canonical_and_blocks_legacy_same_name_leak() {
        let base_url = Url::parse("https://linux.do").expect("base url");
        let main_url = Url::parse("https://linux.do/latest").expect("request url");
        let subdomain_url = Url::parse("https://connect.linux.do/latest").expect("request url");

        let mut canonical_t = CanonicalCookie::new("_t", "fresh-host", "https://linux.do/");
        canonical_t.host_only = true;
        canonical_t.path = "/".into();
        let mut canonical_cf = CanonicalCookie::new("cf_clearance", "clear", "https://linux.do/");
        canonical_cf.host_only = false;
        canonical_cf.domain = Some(".linux.do".into());
        canonical_cf.path = "/".into();

        let cookies = CookieSnapshot {
            platform_cookies: vec![PlatformCookie {
                name: "_t".into(),
                value: "legacy-domain".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            canonical_cookies: vec![canonical_t, canonical_cf],
            ..CookieSnapshot::default()
        };

        let main_header = build_cookie_header(&cookies, &base_url, &main_url);
        assert!(main_header.contains("_t=fresh-host"));
        assert!(main_header.contains("cf_clearance=clear"));
        assert!(!main_header.contains("legacy-domain"));

        let subdomain_header = build_cookie_header(&cookies, &base_url, &subdomain_url);
        assert_eq!(subdomain_header, "cf_clearance=clear");
    }
}
