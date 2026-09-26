use super::*;

#[tokio::test]
async fn fetch_topic_list_surfaces_cloudflare_challenge_error() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cloudflare challenge should surface as an error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list",
            ..
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_retries_once_after_cloudflare_challenge_completion() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|request| async move {
        assert_eq!(request.operation, "fetch topic list");
        assert!(request.request_url.contains("/latest.json"));
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("new-clearance".into()),
            cookies: vec![
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "new-clearance".into(),
                    domain: Some("linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
                PlatformCookie {
                    name: "cf_clearance".into(),
                    value: "stale-clearance".into(),
                    domain: Some(".linux.do".into()),
                    path: Some("/".into()),
                    expires_at_unix_ms: None,
                    same_site: None,
                },
            ],
            browser_user_agent: Some("FireBrowser/1.0".into()),
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("cloudflare challenge should retry once");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    let retry_request = &requests[1];
    let retry_request_lower = retry_request.to_ascii_lowercase();
    assert!(
        retry_request_lower.contains("cookie: cf_clearance=new-clearance"),
        "retry request should send fresh cf_clearance:\n{retry_request}"
    );
    assert!(
        !retry_request.contains("stale-clearance"),
        "retry request must not send stale cf_clearance:\n{retry_request}"
    );
    assert!(
        retry_request_lower.contains("user-agent: firebrowser/1.0"),
        "retry request should use challenge WebView user agent:\n{retry_request}"
    );
    let snapshot = core.snapshot();
    assert_eq!(
        snapshot.cookies.cf_clearance.as_deref(),
        Some("new-clearance")
    );
    assert_eq!(
        snapshot.browser_user_agent.as_deref(),
        Some("FireBrowser/1.0")
    );
}

#[tokio::test]
async fn fetch_topic_list_retries_after_page_clear_without_fresh_clearance() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: None,
            cookies: vec![],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("page-clear without a new cookie should still retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
}

#[tokio::test]
async fn page_clear_with_login_cookies_rebuilds_missing_bootstrap() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
        raw_text_response(200, &sample_home_html()),
        raw_json_response(200, "application/json", r#"{"csrf":"csrf-token"}"#),
        raw_text_response(200, &sample_home_html()),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_platform_cookies(vec![
        PlatformCookie {
            name: "_t".into(),
            value: "token".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        },
        PlatformCookie {
            name: "_forum_session".into(),
            value: "forum".into(),
            domain: None,
            path: None,
            expires_at_unix_ms: None,
            same_site: None,
        },
    ]);
    assert!(core.snapshot().bootstrap.current_username.is_none());
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: None,
            cookies: vec![],
            browser_user_agent: None,
        }
    });

    let _ = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("page-clear retry should succeed");

    for _ in 0..80 {
        if core.snapshot().bootstrap.current_username.as_deref() == Some("alice") {
            break;
        }
        sleep(Duration::from_millis(25)).await;
    }

    let snapshot = core.snapshot();
    let _ = server.shutdown().await;
    assert_eq!(
        snapshot.bootstrap.current_username.as_deref(),
        Some("alice")
    );
    assert!(snapshot.bootstrap.has_preloaded_data);
}

#[tokio::test]
async fn retry_still_challenged_marks_incumbent_and_skips_second_presentation() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let _ = core.apply_platform_cookies(vec![PlatformCookie {
        name: "cf_clearance".into(),
        value: "working".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }]);
    let challenge_calls = Arc::new(AtomicUsize::new(0));
    {
        let challenge_calls = Arc::clone(&challenge_calls);
        core.set_cloudflare_challenge_handler(move |_| {
            challenge_calls.fetch_add(1, Ordering::SeqCst);
            async move {
                fire_models::CloudflareChallengeResult {
                    completed: true,
                    user_cancelled: false,
                    fresh_cf_clearance: None,
                    cookies: vec![],
                    browser_user_agent: None,
                }
            }
        });
    }

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("retry that is still CF should fail");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list",
            ..
        }
    ));
    assert_eq!(requests.len(), 2);
    assert_eq!(challenge_calls.load(Ordering::SeqCst), 1);
    assert_eq!(
        core.snapshot()
            .cookies
            .last_challenged_cf_clearance
            .as_deref(),
        Some("working")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_synthesizes_confirmed_clearance_when_snapshot_missing() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("confirmed-clearance".into()),
            cookies: vec![],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("confirmed clearance should be synthesized for retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("cookie: cf_clearance=confirmed-clearance"),
        "retry request should send synthesized cf_clearance:\n{}",
        requests[1]
    );
    assert_eq!(
        core.snapshot().cookies.cf_clearance.as_deref(),
        Some("confirmed-clearance")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_synthesizes_confirmed_clearance_when_snapshot_scope_is_wrong() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("wrong-scope-clearance".into()),
            cookies: vec![PlatformCookie {
                name: "cf_clearance".into(),
                value: "wrong-scope-clearance".into(),
                domain: Some("unrelated.example".into()),
                path: Some("/challenge".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("confirmed wrong-scope clearance should be synthesized for retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert!(
        requests[1]
            .to_ascii_lowercase()
            .contains("cookie: cf_clearance=wrong-scope-clearance"),
        "retry request should send synthesized cf_clearance:\n{}",
        requests[1]
    );
    let snapshot = core.snapshot();
    let clearance_cookie = snapshot
        .cookies
        .platform_cookies
        .iter()
        .find(|cookie| cookie.name == "cf_clearance")
        .expect("cf_clearance platform cookie");
    assert_eq!(clearance_cookie.path.as_deref(), Some("/"));
    assert_ne!(
        clearance_cookie.domain.as_deref(),
        Some("unrelated.example")
    );
}

#[tokio::test]
async fn cloudflare_challenge_retry_accepts_platform_confirmed_existing_clearance() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let snapshot = core.apply_platform_cookies(vec![PlatformCookie {
        name: "cf_clearance".into(),
        value: "stable-clearance".into(),
        domain: Some("linux.do".into()),
        path: Some("/".into()),
        expires_at_unix_ms: None,
        same_site: None,
    }]);
    assert_eq!(
        snapshot.cookies.cf_clearance.as_deref(),
        Some("stable-clearance")
    );
    core.set_cloudflare_challenge_handler(|_| async move {
        fire_models::CloudflareChallengeResult {
            completed: true,
            user_cancelled: false,
            fresh_cf_clearance: Some("stable-clearance".into()),
            cookies: vec![PlatformCookie {
                name: "cf_clearance".into(),
                value: "stable-clearance".into(),
                domain: Some("linux.do".into()),
                path: Some("/".into()),
                expires_at_unix_ms: None,
                same_site: None,
            }],
            browser_user_agent: None,
        }
    });

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("platform-confirmed clearance should unblock retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert_eq!(
        core.snapshot().cookies.cf_clearance.as_deref(),
        Some("stable-clearance")
    );
}

#[tokio::test]
async fn business_request_is_blocked_while_cloudflare_challenge_is_in_progress() {
    let latest = sample_latest_json();
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_json_response(200, "application/json", &latest),
        raw_json_response(200, "application/json", &latest),
        raw_json_response(200, "application/json", &latest),
        raw_json_response(200, "application/json", &latest),
        raw_json_response(200, "application/json", &latest),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let challenge_started = Arc::new(Notify::new());
    let release_challenge = Arc::new(Notify::new());
    {
        let challenge_started = Arc::clone(&challenge_started);
        let release_challenge = Arc::clone(&release_challenge);
        core.set_cloudflare_challenge_handler(move |_| {
            let challenge_started = Arc::clone(&challenge_started);
            let release_challenge = Arc::clone(&release_challenge);
            async move {
                challenge_started.notify_waiters();
                release_challenge.notified().await;
                fire_models::CloudflareChallengeResult {
                    completed: true,
                    user_cancelled: false,
                    fresh_cf_clearance: Some("new-clearance".into()),
                    cookies: vec![PlatformCookie {
                        name: "cf_clearance".into(),
                        value: "new-clearance".into(),
                        domain: Some("linux.do".into()),
                        path: Some("/".into()),
                        expires_at_unix_ms: None,
                        same_site: None,
                    }],
                    browser_user_agent: None,
                }
            }
        });
    }

    let first_core = core.clone();
    let first = tokio::spawn(async move {
        first_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });
    challenge_started.notified().await;

    let parked_core = core.clone();
    let parked = tokio::spawn(async move {
        parked_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });
    tokio::time::sleep(Duration::from_millis(40)).await;
    assert_eq!(
        server.request_count(),
        1,
        "later requests stay parked until the recovery epoch ends"
    );

    release_challenge.notify_waiters();
    let response = first
        .await
        .expect("task should finish")
        .expect("first request should retry after challenge");
    let parked_response = tokio::time::timeout(Duration::from_secs(5), parked)
        .await
        .expect("parked request should resume")
        .expect("task should finish")
        .expect("parked request should run after recovery");
    let _ = server.shutdown().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(parked_response.rows.len(), 1);
}

#[tokio::test]
async fn concurrent_cloudflare_challenges_join_and_retry_after_shared_success() {
    let challenge_body =
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#;
    let server = TestServer::spawn_scripted(vec![
        // Delay both CF bodies so the two clients are already in-flight before
        // either enters the challenge owner/join path.
        TestServerStep::delayed(
            raw_cloudflare_challenge_response(403, challenge_body),
            Duration::from_millis(80),
        ),
        TestServerStep::delayed(
            raw_cloudflare_challenge_response(403, challenge_body),
            Duration::from_millis(80),
        ),
        TestServerStep::immediate(raw_json_response(
            200,
            "application/json",
            &sample_latest_json(),
        )),
        TestServerStep::immediate(raw_json_response(
            200,
            "application/json",
            &sample_latest_json(),
        )),
    ])
    .await
    .expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let challenge_calls = Arc::new(AtomicUsize::new(0));
    let challenge_started = Arc::new(Notify::new());
    let release_challenge = Arc::new(Notify::new());
    {
        let challenge_calls = Arc::clone(&challenge_calls);
        let challenge_started = Arc::clone(&challenge_started);
        let release_challenge = Arc::clone(&release_challenge);
        core.set_cloudflare_challenge_handler(move |_| {
            let challenge_calls = Arc::clone(&challenge_calls);
            let challenge_started = Arc::clone(&challenge_started);
            let release_challenge = Arc::clone(&release_challenge);
            async move {
                challenge_calls.fetch_add(1, Ordering::SeqCst);
                challenge_started.notify_waiters();
                release_challenge.notified().await;
                fire_models::CloudflareChallengeResult {
                    completed: true,
                    user_cancelled: false,
                    fresh_cf_clearance: Some("joined-clearance".into()),
                    cookies: vec![PlatformCookie {
                        name: "cf_clearance".into(),
                        value: "joined-clearance".into(),
                        domain: Some("linux.do".into()),
                        path: Some("/".into()),
                        expires_at_unix_ms: None,
                        same_site: None,
                    }],
                    browser_user_agent: None,
                }
            }
        });
    }

    let first_core = core.clone();
    let first = tokio::spawn(async move {
        first_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });
    let second_core = core.clone();
    let second = tokio::spawn(async move {
        second_core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
    });

    challenge_started.notified().await;
    // Let the second CF victim reach the shared join wait.
    sleep(Duration::from_millis(40)).await;
    release_challenge.notify_waiters();

    let first_response = first
        .await
        .expect("first task")
        .expect("first request should succeed after shared challenge");
    let second_response = second
        .await
        .expect("second task")
        .expect("joined request should retry after shared challenge");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(first_response.rows.len(), 1);
    assert_eq!(second_response.rows.len(), 1);
    assert_eq!(challenge_calls.load(Ordering::SeqCst), 1);
    assert_eq!(requests.len(), 4);
}

#[tokio::test]
async fn foreground_retry_bypasses_cloudflare_failure_cooldown() {
    let responses = vec![
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
        raw_cloudflare_challenge_response(
            403,
            r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
        ),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let challenge_calls = Arc::new(AtomicUsize::new(0));
    {
        let challenge_calls = Arc::clone(&challenge_calls);
        core.set_cloudflare_challenge_handler(move |_| {
            challenge_calls.fetch_add(1, Ordering::SeqCst);
            async move {
                fire_models::CloudflareChallengeResult {
                    completed: false,
                    user_cancelled: false,
                    fresh_cf_clearance: None,
                    cookies: vec![],
                    browser_user_agent: None,
                }
            }
        });
    }

    for _ in 0..2 {
        let error = core
            .fetch_topic_list(TopicListQuery {
                kind: TopicListKind::Latest,
                ..TopicListQuery::default()
            })
            .await
            .expect_err("challenge should remain unresolved");
        assert!(matches!(
            error,
            FireCoreError::CloudflareChallenge {
                operation: "fetch topic list",
                ..
            }
        ));
    }
    let requests = server.shutdown_with_requests().await;

    assert_eq!(requests.len(), 2);
    assert_eq!(challenge_calls.load(Ordering::SeqCst), 2);
}

#[tokio::test]
async fn fetch_topic_list_self_heals_unauthorized_with_sweep_retry() {
    let responses = vec![
        raw_json_response(
            401,
            "application/json",
            r#"{"errors":["session cookie state is stale"]}"#,
        ),
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(Mutex::new(Vec::new()));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            let calls = Arc::clone(&calls);
            async move {
                calls
                    .lock()
                    .expect("calls mutex")
                    .push((request.phase, request.attempt));
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("self-healed request should retry");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 2);
    assert_eq!(
        calls.lock().expect("calls mutex").as_slice(),
        &[(CookieSelfHealingPhase::Sweep, 1)]
    );
}

#[tokio::test]
async fn fetch_topic_list_does_not_self_heal_cloudflare_challenge_without_handler() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            calls.fetch_add(1, Ordering::SeqCst);
            async move {
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cloudflare challenge must not trigger cookie healing");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list",
            ..
        }
    ));
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(requests.len(), 1);
}

#[tokio::test]
async fn fetch_topic_list_does_not_self_heal_explicit_not_logged_in() {
    let body = r#"{"errors":["You need to log in."],"error_type":"not_logged_in"}"#;
    let responses = vec![raw_json_response(401, "application/json", body)];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(AtomicUsize::new(0));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            calls.fetch_add(1, Ordering::SeqCst);
            async move {
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("explicit not_logged_in must surface as login required");
    let requests = server.shutdown_with_requests().await;

    assert!(matches!(error, FireCoreError::LoginRequired { .. }));
    assert_eq!(calls.load(Ordering::SeqCst), 0);
    assert_eq!(requests.len(), 1);
}

#[tokio::test]
async fn fetch_topic_list_self_healing_escalates_to_nuclear_reset() {
    let unauthorized = raw_json_response(
        401,
        "application/json",
        r#"{"errors":["session cookie state is stale"]}"#,
    );
    let responses = vec![
        unauthorized.clone(),
        unauthorized.clone(),
        unauthorized,
        raw_json_response(200, "application/json", &sample_latest_json()),
    ];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let calls = Arc::new(Mutex::new(Vec::new()));
    {
        let calls = Arc::clone(&calls);
        core.set_cookie_self_healing_handler(move |request| {
            let calls = Arc::clone(&calls);
            async move {
                calls
                    .lock()
                    .expect("calls mutex")
                    .push((request.phase, request.attempt));
                CookieSelfHealingResult {
                    completed: true,
                    session_epoch: request.session_epoch,
                }
            }
        });
    }

    let response = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect("nuclear reset should retry once");
    let requests = server.shutdown_with_requests().await;

    assert_eq!(response.rows.len(), 1);
    assert_eq!(requests.len(), 4);
    assert_eq!(
        calls.lock().expect("calls mutex").as_slice(),
        &[
            (CookieSelfHealingPhase::Sweep, 1),
            (CookieSelfHealingPhase::Sweep, 2),
            (CookieSelfHealingPhase::NuclearReset, 1),
        ]
    );
}

#[tokio::test]
async fn fetch_topic_list_surfaces_rate_limited_cloudflare_challenge_error() {
    let responses = vec![raw_cloudflare_challenge_response(
        429,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("429 Cloudflare challenge should surface as a challenge error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list",
            ..
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_accepts_cf_mitigated_challenge_without_html_content_type() {
    let body = "managed challenge";
    let responses = vec![format!(
        "HTTP/1.1 429 TEST\r\nServer: cloudflare\r\nContent-Type: text/plain; charset=utf-8\r\nCf-Mitigated: challenge\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cf-mitigated challenge should not require HTML content type");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::CloudflareChallenge {
            operation: "fetch topic list",
            ..
        }
    ));
}

#[tokio::test]
async fn fetch_topic_list_does_not_treat_non_cloudflare_403_body_as_challenge() {
    let responses = vec![raw_json_response(
        403,
        "text/html; charset=utf-8",
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("non-cloudflare 403 should surface as a plain HTTP error");
    let _ = server.shutdown().await;

    assert!(matches!(
        error,
        FireCoreError::HttpStatus {
            operation: "fetch topic list",
            status: 403,
            ..
        }
    ));
}

#[tokio::test]
async fn cloudflare_epoch_suppresses_login_recovery() {
    let responses = vec![raw_cloudflare_challenge_response(
        403,
        r#"<html><head><title>Just a moment...</title></head><body>__cf_chl_opt</body></html>"#,
    )];
    let server = TestServer::spawn(responses).await.expect("server");
    let core = FireCore::new(FireCoreConfig {
        base_url: server.base_url(),
        workspace_path: None,
    })
    .expect("core");
    let epoch_before = core.session_epoch();
    let core_for_handler = core.clone();
    core.set_cloudflare_challenge_handler(move |_request| {
        let core = core_for_handler.clone();
        async move {
            assert_eq!(
                core.snapshot().recovery,
                fire_models::SessionRecovery::Cloudflare
            );
            assert_eq!(core.request_read_path_login("during-cf"), 0);
            assert!(core.snapshot().read_path_login_request.is_none());
            core.passive_logout(fire_models::PassiveLogoutTrigger {
                source: "during-cf".into(),
                signal_strength: fire_models::SignalStrength::Strong,
                cookie_diagnostic: String::new(),
            })
            .await
            .expect("passive logout is suppressed");
            assert_eq!(core.session_epoch(), epoch_before);
            fire_models::CloudflareChallengeResult {
                completed: false,
                user_cancelled: true,
                fresh_cf_clearance: None,
                cookies: Vec::new(),
                browser_user_agent: None,
            }
        }
    });

    let error = core
        .fetch_topic_list(TopicListQuery {
            kind: TopicListKind::Latest,
            ..TopicListQuery::default()
        })
        .await
        .expect_err("cancelled challenge");
    let _ = server.shutdown().await;
    assert!(matches!(error, FireCoreError::CloudflareChallenge { .. }));
    assert_eq!(core.snapshot().recovery, fire_models::SessionRecovery::Idle);
}
