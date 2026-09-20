//! `cf_clearance` incumbent stickiness.
//!
//! Candidate liveness cannot be judged on the client. A value that just hit a
//! rate-limit challenge may still be valid, and leftover CHIPS copies often
//! expire later than the working incumbent. Replacement is allowed only when
//! the jar incumbent is empty, expired, inside the 30-minute rotation window,
//! just challenged, or replaced by a verified challenge value.

use std::time::Duration;

pub const CF_CLEARANCE_COOKIE_NAME: &str = "cf_clearance";
pub const CF_CLEARANCE_ROTATION_WINDOW: Duration = Duration::from_secs(30 * 60);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CfClearanceReplaceDecision {
    Allow,
    SkipSameValue,
    SkipHealthyIncumbent,
}

pub fn normalize_cf_clearance_value(value: &str) -> String {
    percent_decode_once(value.trim())
}

pub fn is_cf_clearance_cookie_name(name: &str) -> bool {
    name.eq_ignore_ascii_case(CF_CLEARANCE_COOKIE_NAME)
}

pub fn extract_cf_clearance_from_cookie_header(header: &str) -> Option<String> {
    header.split(';').find_map(|part| {
        let part = part.trim();
        let (name, value) = part.split_once('=')?;
        if !is_cf_clearance_cookie_name(name) {
            return None;
        }
        let normalized = normalize_cf_clearance_value(value);
        (!normalized.is_empty()).then_some(normalized)
    })
}

pub fn evaluate_cf_clearance_replacement(
    incumbent_value: Option<&str>,
    incumbent_expires_at_unix_ms: Option<i64>,
    last_challenged_value: Option<&str>,
    candidate_value: &str,
    verified: bool,
    now_unix_ms: i64,
) -> CfClearanceReplaceDecision {
    let candidate = normalize_cf_clearance_value(candidate_value);
    if candidate.is_empty() {
        return CfClearanceReplaceDecision::Allow;
    }

    let incumbent = incumbent_value
        .map(normalize_cf_clearance_value)
        .filter(|value| !value.is_empty());
    let Some(incumbent) = incumbent else {
        return CfClearanceReplaceDecision::Allow;
    };

    if verified {
        return CfClearanceReplaceDecision::Allow;
    }

    if incumbent == candidate {
        return CfClearanceReplaceDecision::SkipSameValue;
    }

    if let Some(expires_at_unix_ms) = incumbent_expires_at_unix_ms {
        if expires_at_unix_ms <= now_unix_ms {
            return CfClearanceReplaceDecision::Allow;
        }
        let remaining = expires_at_unix_ms.saturating_sub(now_unix_ms);
        if remaining <= CF_CLEARANCE_ROTATION_WINDOW.as_millis() as i64 {
            return CfClearanceReplaceDecision::Allow;
        }
    }

    let challenged = last_challenged_value
        .map(normalize_cf_clearance_value)
        .filter(|value| !value.is_empty());
    if challenged.as_deref() == Some(incumbent.as_str()) {
        return CfClearanceReplaceDecision::Allow;
    }

    CfClearanceReplaceDecision::SkipHealthyIncumbent
}

fn percent_decode_once(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut output = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        if bytes[index] == b'%' && index + 2 < bytes.len() {
            if let (Some(high), Some(low)) =
                (hex_digit(bytes[index + 1]), hex_digit(bytes[index + 2]))
            {
                output.push((high << 4) | low);
                index += 3;
                continue;
            }
        }
        output.push(bytes[index]);
        index += 1;
    }
    String::from_utf8_lossy(&output).into_owned()
}

fn hex_digit(byte: u8) -> Option<u8> {
    match byte {
        b'0'..=b'9' => Some(byte - b'0'),
        b'a'..=b'f' => Some(byte - b'a' + 10),
        b'A'..=b'F' => Some(byte - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_700_000_000_000;
    const HOUR: i64 = 60 * 60 * 1000;

    #[test]
    fn empty_incumbent_allows_any_candidate() {
        assert_eq!(
            evaluate_cf_clearance_replacement(None, None, None, "next", false, NOW),
            CfClearanceReplaceDecision::Allow
        );
    }

    #[test]
    fn same_value_is_idempotent() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("abc"),
                Some(NOW + HOUR),
                None,
                "abc",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::SkipSameValue
        );
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("abc"),
                Some(NOW + HOUR),
                None,
                "abc",
                true,
                NOW
            ),
            CfClearanceReplaceDecision::Allow
        );
    }

    #[test]
    fn healthy_incumbent_rejects_different_value() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("working"),
                Some(NOW + HOUR),
                None,
                "leftover-chips",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::SkipHealthyIncumbent
        );
    }

    #[test]
    fn later_expiry_does_not_win() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("working"),
                Some(NOW + HOUR),
                None,
                "older-copy-with-later-ttl",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::SkipHealthyIncumbent
        );
    }

    #[test]
    fn expired_or_near_expiry_allows_rotation() {
        assert_eq!(
            evaluate_cf_clearance_replacement(Some("old"), Some(NOW - 1), None, "next", false, NOW),
            CfClearanceReplaceDecision::Allow
        );
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("old"),
                Some(NOW + 10 * 60 * 1000),
                None,
                "next",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::Allow
        );
    }

    #[test]
    fn challenged_incumbent_allows_replacement() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("dead"),
                Some(NOW + HOUR),
                Some("dead"),
                "fresh",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::Allow
        );
    }

    #[test]
    fn challenged_other_value_does_not_open_rotation() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("working"),
                Some(NOW + HOUR),
                Some("someone-else"),
                "fresh",
                false,
                NOW
            ),
            CfClearanceReplaceDecision::SkipHealthyIncumbent
        );
    }

    #[test]
    fn verified_value_replaces_healthy_incumbent() {
        assert_eq!(
            evaluate_cf_clearance_replacement(
                Some("working"),
                Some(NOW + HOUR),
                None,
                "verified",
                true,
                NOW
            ),
            CfClearanceReplaceDecision::Allow
        );
    }

    #[test]
    fn extracts_clearance_from_cookie_header() {
        assert_eq!(
            extract_cf_clearance_from_cookie_header(
                "_t=token; cf_clearance=abc.def; _forum_session=s"
            ),
            Some("abc.def".into())
        );
        assert_eq!(
            extract_cf_clearance_from_cookie_header("my_cf_clearance=bad; _t=x"),
            None
        );
    }
}
