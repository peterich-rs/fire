pub(crate) fn parse_badge_value(value: Value) -> Result<Badge, serde_json::Error> {
    let badge_value = match value {
        Value::Object(ref obj) if obj.contains_key("badge") => {
            obj.get("badge").cloned().unwrap_or(value.clone())
        }
        other => other,
    };
    parse_badge_item(&badge_value)
}

fn parse_badge_item(value: &Value) -> Result<Badge, serde_json::Error> {
    let object = value
        .as_object()
        .ok_or_else(|| invalid_json("badge response root was not an object"))?;
    Ok(Badge {
        id: integer_u64(object.get("id")).unwrap_or_default(),
        name: scalar_string(object.get("name")).unwrap_or_default(),
        description: scalar_string(object.get("description")),
        badge_type_id: integer_u32(object.get("badge_type_id")).unwrap_or_default(),
        image_url: scalar_string(object.get("image_url")),
        icon: scalar_string(object.get("icon")),
        slug: scalar_string(object.get("slug")),
        grant_count: integer_u32(object.get("grant_count")).unwrap_or_default(),
        long_description: scalar_string(object.get("long_description")),
    })
}

