use super::*;

#[test]
fn low_confidence_when_domain_and_path_both_none() {
    let cookie = PlatformCookie {
        name: "_t".into(),
        value: "token".into(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(cookie.is_low_confidence());
}

#[test]
fn not_low_confidence_when_domain_is_some() {
    let cookie = PlatformCookie {
        name: "_t".into(),
        value: "token".into(),
        domain: Some("linux.do".into()),
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(!cookie.is_low_confidence());
}

#[test]
fn not_low_confidence_when_path_is_some() {
    let cookie = PlatformCookie {
        name: "_t".into(),
        value: "token".into(),
        domain: None,
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    assert!(!cookie.is_low_confidence());
}

#[test]
fn host_only_scores_higher_than_subdomain() {
    let host_only = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    let subdomain = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let host_only_score = score_platform_cookie(&host_only, "linux.do");
    let subdomain_score = score_platform_cookie(&subdomain, "linux.do");
    assert!(host_only_score > subdomain_score);
}

#[test]
fn exact_host_match_scores_higher_than_subdomain() {
    let exact = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let subdomain = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let exact_score = score_platform_cookie(&exact, "linux.do");
    let subdomain_score = score_platform_cookie(&subdomain, "linux.do");
    assert!(exact_score > subdomain_score);
}

#[test]
fn host_only_scores_higher_than_exact_match() {
    let host_only = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    let exact = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    };
    let host_only_score = score_platform_cookie(&host_only, "linux.do");
    let exact_score = score_platform_cookie(&exact, "linux.do");
    assert!(host_only_score > exact_score);
}

#[test]
fn empty_value_scores_lower_than_non_empty() {
    let empty = PlatformCookie {
        name: "_t".into(),
        value: String::new(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    let non_empty = PlatformCookie {
        name: "_t".into(),
        value: "v".into(),
        domain: None,
        path: None,
        expires_at_unix_ms: None,
        same_site: None,
    };
    let empty_score = score_platform_cookie(&empty, "linux.do");
    let non_empty_score = score_platform_cookie(&non_empty, "linux.do");
    assert!(non_empty_score > empty_score);
}

#[test]
fn scored_apply_picks_host_only_over_subdomain_for_same_name() {
    let mut snapshot = CookieSnapshot::default();
    snapshot.scored_apply_platform_cookies(
        &[
            PlatformCookie {
                name: "_t".into(),
                value: "subdomain-value".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            },
            PlatformCookie {
                name: "_t".into(),
                value: "host-only-value".into(),
                domain: None,
                path: None,
                expires_at_unix_ms: None,
                same_site: None,
            },
        ],
        "linux.do",
        true,
    );
    assert_eq!(snapshot.t_token.as_deref(), Some("host-only-value"));
}

#[test]
fn canonical_storage_key_excludes_host_only_flag() {
    let mut host_only = CanonicalCookie::new("_t", "host", "https://linux.do/");
    host_only.host_only = true;
    host_only.domain = None;

    let mut domain_cookie = CanonicalCookie::new("_t", "domain", "https://linux.do/");
    domain_cookie.host_only = false;
    domain_cookie.domain = Some(".linux.do".into());

    assert_eq!(host_only.storage_key(), domain_cookie.storage_key());
}

#[test]
fn canonical_freshness_prefers_version_then_expiry_then_creation_time() {
    let mut existing = CanonicalCookie::new("cf_clearance", "old", "https://linux.do/");
    existing.version = 2;
    existing.expires_at_unix_ms = Some(1000);
    existing.creation_time_unix_ms = 1000;

    let mut lower_version = existing.clone();
    lower_version.version = 1;
    lower_version.expires_at_unix_ms = Some(9999);
    assert!(!lower_version.is_fresher_than(&existing));

    let mut later_expiry = existing.clone();
    later_expiry.expires_at_unix_ms = Some(2000);
    assert!(later_expiry.is_fresher_than(&existing));

    let mut later_creation = existing.clone();
    later_creation.expires_at_unix_ms = existing.expires_at_unix_ms;
    later_creation.creation_time_unix_ms = 2000;
    assert!(later_creation.is_fresher_than(&existing));
}

#[test]
fn trusted_replacement_bumps_version_when_value_changes() {
    let mut existing = CanonicalCookie::new("_t", "old", "https://linux.do/");
    existing.version = 7;
    existing.creation_time_unix_ms = 100;
    existing.last_access_time_unix_ms = 200;

    let replacement =
        CanonicalCookie::new("_t", "new", "https://linux.do/").with_trusted_version_from(&existing);

    assert_eq!(replacement.version, 8);
    assert_eq!(replacement.creation_time_unix_ms, 100);
    assert_eq!(replacement.last_access_time_unix_ms, 200);
}

#[test]
fn canonical_set_cookie_header_preserves_metadata() {
    let mut cookie = CanonicalCookie::new("cf_clearance", "value", "https://linux.do/");
    cookie.host_only = false;
    cookie.domain = Some(".linux.do".into());
    cookie.path = "/".into();
    cookie.secure = true;
    cookie.http_only = true;
    cookie.same_site = CookieSameSite::None;
    cookie.partitioned = true;
    cookie.max_age_seconds = Some(120);

    let header = cookie.to_set_cookie_header();

    assert!(header.contains("cf_clearance=value"));
    assert!(header.contains("Domain=.linux.do"));
    assert!(header.contains("Path=/"));
    assert!(header.contains("Secure"));
    assert!(header.contains("HttpOnly"));
    assert!(header.contains("SameSite=None"));
    assert!(header.contains("Partitioned"));
    assert!(header.contains("Max-Age=120"));
}

#[test]
fn canonical_store_trusted_write_bumps_existing_version() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut store = CanonicalCookieStore::new();

    store.save_canonical_cookies(
        &uri,
        [CanonicalCookie::new("_t", "old", "https://linux.do/")],
        CookieTrust::Trusted,
    );
    store.save_canonical_cookies(
        &uri,
        [CanonicalCookie::new("_t", "new", "https://linux.do/")],
        CookieTrust::Trusted,
    );

    let cookie = store.read_all().first().expect("cookie");
    assert_eq!(cookie.value, "new");
    assert_eq!(cookie.version, 2);
}

#[test]
fn canonical_store_untrusted_stale_write_is_ignored() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut store = CanonicalCookieStore::new();
    let mut trusted = CanonicalCookie::new("cf_clearance", "fresh", "https://linux.do/");
    trusted.version = 3;
    store.save_canonical_cookies(&uri, [trusted], CookieTrust::Trusted);

    let mut stale = CanonicalCookie::new("cf_clearance", "stale", "https://linux.do/");
    stale.version = 1;
    stale.expires_at_unix_ms = Some(current_unix_ms() + 10_000_000);
    store.save_canonical_cookies(&uri, [stale], CookieTrust::Untrusted);

    let cookie = store.read_all().first().expect("cookie");
    assert_eq!(cookie.value, "fresh");
    assert_eq!(cookie.version, 3);
}

#[test]
fn canonical_store_delete_by_name_bypasses_freshness() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut store = CanonicalCookieStore::new();
    let mut cookie = CanonicalCookie::new("cf_clearance", "fresh", "https://linux.do/");
    cookie.expires_at_unix_ms = Some(current_unix_ms() + 10_000_000);
    store.save_canonical_cookies(&uri, [cookie], CookieTrust::Trusted);

    let removed = store.delete_by_name(&uri, "cf_clearance");

    assert_eq!(removed, 1);
    assert!(store.read_all().is_empty());
}

#[test]
fn canonical_store_load_for_request_matches_domain_and_path() {
    let uri = url::Url::parse("https://linux.do/t/1").expect("url");
    let subdomain_uri = url::Url::parse("https://connect.linux.do/t/1").expect("url");
    let mut store = CanonicalCookieStore::new();

    let mut host_only = CanonicalCookie::new("_t", "host-only", "https://linux.do/");
    host_only.host_only = true;
    host_only.path = "/".into();
    let mut domain_cookie = CanonicalCookie::new("cf_clearance", "domain", "https://linux.do/");
    domain_cookie.host_only = false;
    domain_cookie.domain = Some(".linux.do".into());
    domain_cookie.path = "/t/".into();
    store.save_canonical_cookies(&uri, [host_only, domain_cookie], CookieTrust::Trusted);

    let main_values = store
        .load_for_request(&uri)
        .into_iter()
        .map(|cookie| cookie.value)
        .collect::<Vec<_>>();
    let subdomain_values = store
        .load_for_request(&subdomain_uri)
        .into_iter()
        .map(|cookie| cookie.value)
        .collect::<Vec<_>>();

    assert_eq!(main_values, vec!["domain", "host-only"]);
    assert_eq!(subdomain_values, vec!["domain"]);
}

#[test]
fn platform_to_canonical_treats_bare_domain_as_host_only() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let cookies = canonical_cookies_from_platform(
        &[PlatformCookie {
            name: "_t".into(),
            value: "token".into(),
            domain: Some("linux.do".into()),
            path: Some("/".into()),
            expires_at_unix_ms: None,
            same_site: None,
        }],
        &uri,
        CookieSource::WebViewBulkRead,
    );

    let cookie = cookies.first().expect("cookie");
    assert!(cookie.host_only);
    assert_eq!(cookie.domain, None);
    assert_eq!(cookie.normalized_domain().as_deref(), Some("linux.do"));
}

#[test]
fn webview_priming_payload_skips_cloudflare_clearance() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut clearance = CanonicalCookie::new("cf_clearance", "fresh", "https://linux.do/");
    clearance.host_only = false;
    clearance.domain = Some(".linux.do".into());
    clearance.secure = true;
    clearance.same_site = CookieSameSite::None;
    clearance.partitioned = true;
    let session = CanonicalCookie::new("_t", "token", "https://linux.do/");
    snapshot.merge_canonical_cookies(&uri, &[clearance, session], CookieTrust::Trusted);

    let payload = snapshot.webview_priming_payload(&uri);

    assert!(!payload.iter().any(|action| match action {
        WebViewCookieAction::DeleteByName { name, .. } => name == "cf_clearance",
        WebViewCookieAction::SetRaw { set_cookie, .. } => set_cookie.contains("cf_clearance="),
        WebViewCookieAction::DeleteExact { name, .. } => name == "cf_clearance",
    }));
    assert!(payload.iter().any(|action| {
        matches!(
            action,
            WebViewCookieAction::SetRaw { set_cookie, .. } if set_cookie.contains("_t=token")
        )
    }));
}

#[test]
fn sweep_plan_for_cloudflare_clearance_is_read_only_and_keeps_healthy_incumbent() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut canonical = CanonicalCookie::new("cf_clearance", "old", "https://linux.do/");
    canonical.host_only = false;
    canonical.domain = Some(".linux.do".into());
    canonical.secure = true;
    canonical.same_site = CookieSameSite::None;
    snapshot.merge_canonical_cookies(&uri, &[canonical], CookieTrust::Trusted);

    let older_expires = current_unix_ms() + 60_000;
    let newer_expires = current_unix_ms() + 120_000;
    let plan = snapshot.cookie_sweep_plan(
        &uri,
        "cf_clearance",
        &[
            WebViewCookieInfo {
                name: "cf_clearance".into(),
                value: "old".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                host_only: Some(false),
                secure: Some(true),
                http_only: None,
                same_site: Some(CookieSameSite::None),
                expires_at_unix_ms: Some(older_expires),
            },
            WebViewCookieInfo {
                name: "cf_clearance".into(),
                value: "new-webview".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                host_only: Some(false),
                secure: Some(true),
                http_only: None,
                same_site: Some(CookieSameSite::None),
                expires_at_unix_ms: Some(newer_expires),
            },
        ],
    );

    assert_eq!(
        plan.selected_winner
            .as_ref()
            .map(|cookie| cookie.value.as_str()),
        Some("old")
    );
    assert!(
        plan.actions.is_empty(),
        "cf_clearance sweep must not rewrite WebView"
    );
}

#[test]
fn commit_clearance_sweep_keeps_first_allowed_variant_when_jar_empty() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let older_expires = current_unix_ms() + 60_000;
    let newer_expires = current_unix_ms() + 120_000;

    snapshot.commit_cookie_sweep_result(
        &uri,
        "cf_clearance",
        CookieSweepIntent::EnsureUnique,
        &[
            WebViewCookieInfo {
                name: "cf_clearance".into(),
                value: "older".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                host_only: Some(false),
                secure: Some(true),
                http_only: None,
                same_site: Some(CookieSameSite::None),
                expires_at_unix_ms: Some(older_expires),
            },
            WebViewCookieInfo {
                name: "cf_clearance".into(),
                value: "newer".into(),
                domain: Some(".linux.do".into()),
                path: Some("/".into()),
                host_only: Some(false),
                secure: Some(true),
                http_only: None,
                same_site: Some(CookieSameSite::None),
                expires_at_unix_ms: Some(newer_expires),
            },
        ],
    );

    assert_eq!(snapshot.cf_clearance.as_deref(), Some("older"));
}

#[test]
fn commit_sweep_result_keeps_healthy_incumbent() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut canonical = CanonicalCookie::new("cf_clearance", "old", "https://linux.do/");
    canonical.host_only = false;
    canonical.domain = Some(".linux.do".into());
    canonical.secure = true;
    canonical.same_site = CookieSameSite::None;
    snapshot.merge_canonical_cookies(&uri, &[canonical], CookieTrust::Trusted);

    snapshot.commit_cookie_sweep_result(
        &uri,
        "cf_clearance",
        CookieSweepIntent::EnsureUnique,
        &[WebViewCookieInfo {
            name: "cf_clearance".into(),
            value: "new-webview".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            host_only: Some(false),
            secure: Some(true),
            http_only: None,
            same_site: Some(CookieSameSite::None),
            expires_at_unix_ms: None,
        }],
    );

    assert_eq!(snapshot.cf_clearance.as_deref(), Some("old"));
    let cookie = snapshot
        .canonical_cookies
        .iter()
        .find(|cookie| cookie.name == "cf_clearance")
        .expect("canonical cookie");
    assert_eq!(cookie.value, "old");
    assert_eq!(cookie.domain.as_deref(), Some(".linux.do"));
    assert_eq!(cookie.same_site, CookieSameSite::None);
    assert_eq!(cookie.version, 1);
}

#[test]
fn commit_delete_sweep_result_removes_canonical_cookie() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    snapshot.merge_canonical_cookies(
        &uri,
        &[CanonicalCookie::new(
            "cf_clearance",
            "fresh",
            "https://linux.do/",
        )],
        CookieTrust::Trusted,
    );

    snapshot.commit_cookie_sweep_result(&uri, "cf_clearance", CookieSweepIntent::Delete, &[]);

    assert_eq!(snapshot.cf_clearance, None);
    assert!(!snapshot
        .canonical_cookies
        .iter()
        .any(|cookie| cookie.name == "cf_clearance"));
}

#[test]
fn delete_plan_uses_exact_delete_when_webview_metadata_exists() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let snapshot = CookieSnapshot::default();
    let plan = snapshot.cookie_delete_plan(
        &uri,
        "cf_clearance",
        &[WebViewCookieInfo {
            name: "cf_clearance".into(),
            value: "stale".into(),
            domain: Some(".linux.do".into()),
            path: Some("/".into()),
            host_only: Some(false),
            secure: None,
            http_only: None,
            same_site: None,
            expires_at_unix_ms: None,
        }],
    );

    assert_eq!(plan.intent, CookieSweepIntent::Delete);
    assert_eq!(plan.actions.len(), 1);
    assert!(matches!(
        &plan.actions[0],
        WebViewCookieAction::DeleteExact {
            name,
            domain,
            path,
            ..
        } if name == "cf_clearance" && domain.as_deref() == Some(".linux.do") && path == "/"
    ));
}

#[test]
fn nuclear_reset_deletes_webview_variants_and_reprimes_canonical() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let canonical = CanonicalCookie::new("_t", "fresh", "https://linux.do/");
    snapshot.merge_canonical_cookies(&uri, &[canonical], CookieTrust::Trusted);

    let plan = snapshot.cookie_nuclear_reset_plan(
        &uri,
        &[WebViewCookieInfo {
            name: "_t".into(),
            value: "stale".into(),
            domain: None,
            path: None,
            host_only: None,
            secure: None,
            http_only: None,
            same_site: None,
            expires_at_unix_ms: None,
        }],
    );

    assert!(plan.actions.iter().any(
        |action| matches!(action, WebViewCookieAction::DeleteByName { name, .. } if name == "_t")
    ));
    assert!(plan.actions.iter().any(|action| {
        matches!(
            action,
            WebViewCookieAction::SetRaw { set_cookie, .. } if set_cookie.contains("_t=fresh")
        )
    }));
}

#[test]
fn healthy_incumbent_rejects_later_expiry_leftover() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut working = CanonicalCookie::new("cf_clearance", "working", "https://linux.do/");
    working.host_only = false;
    working.domain = Some(".linux.do".into());
    working.expires_at_unix_ms = Some(current_unix_ms() + 60 * 60 * 1000);
    snapshot.merge_canonical_cookies(&uri, &[working], CookieTrust::Trusted);

    let mut leftover = CanonicalCookie::new("cf_clearance", "leftover-chips", "https://linux.do/");
    leftover.host_only = false;
    leftover.domain = Some(".linux.do".into());
    leftover.expires_at_unix_ms = Some(current_unix_ms() + 24 * 60 * 60 * 1000);
    snapshot.merge_canonical_cookies(&uri, &[leftover], CookieTrust::Trusted);

    assert_eq!(snapshot.cf_clearance.as_deref(), Some("working"));
}

#[test]
fn challenged_incumbent_allows_ordinary_replacement() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut dead = CanonicalCookie::new("cf_clearance", "dead", "https://linux.do/");
    dead.host_only = false;
    dead.domain = Some(".linux.do".into());
    dead.expires_at_unix_ms = Some(current_unix_ms() + 60 * 60 * 1000);
    snapshot.merge_canonical_cookies(&uri, &[dead], CookieTrust::Trusted);
    snapshot.note_cf_clearance_challenged(Some("dead"));

    let mut next = CanonicalCookie::new("cf_clearance", "fresh", "https://linux.do/");
    next.host_only = false;
    next.domain = Some(".linux.do".into());
    snapshot.merge_canonical_cookies(&uri, &[next], CookieTrust::Trusted);

    assert_eq!(snapshot.cf_clearance.as_deref(), Some("fresh"));
}

#[test]
fn verified_replace_swaps_all_cf_clearance_variants() {
    let uri = url::Url::parse("https://linux.do/").expect("url");
    let mut snapshot = CookieSnapshot::default();
    let mut root = CanonicalCookie::new("cf_clearance", "root", "https://linux.do/");
    root.host_only = true;
    let mut partitioned = CanonicalCookie::new("cf_clearance", "chips", "https://linux.do/");
    partitioned.host_only = false;
    partitioned.domain = Some(".linux.do".into());
    snapshot.merge_canonical_cookies(&uri, &[root, partitioned], CookieTrust::Trusted);

    let mut verified = CanonicalCookie::new("cf_clearance", "verified", "https://linux.do/");
    verified.host_only = false;
    verified.domain = Some(".linux.do".into());
    verified.secure = true;
    verified.same_site = CookieSameSite::None;
    snapshot.replace_verified_cf_clearance(&uri, verified);

    let values: Vec<_> = snapshot
        .canonical_cookies
        .iter()
        .filter(|cookie| cookie.name == "cf_clearance")
        .map(|cookie| cookie.value.as_str())
        .collect();
    assert_eq!(values, vec!["verified"]);
    assert_eq!(snapshot.cf_clearance.as_deref(), Some("verified"));
}

#[test]
fn platform_apply_keeps_healthy_incumbent_clearance() {
    let mut snapshot = CookieSnapshot::default();
    snapshot.apply_platform_cookies(&[PlatformCookie {
        name: "cf_clearance".into(),
        value: "working".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: Some(current_unix_ms() + 60 * 60 * 1000),
        same_site: Some("None".into()),
    }]);
    snapshot.apply_platform_cookies(&[PlatformCookie {
        name: "cf_clearance".into(),
        value: "later-expiry-leftover".into(),
        domain: Some(".linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: Some(current_unix_ms() + 24 * 60 * 60 * 1000),
        same_site: Some("None".into()),
    }]);

    assert_eq!(snapshot.cf_clearance.as_deref(), Some("working"));
}
