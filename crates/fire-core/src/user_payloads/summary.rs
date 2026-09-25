pub(crate) fn parse_user_summary_value(
    value: Value,
) -> Result<UserSummaryResponse, serde_json::Error> {
    let root = match &value {
        Value::Object(obj) => obj,
        _ => return Err(invalid_json("user summary response root was not an object")),
    };

    let empty = Map::new();
    let summary_obj = root
        .get("user_summary")
        .and_then(Value::as_object)
        .unwrap_or(&empty);
    let stats = parse_user_summary_stats_object(summary_obj);
    let top_replies = parse_array_items_lossy(
        array_items(
            summary_obj
                .get("replies")
                .or_else(|| summary_obj.get("top_replies")),
        ),
        "profile summary reply",
        parse_profile_summary_reply_value,
    );
    let top_links = parse_array_items_lossy(
        array_items(
            summary_obj
                .get("links")
                .or_else(|| summary_obj.get("top_links")),
        ),
        "profile summary link",
        parse_profile_summary_link_value,
    );
    let top_categories = parse_array_items_lossy(
        array_items(summary_obj.get("top_categories")),
        "profile summary top category",
        parse_profile_summary_top_category_value,
    );
    let most_replied_to_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_replied_to_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let most_liked_by_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_liked_by_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let most_liked_users = parse_array_items_lossy(
        array_items(summary_obj.get("most_liked_users")),
        "profile summary user reference",
        parse_profile_summary_user_reference_value,
    );
    let top_topics = parse_array_items_lossy(
        array_items(root.get("topics")),
        "profile summary topic",
        parse_profile_summary_topic_value,
    );
    let badges =
        parse_array_items_lossy(array_items(root.get("badges")), "badge", parse_badge_item);

    Ok(UserSummaryResponse {
        stats,
        top_topics,
        top_replies,
        top_links,
        top_categories,
        most_replied_to_users,
        most_liked_by_users,
        most_liked_users,
        badges,
    })
}

fn parse_user_summary_stats_object(object: &Map<String, Value>) -> UserSummaryStats {
    UserSummaryStats {
        days_visited: integer_u32(object.get("days_visited")).unwrap_or_default(),
        posts_read_count: integer_u32(object.get("posts_read_count")).unwrap_or_default(),
        likes_received: integer_u32(object.get("likes_received")).unwrap_or_default(),
        likes_given: integer_u32(object.get("likes_given")).unwrap_or_default(),
        topic_count: integer_u32(object.get("topic_count")).unwrap_or_default(),
        post_count: integer_u32(object.get("post_count")).unwrap_or_default(),
        time_read: integer_u64(object.get("time_read")).unwrap_or_default(),
        bookmark_count: integer_u32(object.get("bookmark_count")).unwrap_or_default(),
    }
}

fn parse_profile_summary_topic_value(
    value: &Value,
) -> Result<ProfileSummaryTopic, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary topic item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary topic item did not contain an id"))?;
    Ok(ProfileSummaryTopic {
        id,
        title: scalar_string(object.get("title")).unwrap_or_default(),
        slug: scalar_string(object.get("slug")),
        like_count: integer_u32(object.get("like_count")).unwrap_or_default(),
        category_id: integer_u64(object.get("category_id")),
        created_at: scalar_string(object.get("created_at")),
    })
}

fn parse_profile_summary_reply_value(
    value: &Value,
) -> Result<ProfileSummaryReply, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary reply item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary reply item did not contain an id"))?;
    let topic_id = integer_u64(object.get("topic_id"))
        .ok_or_else(|| invalid_json("profile summary reply item did not contain a topic_id"))?;
    Ok(ProfileSummaryReply {
        id,
        topic_id,
        title: scalar_string(object.get("title")),
        like_count: integer_u32(object.get("like_count")).unwrap_or_default(),
        created_at: scalar_string(object.get("created_at")),
        post_number: integer_u32(object.get("post_number")),
    })
}

fn parse_profile_summary_link_value(
    value: &Value,
) -> Result<ProfileSummaryLink, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary link item was not an object"))?;
    let url = scalar_string(object.get("url"))
        .ok_or_else(|| invalid_json("profile summary link item did not contain a url"))?;
    Ok(ProfileSummaryLink {
        url,
        title: scalar_string(object.get("title")),
        clicks: integer_u32(object.get("clicks")).unwrap_or_default(),
        topic_id: integer_u64(object.get("topic_id")),
        post_number: integer_u32(object.get("post_number")),
    })
}

fn parse_profile_summary_top_category_value(
    value: &Value,
) -> Result<ProfileSummaryTopCategory, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary top category item was not an object"))?;
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("profile summary top category item did not contain an id"))?;
    Ok(ProfileSummaryTopCategory {
        id,
        name: scalar_string(object.get("name")),
        topic_count: integer_u32(object.get("topic_count")).unwrap_or_default(),
        post_count: integer_u32(object.get("post_count")).unwrap_or_default(),
    })
}

fn parse_profile_summary_user_reference_value(
    value: &Value,
) -> Result<ProfileSummaryUserReference, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("profile summary user reference item was not an object"))?;
    let id = integer_u64(object.get("id")).unwrap_or_default();
    let username = scalar_string(object.get("username")).unwrap_or_default();
    if id == 0 && username.is_empty() {
        return Err(invalid_json(
            "profile summary user reference item did not contain an id or username",
        ));
    }
    Ok(ProfileSummaryUserReference {
        id,
        username,
        avatar_template: scalar_string(object.get("avatar_template")),
        count: integer_u32(object.get("count")).unwrap_or_default(),
    })
}

