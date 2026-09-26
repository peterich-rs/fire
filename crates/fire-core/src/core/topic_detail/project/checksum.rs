use fire_models::{
    TopicDetailAuthorDisplay, TopicDetailBoostDisplay, TopicDetailPollDisplay,
    TopicDetailReplyUserDisplay, TopicDetailUiRow,
};

// Layout and interaction together cover every `TopicDetailUiRow` field except
// the tree shape, which `structure_changed` compares directly. Hosts treat
// equal checksums as an unchanged row.
//
// New data fields must be classified here. Exhaustive destructure (no `..`)
// makes an unclassified field a compile error (E0027).

pub(crate) fn row_checksums(row: &TopicDetailUiRow) -> (u64, u64) {
    let TopicDetailUiRow {
        post_id,
        post_number,
        root_post_number,
        parent_post_number,
        depth,
        has_children,
        is_last_sibling,
        descendant_count,
        author,
        presentation,
        layout_checksum: _,
        interaction_checksum: _,
        author_band_checksum: _,
        text_band_checksum: _,
        actions_band_checksum: _,
        reactions_band_checksum: _,
        created_at,
        updated_at,
        post_type,
        reply_count,
        reply_to_username,
        reply_to_user,
        like_count,
        reactions,
        current_reaction_id,
        polls,
        boosts,
        accepted_answer,
        can_accept_answer,
        can_unaccept_answer,
        can_edit,
        can_delete,
        can_recover,
        can_boost,
        bookmarked,
        bookmark_id,
        bookmark_name,
        bookmark_reminder_at,
        hidden,
        is_mutating,
        is_loading_reply_context,
        is_original_post,
    } = row;

    let _shape = (
        post_id,
        post_number,
        root_post_number,
        parent_post_number,
        depth,
        has_children,
        is_last_sibling,
        descendant_count,
        reply_count,
        is_original_post,
    );

    let mut layout = Hasher::new();
    layout.u64(*post_id);
    layout.u64(*post_type as u64);
    hash_author(&mut layout, author);
    layout.sep();
    layout.str(reply_to_username.as_deref().unwrap_or(""));
    hash_reply_user(&mut layout, reply_to_user.as_ref());
    layout.sep();
    match presentation.get() {
        Some(document) => layout.u64(document.presentation().checksum),
        None => layout.str("pending"),
    }
    layout.sep();
    hash_polls(&mut layout, polls);
    layout.sep();
    hash_boosts(&mut layout, boosts);
    layout.sep();
    layout.bool(reactions.is_empty());
    layout.sep();
    // These flags change the action row, so they change measured height.
    layout.bool(*hidden);
    layout.bool(*can_edit);
    layout.bool(*can_delete);
    layout.bool(*can_recover);
    layout.bool(*can_boost);

    let mut interaction = Hasher::new();
    interaction.u64(u64::from(*post_number));
    interaction.sep();
    interaction.str(&author.username);
    interaction.sep();
    interaction.str(author.avatar_template.as_deref().unwrap_or(""));
    interaction.sep();
    interaction.str(created_at.as_deref().unwrap_or(""));
    interaction.sep();
    interaction.str(updated_at.as_deref().unwrap_or(""));
    interaction.sep();
    interaction.u64(u64::from(*like_count));
    interaction.sep();
    interaction.u64(u64::from(*reply_count));
    interaction.sep();
    for reaction in reactions {
        interaction.str(&reaction.id);
        interaction.sep();
        interaction.str(reaction.kind.as_deref().unwrap_or(""));
        interaction.sep();
        interaction.u64(u64::from(reaction.count));
        interaction.sep();
        hash_optional_bool(&mut interaction, reaction.can_undo);
        interaction.sep();
    }
    interaction.str(current_reaction_id.as_deref().unwrap_or(""));
    interaction.sep();
    interaction.bool(*accepted_answer);
    interaction.bool(*can_accept_answer);
    interaction.bool(*can_unaccept_answer);
    interaction.bool(*can_edit);
    interaction.bool(*can_delete);
    interaction.bool(*can_recover);
    interaction.bool(*can_boost);
    interaction.bool(*hidden);
    interaction.bool(*bookmarked);
    interaction.u64(bookmark_id.unwrap_or(0));
    interaction.str(bookmark_name.as_deref().unwrap_or(""));
    interaction.str(bookmark_reminder_at.as_deref().unwrap_or(""));
    interaction.bool(*is_mutating);
    interaction.bool(*is_loading_reply_context);

    (layout.finish(), interaction.finish())
}

#[allow(dead_code)]
pub(crate) fn layout_checksum(row: &TopicDetailUiRow) -> u64 {
    row_checksums(row).0
}

pub(crate) fn author_band_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hash_author(&mut hasher, &row.author);
    hasher.sep();
    hasher.str(row.author.avatar_template.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.str(row.created_at.as_deref().unwrap_or(""));
    hasher.sep();
    hasher.u64(u64::from(row.post_number));
    hasher.bool(row.accepted_answer);
    hasher.finish()
}

pub(crate) fn text_band_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    match row.presentation.get() {
        Some(document) => hasher.u64(document.presentation().checksum),
        None => hasher.str("pending"),
    }
    hasher.sep();
    hash_polls(&mut hasher, &row.polls);
    hasher.sep();
    hash_boosts(&mut hasher, &row.boosts);
    hasher.bool(row.hidden);
    hasher.finish()
}

pub(crate) fn actions_band_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.bool(row.can_edit);
    hasher.bool(row.can_delete);
    hasher.bool(row.can_recover);
    hasher.bool(row.can_boost);
    hasher.bool(row.hidden);
    hasher.bool(row.bookmarked);
    hasher.bool(row.is_mutating);
    hasher.finish()
}

pub(crate) fn reactions_band_checksum(row: &TopicDetailUiRow) -> u64 {
    let mut hasher = Hasher::new();
    hasher.u64(u64::from(row.like_count));
    hasher.sep();
    hasher.str(row.current_reaction_id.as_deref().unwrap_or(""));
    for reaction in &row.reactions {
        hasher.str(&reaction.id);
        hasher.sep();
        hasher.u64(u64::from(reaction.count));
        hash_optional_bool(&mut hasher, reaction.can_undo);
    }
    hasher.finish()
}

#[allow(dead_code)]
pub(crate) fn interaction_checksum(row: &TopicDetailUiRow) -> u64 {
    row_checksums(row).1
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
            hasher.str(&option.plain_text);
            hasher.u64(u64::from(option.votes));
        }
        hasher.sep();
    }
}

fn hash_boosts(hasher: &mut Hasher, boosts: &[TopicDetailBoostDisplay]) {
    for boost in boosts {
        hasher.u64(boost.id);
        hasher.u64(boost.user.id);
        hasher.str(&boost.user.username);
        hasher.str(boost.user.name.as_deref().unwrap_or(""));
        hasher.str(boost.user.avatar_template.as_deref().unwrap_or(""));
        hasher.str(&boost.display_text);
        match boost.presentation.get() {
            Some(document) => hasher.u64(document.presentation().checksum),
            None => hasher.str("pending"),
        }
        hasher.bool(boost.can_delete);
        hasher.bool(boost.can_flag);
        match boost.user_flag_status {
            Some(status) => hasher.u64(u64::from(status as u32)),
            None => hasher.str(""),
        }
        for flag in &boost.available_flags {
            hasher.str(flag);
        }
        hasher.sep();
    }
}

fn hash_reply_user(hasher: &mut Hasher, user: Option<&TopicDetailReplyUserDisplay>) {
    let Some(user) = user else {
        hasher.str("");
        return;
    };
    hasher.str(&user.username);
    hasher.str(user.name.as_deref().unwrap_or(""));
    hasher.str(user.avatar_template.as_deref().unwrap_or(""));
}

fn hash_optional_bool(hasher: &mut Hasher, value: Option<bool>) {
    match value {
        Some(value) => hasher.bool(value),
        None => hasher.str(""),
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
