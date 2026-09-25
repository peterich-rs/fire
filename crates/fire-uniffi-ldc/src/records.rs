use fire_models::{
    CdkAuthorizationUrl, CdkUserInfo, LdcApprovalStatus, LdcAuthorizationUrl, LdcRewardRequest,
    LdcRewardResult, LdcUserInfo,
};

#[derive(uniffi::Record, Debug, Clone)]
pub struct LdcAuthorizationUrlState {
    pub url: String,
    pub state: String,
}

impl From<LdcAuthorizationUrl> for LdcAuthorizationUrlState {
    fn from(value: LdcAuthorizationUrl) -> Self {
        Self {
            url: value.url,
            state: value.state,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CdkAuthorizationUrlState {
    pub url: String,
    pub state: String,
}

impl From<CdkAuthorizationUrl> for CdkAuthorizationUrlState {
    fn from(value: CdkAuthorizationUrl) -> Self {
        Self {
            url: value.url,
            state: value.state,
        }
    }
}

#[derive(uniffi::Enum, Debug, Clone, Copy, PartialEq, Eq)]
pub enum LdcApprovalStatusKindState {
    Pending,
    Approved,
    Denied,
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LdcApprovalStatusState {
    pub kind: LdcApprovalStatusKindState,
    pub code: Option<String>,
    pub state: Option<String>,
}

impl From<LdcApprovalStatus> for LdcApprovalStatusState {
    fn from(value: LdcApprovalStatus) -> Self {
        match value {
            LdcApprovalStatus::Pending => Self {
                kind: LdcApprovalStatusKindState::Pending,
                code: None,
                state: None,
            },
            LdcApprovalStatus::Approved { code, state } => Self {
                kind: LdcApprovalStatusKindState::Approved,
                code: Some(code),
                state: Some(state),
            },
            LdcApprovalStatus::Denied => Self {
                kind: LdcApprovalStatusKindState::Denied,
                code: None,
                state: None,
            },
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LdcUserInfoState {
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

impl From<LdcUserInfo> for LdcUserInfoState {
    fn from(value: LdcUserInfo) -> Self {
        Self {
            id: value.id,
            username: value.username,
            nickname: value.nickname,
            trust_level: value.trust_level,
            avatar_url: value.avatar_url,
            total_receive: value.total_receive,
            total_payment: value.total_payment,
            total_transfer: value.total_transfer,
            total_community: value.total_community,
            community_balance: value.community_balance,
            available_balance: value.available_balance,
            pay_score: value.pay_score,
            is_pay_key: value.is_pay_key,
            is_admin: value.is_admin,
            remain_quota: value.remain_quota,
            pay_level: value.pay_level,
            daily_limit: value.daily_limit,
            gamification_score: value.gamification_score,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct CdkUserInfoState {
    pub id: u64,
    pub username: String,
    pub nickname: String,
    pub trust_level: u32,
    pub avatar_url: String,
    pub score: i64,
}

impl From<CdkUserInfo> for CdkUserInfoState {
    fn from(value: CdkUserInfo) -> Self {
        Self {
            id: value.id,
            username: value.username,
            nickname: value.nickname,
            trust_level: value.trust_level,
            avatar_url: value.avatar_url,
            score: value.score,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LdcRewardRequestState {
    pub user_id: u64,
    pub username: String,
    pub amount: f64,
    pub out_trade_no: String,
    pub remark: Option<String>,
}

impl From<LdcRewardRequestState> for LdcRewardRequest {
    fn from(value: LdcRewardRequestState) -> Self {
        Self {
            user_id: value.user_id,
            username: value.username,
            amount: value.amount,
            out_trade_no: value.out_trade_no,
            remark: value.remark,
        }
    }
}

#[derive(uniffi::Record, Debug, Clone)]
pub struct LdcRewardResultState {
    pub success: bool,
    pub trade_no: Option<String>,
    pub error_message: Option<String>,
}

impl From<LdcRewardResult> for LdcRewardResultState {
    fn from(value: LdcRewardResult) -> Self {
        Self {
            success: value.success,
            trade_no: value.trade_no,
            error_message: value.error_message,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{LdcApprovalStatusKindState, LdcApprovalStatusState};
    use fire_models::LdcApprovalStatus;

    #[test]
    fn approved_status_carries_code_and_state() {
        let state = LdcApprovalStatusState::from(LdcApprovalStatus::Approved {
            code: "code-123".to_string(),
            state: "state-456".to_string(),
        });

        assert_eq!(state.kind, LdcApprovalStatusKindState::Approved);
        assert_eq!(state.code.as_deref(), Some("code-123"));
        assert_eq!(state.state.as_deref(), Some("state-456"));
    }

    #[test]
    fn non_approved_statuses_do_not_carry_callback_fields() {
        let pending = LdcApprovalStatusState::from(LdcApprovalStatus::Pending);
        let denied = LdcApprovalStatusState::from(LdcApprovalStatus::Denied);

        assert_eq!(pending.kind, LdcApprovalStatusKindState::Pending);
        assert!(pending.code.is_none());
        assert!(pending.state.is_none());
        assert_eq!(denied.kind, LdcApprovalStatusKindState::Denied);
        assert!(denied.code.is_none());
        assert!(denied.state.is_none());
    }
}
