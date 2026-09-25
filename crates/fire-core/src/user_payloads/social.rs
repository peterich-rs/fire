pub(crate) fn parse_follow_users_value(value: Value) -> Result<Vec<FollowUser>, serde_json::Error> {
    let list_value = match value {
        Value::Array(_) => value,
        Value::Object(ref obj) => obj
            .get("users")
            .or_else(|| obj.get("following"))
            .or_else(|| obj.get("followers"))
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
        _ => Value::Array(Vec::new()),
    };
    Ok(parse_array_items_lossy(
        array_items(Some(&list_value)),
        "follow user item",
        parse_follow_user_value,
    ))
}

fn parse_follow_user_value(value: &Value) -> Result<FollowUser, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("follow user item was not an object"))?;
    let id = integer_u64(object.get("id")).unwrap_or_default();
    let username = scalar_string(object.get("username")).unwrap_or_default();
    if id == 0 && username.is_empty() {
        return Err(invalid_json(
            "follow user item did not contain an id or username",
        ));
    }
    Ok(FollowUser {
        id,
        username,
        name: scalar_string(object.get("name")),
        avatar_template: scalar_string(object.get("avatar_template")),
    })
}

