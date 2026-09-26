use serde::{Deserialize, Serialize};

use crate::topic::HomeTopicListScope;
use crate::topic_detail_ui::{TopicHomeRowCountPatch, TopicHomeUnreadDecision};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[repr(u8)]
pub enum TopicNotificationLevel {
    Muted = 0,
    #[default]
    Regular = 1,
    Tracking = 2,
    Watching = 3,
}

impl TopicNotificationLevel {
    pub fn from_u32(value: u32) -> Self {
        match value {
            0 => Self::Muted,
            2 => Self::Tracking,
            3 => Self::Watching,
            _ => Self::Regular,
        }
    }

    pub fn as_u32(self) -> u32 {
        self as u32
    }

    pub fn is_at_least_tracking(self) -> bool {
        matches!(self, Self::Tracking | Self::Watching)
    }

    pub fn is_muted(self) -> bool {
        matches!(self, Self::Muted)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TrackedTopicState {
    pub topic_id: u64,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub category_id: Option<u64>,
    pub notification_level: TopicNotificationLevel,
    pub created_in_new_period: bool,
    pub is_seen: bool,
}

impl TrackedTopicState {
    pub fn is_new(&self) -> bool {
        self.last_read_post_number.is_none()
            && self.created_in_new_period
            && ((!self.notification_level.is_muted() && !self.is_seen)
                || self.notification_level.is_at_least_tracking())
    }

    pub fn is_unread(&self) -> bool {
        match self.last_read_post_number {
            Some(last_read) => {
                last_read < self.highest_post_number
                    && self.notification_level.is_at_least_tracking()
            }
            None => false,
        }
    }

    pub fn unread_decision(&self) -> TopicHomeUnreadDecision {
        if self.is_new() || self.last_read_post_number.is_none() {
            TopicHomeUnreadDecision::WhenLastReadMissing
        } else if self.is_unread() {
            TopicHomeUnreadDecision::StillUnread
        } else {
            TopicHomeUnreadDecision::CaughtUp
        }
    }

    pub fn unread_posts(&self) -> u32 {
        if self.is_new() {
            0
        } else {
            self.highest_post_number
                .saturating_sub(self.last_read_post_number.unwrap_or(0))
        }
    }

    pub fn new_posts(&self) -> u32 {
        u32::from(self.is_new())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TopicTrackingMessageType {
    NewTopic,
    Unread,
    Read,
    DismissNew,
    DismissNewPosts,
}

impl TopicTrackingMessageType {
    pub fn parse(value: &str) -> Option<Self> {
        match value.trim() {
            "new_topic" => Some(Self::NewTopic),
            "unread" => Some(Self::Unread),
            "read" => Some(Self::Read),
            "dismiss_new" => Some(Self::DismissNew),
            "dismiss_new_posts" => Some(Self::DismissNewPosts),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicTrackingPatch {
    pub topic_id: u64,
    pub unread: TopicHomeUnreadDecision,
    pub last_read_post_number: Option<u32>,
    pub highest_post_number: u32,
    pub unread_posts: u32,
    pub new_posts: u32,
}

impl TopicTrackingPatch {
    pub fn from_state(state: &TrackedTopicState) -> Self {
        Self {
            topic_id: state.topic_id,
            unread: state.unread_decision(),
            last_read_post_number: state.last_read_post_number,
            highest_post_number: state.highest_post_number,
            unread_posts: state.unread_posts(),
            new_posts: state.new_posts(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TopicListRowPatchBatch {
    pub scope: HomeTopicListScope,
    pub patches: Vec<TopicHomeRowCountPatch>,
}
