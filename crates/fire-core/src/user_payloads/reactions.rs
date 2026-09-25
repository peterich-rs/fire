pub(crate) fn parse_user_reactions_value(
    value: Value,
) -> Result<UserReactionsResponse, serde_json::Error> {
    let reactions_value = match value {
        Value::Array(_) => value,
        Value::Object(ref obj) => obj
            .get("reactions")
            .or_else(|| obj.get("posts"))
            .cloned()
            .unwrap_or(Value::Array(Vec::new())),
        _ => Value::Array(Vec::new()),
    };

    Ok(UserReactionsResponse {
        reactions: parse_array_items_lossy(
            array_items(Some(&reactions_value)),
            "user reaction item",
            parse_user_reaction_value,
        ),
    })
}

fn parse_user_reaction_value(value: &Value) -> Result<UserReaction, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("user reaction item was not an object"))?;
    let post_object = object.get("post").and_then(Value::as_object);
    let reaction_object = object.get("reaction").and_then(Value::as_object);
    let id = integer_u64(object.get("id"))
        .ok_or_else(|| invalid_json("user reaction item did not contain an id"))?;
    let post_id = integer_u64(object.get("post_id"))
        .or_else(|| post_object.and_then(|post| integer_u64(post.get("id"))))
        .ok_or_else(|| invalid_json("user reaction item did not contain a post_id"))?;

    Ok(UserReaction {
        id,
        post_id,
        topic_id: post_object
            .and_then(|post| integer_u64(post.get("topic_id")))
            .or_else(|| integer_u64(object.get("topic_id")))
            .unwrap_or_default(),
        post_number: post_object
            .and_then(|post| integer_u32(post.get("post_number")))
            .or_else(|| integer_u32(object.get("post_number"))),
        topic_title: post_object
            .and_then(|post| scalar_string(post.get("topic_title")))
            .or_else(|| scalar_string(object.get("topic_title")))
            .or_else(|| scalar_string(object.get("title"))),
        excerpt: post_object
            .and_then(|post| scalar_string(post.get("excerpt")))
            .or_else(|| scalar_string(object.get("excerpt"))),
        reaction_value: reaction_object
            .and_then(|reaction| scalar_string(reaction.get("reaction_value")))
            .or_else(|| scalar_string(object.get("reaction_value"))),
        created_at: scalar_string(object.get("created_at")),
    })
}

