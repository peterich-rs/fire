fn require_object(value: &Value, details: impl Into<String>) -> Result<(), serde_json::Error> {
    if value.is_object() {
        Ok(())
    } else {
        Err(invalid_json(details))
    }
}

fn optional_array_field<'a>(value: &'a Value, key: &str) -> Option<&'a [Value]> {
    match object_field(value, key) {
        Some(Value::Array(items)) => Some(items.as_slice()),
        Some(_) => {
            warn!(
                key,
                "chat payload field was not an array; treating as empty"
            );
            None
        }
        None => None,
    }
}

fn required_u64_field(
    value: &Value,
    key: &str,
    details: impl Into<String>,
) -> Result<u64, serde_json::Error> {
    integer_u64(object_field(value, key)).ok_or_else(|| invalid_json(details))
}

