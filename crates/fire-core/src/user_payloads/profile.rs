pub(crate) fn parse_user_profile_value(value: Value) -> Result<UserProfile, serde_json::Error> {
    let user_value = match value {
        Value::Object(ref obj) if obj.contains_key("user") => {
            obj.get("user").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    let Value::Object(object) = user_value else {
        return Err(invalid_json("user profile response root was not an object"));
    };

    Ok(UserProfile {
        id: integer_u64(object.get("id")).unwrap_or_default(),
        username: scalar_string(object.get("username")).unwrap_or_default(),
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
        trust_level: integer_u32(object.get("trust_level")),
        bio_cooked: scalar_string(object.get("bio_cooked")),
        bio_plain_text: scalar_string(object.get("bio_cooked")).and_then(|html| {
            let plain = crate::plain_text_from_html(&html);
            let trimmed = plain.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        }),
        created_at: scalar_string(object.get("created_at")),
        last_seen_at: scalar_string(object.get("last_seen_at")),
        last_posted_at: scalar_string(object.get("last_posted_at")),
        flair_name: scalar_string(object.get("flair_name")),
        flair_url: scalar_string(object.get("flair_url")),
        flair_bg_color: scalar_string(object.get("flair_bg_color")),
        flair_color: scalar_string(object.get("flair_color")),
        profile_background_upload_url: scalar_string(object.get("profile_background_upload_url")),
        card_background_upload_url: scalar_string(object.get("card_background_upload_url")),
        total_followers: integer_u32(object.get("total_followers")),
        total_following: integer_u32(object.get("total_following")),
        can_follow: optional_boolean(object.get("can_follow")),
        is_followed: optional_boolean(object.get("is_followed")),
        can_send_private_message_to_user: optional_boolean(
            object.get("can_send_private_message_to_user"),
        ),
        muted: optional_boolean(object.get("muted")),
        ignored: optional_boolean(object.get("ignored")),
        can_mute_user: optional_boolean(object.get("can_mute_user")),
        can_ignore_user: optional_boolean(object.get("can_ignore_user")),
        gamification_score: integer_u32(object.get("gamification_score")),
        suspended_till: scalar_string(object.get("suspended_till")),
        silenced_till: scalar_string(object.get("silenced_till")),
    })
}

