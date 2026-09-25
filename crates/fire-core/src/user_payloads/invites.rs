pub(crate) fn parse_invite_links_value(value: Value) -> Result<Vec<InviteLink>, serde_json::Error> {
    let mut items = Vec::new();
    match value {
        Value::Array(values) => items.extend(values),
        Value::Object(object) => {
            let invites = object
                .get("invites")
                .or_else(|| object.get("pending_invites"))
                .or_else(|| object.get("invited"))
                .or_else(|| object.get("pending"))
                .cloned();
            if let Some(Value::Array(values)) = invites {
                items.extend(values);
            } else if object.contains_key("invite")
                || object.contains_key("invite_link")
                || object.contains_key("invite_key")
                || object.contains_key("invite_url")
                || object.contains_key("url")
                || object.contains_key("link")
            {
                items.push(Value::Object(object));
            }
        }
        _ => {}
    }

    Ok(parse_array_items_lossy(
        &items,
        "invite link item",
        |item| parse_invite_link_value(item.clone()),
    ))
}

pub(crate) fn parse_invite_link_value(value: Value) -> Result<InviteLink, serde_json::Error> {
    let Value::Object(mut object) = value else {
        return Err(invalid_json("invite link response root was not an object"));
    };

    let invite_link = scalar_string(object.get("invite_link"))
        .or_else(|| scalar_string(object.get("invite_url")))
        .or_else(|| scalar_string(object.get("url")))
        .or_else(|| scalar_string(object.get("link")))
        .unwrap_or_default();

    let invite = match object.remove("invite") {
        Some(Value::Object(invite_object)) => {
            Some(parse_invite_link_details_object(&invite_object))
        }
        Some(_) => None,
        None => {
            if object.contains_key("invite_key")
                || object.contains_key("expires_at")
                || object.contains_key("max_redemptions_allowed")
            {
                Some(parse_invite_link_details_object(&object))
            } else {
                None
            }
        }
    };

    Ok(InviteLink {
        invite_link,
        invite,
    })
}

fn parse_invite_link_details_object(object: &serde_json::Map<String, Value>) -> InviteLinkDetails {
    InviteLinkDetails {
        id: integer_u64(object.get("id")),
        invite_key: scalar_string(object.get("invite_key")),
        max_redemptions_allowed: integer_u32(object.get("max_redemptions_allowed")),
        redemption_count: integer_u32(object.get("redemption_count")),
        expired: object.get("expired").map(|value| boolean(Some(value))),
        created_at: scalar_string(object.get("created_at")),
        expires_at: scalar_string(object.get("expires_at")),
    }
}

