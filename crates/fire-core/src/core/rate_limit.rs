use std::time::Duration;

pub(crate) const RATE_LIMIT_FALLBACK_COOLDOWN: Duration = Duration::from_secs(10);

pub(crate) fn parse_rate_limit_cooldown(body: &str) -> Option<Duration> {
    let value = serde_json::from_str::<serde_json::Value>(body).ok()?;
    let extras = value.get("extras")?.as_object()?;
    for field in ["wait_seconds", "time_left"] {
        let seconds = extras.get(field).and_then(parse_rate_limit_seconds)?;
        if seconds > 0.0 {
            return Some(Duration::from_secs_f64(seconds));
        }
    }
    None
}

fn parse_rate_limit_seconds(value: &serde_json::Value) -> Option<f64> {
    match value {
        serde_json::Value::Number(number) => number.as_f64(),
        serde_json::Value::String(value) => value.trim().parse::<f64>().ok(),
        _ => None,
    }
}
