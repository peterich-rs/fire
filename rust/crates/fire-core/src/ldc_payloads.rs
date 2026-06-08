use fire_models::{CdkUserInfo, LdcAuthorizationUrl, LdcRewardResult, LdcUserInfo};
use serde_json::Value;
use tracing::warn;

use crate::json_helpers::{
    boolean, integer_i64, integer_u32, integer_u64, invalid_json, object_field, scalar_string,
};

pub(crate) fn parse_ldc_authorization_url_value(
    value: Value,
) -> Result<LdcAuthorizationUrl, serde_json::Error> {
    let data = required_data_string(&value, "authorization url response")?;
    let state = url::Url::parse(&data)
        .ok()
        .and_then(|url| {
            url.query_pairs()
                .find(|(key, _)| key == "state")
                .map(|(_, value)| value.into_owned())
        })
        .unwrap_or_default();
    Ok(LdcAuthorizationUrl { url: data, state })
}

pub(crate) fn parse_ldc_user_info_value(value: Value) -> Result<LdcUserInfo, serde_json::Error> {
    let data = required_data_object(&value, "LDC user-info response")?;
    Ok(LdcUserInfo {
        id: required_u64_field(data, "id", "LDC user-info did not contain a valid id")?,
        username: required_string_field(
            data,
            "username",
            "LDC user-info did not contain a valid username",
        )?,
        nickname: required_string_field(
            data,
            "nickname",
            "LDC user-info did not contain a valid nickname",
        )?,
        trust_level: required_u32_field(
            data,
            "trust_level",
            "LDC user-info did not contain a valid trust_level",
        )?,
        avatar_url: required_string_field(
            data,
            "avatar_url",
            "LDC user-info did not contain a valid avatar_url",
        )?,
        total_receive: required_string_field(
            data,
            "total_receive",
            "LDC user-info did not contain a valid total_receive",
        )?,
        total_payment: required_string_field(
            data,
            "total_payment",
            "LDC user-info did not contain a valid total_payment",
        )?,
        total_transfer: required_string_field(
            data,
            "total_transfer",
            "LDC user-info did not contain a valid total_transfer",
        )?,
        total_community: required_string_field(
            data,
            "total_community",
            "LDC user-info did not contain a valid total_community",
        )?,
        community_balance: required_string_field(
            data,
            "community_balance",
            "LDC user-info did not contain a valid community_balance",
        )?,
        available_balance: required_string_field(
            data,
            "available_balance",
            "LDC user-info did not contain a valid available_balance",
        )?,
        pay_score: required_u32_field(
            data,
            "pay_score",
            "LDC user-info did not contain a valid pay_score",
        )?,
        is_pay_key: boolean(object_field(data, "is_pay_key")),
        is_admin: boolean(object_field(data, "is_admin")),
        remain_quota: required_string_field(
            data,
            "remain_quota",
            "LDC user-info did not contain a valid remain_quota",
        )?,
        pay_level: required_u32_field(
            data,
            "pay_level",
            "LDC user-info did not contain a valid pay_level",
        )?,
        daily_limit: required_u32_field(
            data,
            "daily_limit",
            "LDC user-info did not contain a valid daily_limit",
        )?,
        gamification_score: integer_i64(object_field(data, "gamification_score")),
    })
}

pub(crate) fn parse_cdk_user_info_value(value: Value) -> Result<CdkUserInfo, serde_json::Error> {
    let data = required_data_object(&value, "CDK user-info response")?;
    Ok(CdkUserInfo {
        id: required_u64_field(data, "id", "CDK user-info did not contain a valid id")?,
        username: required_string_field(
            data,
            "username",
            "CDK user-info did not contain a valid username",
        )?,
        nickname: required_string_field(
            data,
            "nickname",
            "CDK user-info did not contain a valid nickname",
        )?,
        trust_level: required_u32_field(
            data,
            "trust_level",
            "CDK user-info did not contain a valid trust_level",
        )?,
        avatar_url: required_string_field(
            data,
            "avatar_url",
            "CDK user-info did not contain a valid avatar_url",
        )?,
        score: required_i64_field(data, "score", "CDK user-info did not contain a valid score")?,
    })
}

pub(crate) fn parse_ldc_reward_result_value(
    value: Value,
) -> Result<LdcRewardResult, serde_json::Error> {
    let Value::Object(object) = value else {
        return Err(invalid_json("LDC reward response root was not an object"));
    };

    let error_message =
        scalar_string(object.get("error_msg")).or_else(|| scalar_string(object.get("msg")));
    let trade_no = object.get("data").and_then(|data| {
        object_field(data, "trade_no")
            .and_then(|value| scalar_string(Some(value)))
            .or_else(|| object_field(data, "tradeNo").and_then(|value| scalar_string(Some(value))))
    });
    let success = object.get("data").is_some() && error_message.is_none();

    Ok(LdcRewardResult {
        success,
        trade_no,
        error_message,
    })
}

fn required_data_string(value: &Value, context: &str) -> Result<String, serde_json::Error> {
    let Value::Object(_) = value else {
        return Err(invalid_json(format!("{context} root was not an object")));
    };

    scalar_string(object_field(value, "data"))
        .ok_or_else(|| invalid_json(format!("{context} did not contain a valid data string")))
}

fn required_data_object<'a>(
    value: &'a Value,
    context: &str,
) -> Result<&'a Value, serde_json::Error> {
    let Value::Object(_) = value else {
        return Err(invalid_json(format!("{context} root was not an object")));
    };

    match object_field(value, "data") {
        Some(Value::Object(_)) => object_field(value, "data")
            .ok_or_else(|| invalid_json(format!("{context} did not contain a data object"))),
        Some(_) => Err(invalid_json(format!(
            "{context} data field was not an object"
        ))),
        None => Err(invalid_json(format!(
            "{context} did not contain a data object"
        ))),
    }
}

fn required_string_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<String, serde_json::Error> {
    scalar_string(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

fn required_u64_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<u64, serde_json::Error> {
    integer_u64(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

fn required_u32_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<u32, serde_json::Error> {
    integer_u32(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

fn required_i64_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<i64, serde_json::Error> {
    integer_i64(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

pub(crate) fn extract_oauth_approve_path(html: &str) -> Option<String> {
    let document = scraper::Html::parse_document(html);
    let selector = match scraper::Selector::parse(r#"a[href*="/oauth2/approve/"]"#) {
        Ok(selector) => selector,
        Err(error) => {
            warn!(%error, "failed to build OAuth approval link selector");
            return None;
        }
    };

    document
        .select(&selector)
        .find_map(|element| element.value().attr("href"))
        .and_then(normalize_approve_path)
}

fn normalize_approve_path(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(url) = url::Url::parse(trimmed) {
        if url.domain() != Some("linux.do") && url.host_str() != Some("connect.linux.do") {
            return None;
        }
        return Some(format!(
            "{}{}",
            url.path(),
            url.query()
                .map(|query| format!("?{query}"))
                .unwrap_or_default()
        ));
    }

    if !trimmed.starts_with("/oauth2/approve/") {
        return None;
    }
    Some(trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parses_ldc_user_info_from_data_envelope() {
        let value = json!({
            "data": {
                "id": "1",
                "username": "example",
                "nickname": "nickname",
                "trust_level": "2",
                "avatar_url": "https://example.com/avatar.png",
                "total_receive": "100",
                "total_payment": "50",
                "total_transfer": "10",
                "total_community": "5",
                "community_balance": "3",
                "available_balance": "42",
                "pay_score": "80",
                "is_pay_key": true,
                "is_admin": false,
                "remain_quota": "100",
                "pay_level": 1,
                "daily_limit": "50",
                "gamification_score": "1234"
            }
        });

        let info = parse_ldc_user_info_value(value).unwrap();
        assert_eq!(info.id, 1);
        assert_eq!(info.available_balance, "42");
        assert_eq!(info.daily_limit, 50);
        assert_eq!(info.gamification_score, Some(1234));
    }

    #[test]
    fn parses_cdk_user_info_without_ldc_fields() {
        let value = json!({
            "data": {
                "id": 1,
                "username": "example",
                "nickname": "nickname",
                "trust_level": 2,
                "avatar_url": "https://example.com/avatar.png",
                "score": 200
            }
        });

        let info = parse_cdk_user_info_value(value).unwrap();
        assert_eq!(info.score, 200);
    }

    #[test]
    fn parses_authorization_url_and_state() {
        let value = json!({
            "data": "https://connect.linux.do/oauth2/authorize?client_id=abc&state=state-123"
        });

        let auth = parse_ldc_authorization_url_value(value).unwrap();
        assert_eq!(auth.state, "state-123");
        assert!(auth
            .url
            .starts_with("https://connect.linux.do/oauth2/authorize"));
    }

    #[test]
    fn extracts_approval_path_from_html() {
        let path = extract_oauth_approve_path(
            r#"<html><body><a href="/oauth2/approve/abc">Approve</a></body></html>"#,
        );

        assert_eq!(path.as_deref(), Some("/oauth2/approve/abc"));
    }

    #[test]
    fn parses_reward_success_and_failure_shapes() {
        let success = parse_ldc_reward_result_value(json!({
            "data": { "trade_no": "trade-1" }
        }))
        .unwrap();
        assert!(success.success);
        assert_eq!(success.trade_no.as_deref(), Some("trade-1"));

        let failure = parse_ldc_reward_result_value(json!({
            "msg": "invalid credentials"
        }))
        .unwrap();
        assert!(!failure.success);
        assert_eq!(
            failure.error_message.as_deref(),
            Some("invalid credentials")
        );
    }
}
