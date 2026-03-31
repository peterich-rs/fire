use serde_json::Value;

pub(crate) fn integer_u64(value: Option<&Value>) -> Option<u64> {
    match value? {
        Value::Number(value) => value.as_u64(),
        Value::String(value) => value.trim().parse::<u64>().ok(),
        Value::Bool(value) => Some(u64::from(*value)),
        _ => None,
    }
}

pub(crate) fn positive_u64(value: Option<&Value>) -> Option<u64> {
    integer_u64(value).filter(|value| *value > 0)
}

pub(crate) fn integer_u32(value: Option<&Value>) -> Option<u32> {
    integer_u64(value).and_then(|value| u32::try_from(value).ok())
}

pub(crate) fn positive_u32(value: Option<&Value>) -> Option<u32> {
    integer_u32(value).filter(|value| *value > 0)
}

pub(crate) fn integer_i64(value: Option<&Value>) -> Option<i64> {
    match value? {
        Value::Number(value) => value.as_i64(),
        Value::String(value) => value.trim().parse::<i64>().ok(),
        Value::Bool(value) => Some(i64::from(*value)),
        _ => None,
    }
}

pub(crate) fn integer_i32(value: Option<&Value>) -> Option<i32> {
    match value? {
        Value::Number(value) => value.as_i64().and_then(|value| i32::try_from(value).ok()),
        Value::String(value) => value.trim().parse::<i32>().ok(),
        Value::Bool(value) => Some(i32::from(*value)),
        _ => None,
    }
}

pub(crate) fn boolean(value: Option<&Value>) -> bool {
    match value {
        Some(Value::Bool(value)) => *value,
        Some(Value::Number(value)) => value.as_i64().is_some_and(|value| value != 0),
        Some(Value::String(value)) => matches!(value.trim(), "true" | "1"),
        _ => false,
    }
}
