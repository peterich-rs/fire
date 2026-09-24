use fire_models::{
    TopicDetailAuthorDisplay, TopicDetailBoostDisplay, TopicDetailPollDisplay, TopicDetailUiRow,
};

pub(crate) fn layout_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.u64(row.post_id);
    hash_author(&mut hasher, &row.author);
    hasher.sep();
    match row.presentation.get() {
        Some(document) => hasher.u64(document.presentation().checksum),
        None => hasher.str("pending"),
    }
    hasher.sep();
    hash_polls(&mut hasher, &row.polls);
    hasher.sep();
    hash_boosts(&mut hasher, &row.boosts);
    hasher.sep();
    hasher.bool(row.reactions.is_empty());
    hasher.finish()
}

pub(crate) fn interaction_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.u64(u64::from(row.post_number));
    hasher.sep();
    hasher.str(&row.author.username);
    hasher.sep();
    hasher.str(row.author.avatar_template.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(row.created_at.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(row.updated_at.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(u64::from(row.like_count));
    hasher.sep();
    hasher.u64(u64::from(row.reply_count));
    hasher.sep();
    for reaction in &row.reactions {
        hasher.str(&reaction.id);
        hasher.sep();
        hasher.str(reaction.kind.as_deref().unwrap_or(""));
        hasher.sep();
        hasher.u64(u64::from(reaction.count));
        hasher.sep();
        match reaction.can_undo {
            Some(value) => hasher.bool(value),
            None => hasher.str(""),
        }
        hasher.sep();
    }
    hasher.str(row.current_reaction_id.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.bool(row.accepted_answer);
    hasher.bool(row.can_edit);
    hasher.bool(row.can_delete);
    hasher.bool(row.can_recover);
    hasher.bool(row.hidden);
    hasher.bool(row.bookmarked);
    hasher.u64(row.bookmark_id.unwrap_or(0));
    hasher.str(row.bookmark_name.as_deref().unwrap_or(""));
    hasher.str(row.bookmark_reminder_at.as_deref().unwrap_or(""));
    hasher.bool(row.is_mutating);
    hasher.bool(row.is_loading_reply_context);
    hasher.finish()
}

fn hash_author(hasher: &mut Hasher, author: &TopicDetailAuthorDisplay) {
    hasher.str(&author.username);
    hasher.sep();
    hasher.str(author.name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.user_title.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.primary_group_name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_name.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(author.user_id.unwrap_or(0));
    hasher.sep();
    hasher.str(author.flair_url.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_bg_color.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(author.flair_color.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(author.flair_group_id.unwrap_or(0));
    hasher.sep();
    hasher.bool(author.admin);
    hasher.bool(author.moderator);
    hasher.bool(author.group_moderator);
    hasher.str(author.user_status_emoji.as_deref().unwrap_or(""));
    hasher.str(author.user_status_description.as_deref().unwrap_or(""));
}

fn hash_polls(hasher: &mut Hasher, polls: &[TopicDetailPollDisplay]) {
    for poll in polls {
        hasher.u64(poll.id);
        hasher.str(&poll.name);
        hasher.str(&poll.kind);
        hasher.str(&poll.status);
        hasher.str(&poll.results);
        hasher.u64(u64::from(poll.voters));
        for vote in &poll.user_votes {
            hasher.str(vote);
        }
        for option in &poll.options {
            hasher.str(&option.id);
            hasher.str(&option.html);
            hasher.u64(u64::from(option.votes));
        }
        hasher.sep();
    }
}

fn hash_boosts(hasher: &mut Hasher, boosts: &[TopicDetailBoostDisplay]) {
    for boost in boosts {
        hasher.u64(boost.id);
        hasher.str(&boost.user.username);
        hasher.str(boost.user.name.as_deref().unwrap_or(""));
        hasher.str(&boost.display_text);
        let plain = boost
            .presentation
            .get()
            .map(|document| document.presentation().plain_text.clone())
            .unwrap_or_default();
        hasher.str(&plain);
        hasher.bool(boost.can_delete);
        hasher.bool(boost.can_flag);
        hasher.sep();
    }
}

struct Hasher(u64);

impl Hasher {
    fn new() -> Self {
        Self(0xcbf29ce484222325)
    }

    fn byte(&mut self, byte: u8) {
        self.0 ^= u64::from(byte);
        self.0 = self.0.wrapping_mul(0x100000001b3);
    }

    fn str(&mut self, value: &str) {
        for byte in value.as_bytes() {
            self.byte(*byte);
        }
        self.byte(0);
    }

    fn u64(&mut self, value: u64) {
        for byte in value.to_le_bytes() {
            self.byte(byte);
        }
    }

    fn bool(&mut self, value: bool) {
        self.byte(u8::from(value));
    }

    fn sep(&mut self) {
        self.byte(0x1f);
    }

    fn finish(self) -> u64 {
        self.0
    }
}
