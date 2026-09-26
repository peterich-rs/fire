use std::time::{Duration, SystemTime, UNIX_EPOCH};

use fire_models::{BootstrapArtifacts, MessageBusClientMode};
use http::HeaderMap;
use time::{format_description::well_known::Rfc2822, OffsetDateTime};

use super::super::network::header_value;

pub(super) const DEFAULT_POLLING_INTERVAL: Duration = Duration::from_millis(3_000);
pub(super) const DEFAULT_BACKGROUND_POLLING_INTERVAL: Duration = Duration::from_millis(60_000);
pub(super) const RATE_LIMIT_MIN_DELAY: Duration = Duration::from_secs(15);
pub(super) const CHUNKED_BACKOFF_SUCCESSES: u32 = 30;
pub(super) const FIRST_CHUNK_TIMEOUT: Duration = Duration::from_secs(8);

pub(super) fn target_poll_interval(
    bootstrap: &BootstrapArtifacts,
    mode: MessageBusClientMode,
    app_backgrounded: bool,
) -> Duration {
    let background = app_backgrounded || mode == MessageBusClientMode::IosBackground;
    let millis = if background {
        if bootstrap.background_polling_interval_ms == 0 {
            DEFAULT_BACKGROUND_POLLING_INTERVAL
        } else {
            Duration::from_millis(u64::from(bootstrap.background_polling_interval_ms))
        }
    } else if bootstrap.polling_interval_ms == 0 {
        DEFAULT_POLLING_INTERVAL
    } else {
        Duration::from_millis(u64::from(bootstrap.polling_interval_ms))
    };
    millis.max(Duration::from_millis(1))
}

pub(super) fn success_wait(elapsed: Duration, target: Duration) -> Duration {
    target.saturating_sub(elapsed)
}

pub(super) fn should_send_dont_chunk(
    enable_chunked_encoding: bool,
    chunked_backoff_remaining: u32,
    app_backgrounded: bool,
    mode: MessageBusClientMode,
) -> bool {
    !enable_chunked_encoding
        || chunked_backoff_remaining > 0
        || app_backgrounded
        || mode == MessageBusClientMode::IosBackground
}

pub(super) fn rate_limit_delay(retry_after: Option<Duration>, jitter: Duration) -> Duration {
    retry_after
        .unwrap_or(RATE_LIMIT_MIN_DELAY)
        .max(RATE_LIMIT_MIN_DELAY)
        .saturating_add(jitter.min(Duration::from_secs(1)))
}

pub(super) fn parse_retry_after(headers: &HeaderMap, now: SystemTime) -> Option<Duration> {
    let raw = header_value(headers, "retry-after")?;
    let trimmed = raw.trim();
    if let Ok(seconds) = trimmed.parse::<f64>() {
        if seconds.is_finite() && seconds >= 0.0 {
            return Some(Duration::from_millis((seconds * 1000.0) as u64));
        }
        return None;
    }
    parse_http_date(trimmed)?.duration_since(now).ok()
}

fn parse_http_date(value: &str) -> Option<SystemTime> {
    let normalized = value
        .trim()
        .trim_end_matches(" GMT")
        .trim_end_matches(" gmt")
        .to_string()
        + " +0000";
    OffsetDateTime::parse(&normalized, &Rfc2822)
        .ok()
        .map(SystemTime::from)
}

pub(super) fn rate_limit_jitter(seed: u64) -> Duration {
    Duration::from_millis(seed % 1001)
}

pub(super) fn now_system_time() -> SystemTime {
    SystemTime::now()
}

#[allow(dead_code)]
pub(super) fn unix_epoch() -> SystemTime {
    UNIX_EPOCH
}

#[cfg(test)]
mod tests {
    use fire_models::BootstrapArtifacts;
    use http::{HeaderMap, HeaderValue};

    use super::*;

    fn bootstrap(polling: u32, background: u32, chunked: bool) -> BootstrapArtifacts {
        BootstrapArtifacts {
            polling_interval_ms: polling,
            background_polling_interval_ms: background,
            enable_chunked_encoding: chunked,
            ..BootstrapArtifacts::default()
        }
    }

    #[test]
    fn success_wait_subtracts_elapsed_from_target() {
        assert_eq!(
            success_wait(Duration::from_millis(200), Duration::from_millis(5_000)),
            Duration::from_millis(4_800)
        );
        assert_eq!(
            success_wait(Duration::from_secs(4), Duration::from_secs(3)),
            Duration::ZERO
        );
    }

    #[test]
    fn background_and_ios_background_use_background_interval() {
        let artifacts = bootstrap(3_000, 45_000, true);
        assert_eq!(
            target_poll_interval(&artifacts, MessageBusClientMode::Foreground, false),
            Duration::from_millis(3_000)
        );
        assert_eq!(
            target_poll_interval(&artifacts, MessageBusClientMode::Foreground, true),
            Duration::from_millis(45_000)
        );
        assert_eq!(
            target_poll_interval(&artifacts, MessageBusClientMode::IosBackground, false),
            Duration::from_millis(45_000)
        );
    }

    #[test]
    fn dont_chunk_follows_site_backoff_and_background() {
        assert!(!should_send_dont_chunk(
            true,
            0,
            false,
            MessageBusClientMode::Foreground
        ));
        assert!(should_send_dont_chunk(
            false,
            0,
            false,
            MessageBusClientMode::Foreground
        ));
        assert!(should_send_dont_chunk(
            true,
            4,
            false,
            MessageBusClientMode::Foreground
        ));
        assert!(should_send_dont_chunk(
            true,
            0,
            true,
            MessageBusClientMode::Foreground
        ));
        assert!(should_send_dont_chunk(
            true,
            0,
            false,
            MessageBusClientMode::IosBackground
        ));
    }

    #[test]
    fn rate_limit_delay_respects_retry_after_floor() {
        assert_eq!(
            rate_limit_delay(Some(Duration::from_secs(20)), Duration::from_millis(250)),
            Duration::from_millis(20_250)
        );
        assert_eq!(
            rate_limit_delay(Some(Duration::from_secs(5)), Duration::ZERO),
            Duration::from_secs(15)
        );
        assert_eq!(
            rate_limit_delay(None, Duration::from_millis(10)),
            Duration::from_millis(15_010)
        );
    }

    #[test]
    fn parse_retry_after_accepts_seconds_and_http_date() {
        let mut headers = HeaderMap::new();
        headers.insert("retry-after", HeaderValue::from_static("20"));
        assert_eq!(
            parse_retry_after(&headers, SystemTime::now()),
            Some(Duration::from_secs(20))
        );

        headers.insert(
            "retry-after",
            HeaderValue::from_static("Wed, 21 Oct 2015 07:28:00 GMT"),
        );
        let now = parse_http_date("Wed, 21 Oct 2015 07:27:40 GMT").expect("date");
        assert_eq!(
            parse_retry_after(&headers, now),
            Some(Duration::from_secs(20))
        );

        headers.insert("retry-after", HeaderValue::from_static("not-a-date"));
        assert_eq!(parse_retry_after(&headers, SystemTime::now()), None);
    }
}
