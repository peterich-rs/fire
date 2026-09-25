pub(crate) fn parse_user_actions_value(value: Value) -> Result<Vec<UserAction>, serde_json::Error> {
    let actions_value = match value {
        Value::Object(ref obj) if obj.contains_key("user_actions") => obj
            .get("user_actions")
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
        Value::Array(_) => value,
        _ => Value::Array(Vec::new()),
    };
    Ok(parse_array_items_lossy(
        array_items(Some(&actions_value)),
        "user action item",
        parse_user_action_value,
    ))
}

fn parse_user_action_value(value: &Value) -> Result<UserAction, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("user action item was not an object"))?;
    Ok(UserAction {
        action_type: integer_i32(object.get("action_type")),
        topic_id: integer_u64(object.get("topic_id")),
        post_id: integer_u64(object.get("post_id")),
        post_number: integer_u32(object.get("post_number")),
        title: scalar_string(object.get("title")),
        slug: scalar_string(object.get("slug")),
        username: scalar_string(object.get("username")),
        acting_username: scalar_string(object.get("acting_username")),
        acting_avatar_template: scalar_string(object.get("acting_avatar_template")),
        category_id: integer_u64(object.get("category_id")),
        excerpt: scalar_string(object.get("excerpt")),
        created_at: scalar_string(object.get("created_at")),
    })
}

