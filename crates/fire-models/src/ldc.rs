use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LdcUserInfo {
    pub id: u64,
    pub username: String,
    pub nickname: String,
    pub trust_level: u32,
    pub avatar_url: String,
    pub total_receive: String,
    pub total_payment: String,
    pub total_transfer: String,
    pub total_community: String,
    pub community_balance: String,
    pub available_balance: String,
    pub pay_score: u32,
    pub is_pay_key: bool,
    pub is_admin: bool,
    pub remain_quota: String,
    pub pay_level: u32,
    pub daily_limit: u32,
    pub gamification_score: Option<i64>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CdkUserInfo {
    pub id: u64,
    pub username: String,
    pub nickname: String,
    pub trust_level: u32,
    pub avatar_url: String,
    pub score: i64,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LdcAuthorizationUrl {
    pub url: String,
    pub state: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CdkAuthorizationUrl {
    pub url: String,
    pub state: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum LdcApprovalStatus {
    Pending,
    Approved { code: String, state: String },
    Denied,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LdcPayment {
    pub id: u64,
    pub amount: String,
    pub description: Option<String>,
    pub created_at: Option<String>,
    pub payment_type: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LdcPaymentList {
    pub payments: Vec<LdcPayment>,
    pub has_more: bool,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct LdcRewardRequest {
    pub user_id: u64,
    pub username: String,
    pub amount: f64,
    pub out_trade_no: String,
    pub remark: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LdcRewardResult {
    pub success: bool,
    pub trade_no: Option<String>,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectTrustLevelProgress {
    pub current_level: u32,
    pub next_level: Option<u32>,
    pub days_visited: u32,
    pub topics_read: u32,
    pub posts_read: u32,
    pub time_read: u64,
    pub likes_given: u32,
    pub likes_received: u32,
    pub topics_entered: u32,
    pub posts_created: u32,
    pub requirements: Vec<TrustLevelRequirement>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrustLevelRequirement {
    pub name: String,
    pub current: String,
    pub required: String,
    pub satisfied: bool,
}

#[cfg(test)]
mod tests {
    use super::{CdkUserInfo, LdcUserInfo};
    use serde_json::json;

    #[test]
    fn ldc_user_info_matches_documented_payload_shape() {
        let info: LdcUserInfo = serde_json::from_value(json!({
            "id": 1,
            "username": "example",
            "nickname": "nickname",
            "trust_level": 2,
            "avatar_url": "https://example.com/avatar.png",
            "total_receive": "100",
            "total_payment": "50",
            "total_transfer": "10",
            "total_community": "5",
            "community_balance": "3",
            "available_balance": "42",
            "pay_score": 80,
            "is_pay_key": false,
            "is_admin": false,
            "remain_quota": "100",
            "pay_level": 1,
            "daily_limit": 50,
            "gamification_score": 1234
        }))
        .expect("LDC user-info payload should deserialize");

        assert_eq!(info.username, "example");
        assert_eq!(info.available_balance, "42");
        assert_eq!(info.daily_limit, 50);
        assert_eq!(info.gamification_score, Some(1234));
    }

    #[test]
    fn cdk_user_info_uses_score_without_ldc_balance_fields() {
        let info = CdkUserInfo {
            id: 1,
            username: "example".into(),
            nickname: "nickname".into(),
            trust_level: 2,
            avatar_url: "https://example.com/avatar.png".into(),
            score: 100,
        };

        let value = serde_json::to_value(info).expect("CDK user info should serialize");
        assert_eq!(value["score"], 100);
        assert!(value.get("available_balance").is_none());
        assert!(value.get("total_payment").is_none());
    }
}
