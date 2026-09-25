#[derive(Clone)]
pub(crate) struct FireSessionCookieJar {
    base_url: Url,
    session: Arc<RwLock<FireSessionRuntimeState>>,
    store: Option<Arc<Mutex<fire_store::FireStore>>>,
}

impl FireSessionCookieJar {
    pub(crate) fn new(
        base_url: Url,
        session: Arc<RwLock<FireSessionRuntimeState>>,
        store: Option<Arc<Mutex<fire_store::FireStore>>>,
    ) -> Self {
        Self {
            base_url,
            session,
            store,
        }
    }
}

tokio::task_local! {
    pub(crate) static FIRE_REQUEST_EPOCH: u64;
}

tokio::task_local! {
    pub(crate) static FIRE_REQUEST_TRACE_ID: u64;
}

impl CookieJar for FireSessionCookieJar {
    fn set_cookies(&self, cookie_headers: &mut dyn Iterator<Item = &HeaderValue>, url: &Url) {
        if !same_site_scope(&self.base_url, url) {
            return;
        }

        let request_epoch = FIRE_REQUEST_EPOCH.try_with(|epoch| *epoch).ok();
        if is_stale_request_epoch(&self.session, request_epoch) {
            return;
        }

        let mut patch = CookieSnapshot::default();
        let mut canonical_writes = Vec::new();
        let mut canonical_deletes = Vec::new();
        let mut replay_entries: Vec<(String, String, String)> = Vec::new();
        for header in cookie_headers {
            let Ok(value) = header.to_str() else {
                continue;
            };
            let Some(cookie) = parse_set_cookie(value, url) else {
                continue;
            };
            let canonical_cookie = parse_set_cookie_canonical(value, url);

            if should_ignore_network_auth_cookie_deletion(&cookie) {
                continue;
            }

            if cookie.value.is_empty() || cookie.is_expired_now() {
                canonical_deletes.push(cookie.name.clone());
            } else if let Some(canonical_cookie) = canonical_cookie {
                canonical_writes.push(canonical_cookie);
            }

            match cookie.name.as_str() {
                "_t" => patch.t_token = Some(cookie.value.clone()),
                "_forum_session" => patch.forum_session = Some(cookie.value.clone()),
                "cf_clearance" => patch.cf_clearance = Some(cookie.value.clone()),
                _ => {}
            }
            // cf_clearance must not be replayed jar → WebView. Only browser/WebView
            // authored clearance is trustworthy; Set-Cookie replay can drop
            // Partitioned and create a ghost variant.
            if !cookie.name.eq_ignore_ascii_case("cf_clearance") {
                let replay_domain = cookie
                    .domain
                    .as_deref()
                    .map(|d| d.trim_start_matches('.').to_string())
                    .unwrap_or_default();
                replay_entries.push((value.to_string(), cookie.name.clone(), replay_domain));
            }
            patch.platform_cookies.push(cookie);
        }

        if patch == CookieSnapshot::default()
            && canonical_writes.is_empty()
            && canonical_deletes.is_empty()
        {
            return;
        }

        let mut session = write_rwlock(&self.session, "session");
        mutate_runtime_session_tracking_auth_change(
            &mut session,
            FireAuthChangeSource::NetworkIngress,
            "network set-cookie ingress",
            |snapshot| {
                snapshot.cookies.merge_patch(&patch);
                for name in &canonical_deletes {
                    snapshot.cookies.delete_canonical_cookie_by_name(url, name);
                }
                if !canonical_writes.is_empty() {
                    snapshot.cookies.merge_canonical_cookies(
                        url,
                        &canonical_writes,
                        CookieTrust::Trusted,
                    );
                }
            },
        );

        if let Some(store) = self.store.as_ref() {
            let Ok(store) = store.lock() else {
                return;
            };
            for (raw_set_cookie, cookie_name, domain) in replay_entries {
                let url = self.base_url.as_str();
                if let Err(error) = store.cookie_replay_enqueue(
                    url,
                    &raw_set_cookie,
                    &cookie_name,
                    &domain,
                    fire_models::current_unix_ms() as u64,
                ) {
                    warn!(
                        cookie_name = %cookie_name,
                        %error,
                        "failed to enqueue Set-Cookie into replay queue"
                    );
                }
            }
        }
    }

    fn cookies(&self, url: &Url) -> Option<HeaderValue> {
        let session = read_rwlock(&self.session, "session");
        let snapshot = &session.snapshot;
        if snapshot.cookies.platform_cookies.is_empty()
            && snapshot.cookies.canonical_cookies.is_empty()
        {
            if !same_origin_scope(&self.base_url, url) {
                return None;
            }
        } else if !same_site_scope(&self.base_url, url) {
            return None;
        }

        let cookies = build_cookie_header(&snapshot.cookies, &self.base_url, url);
        if cookies.is_empty() {
            return None;
        }

        HeaderValue::from_str(&cookies).ok()
    }
}

