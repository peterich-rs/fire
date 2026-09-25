use std::{
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use fire_models::TopicTimingsRequest;
use tracing::info;

use super::super::{network::expect_success, rate_limit, FireCore};
use crate::error::FireCoreError;
use http::Method;

#[derive(Default)]
pub(crate) struct FireTopicTimingRuntime {
    cooldown_until: Option<Instant>,
}

impl FireCore {
    pub async fn report_topic_timings(
        &self,
        input: TopicTimingsRequest,
    ) -> Result<bool, FireCoreError> {
        info!(
            topic_id = input.topic_id,
            topic_time_ms = input.topic_time_ms,
            timings_count = input.timings.len(),
            "reporting topic timings"
        );
        if is_timing_rate_limited(&self.topic_timing) {
            info!(
                topic_id = input.topic_id,
                "topic timings skipped: rate limit cooldown active"
            );
            return Ok(false);
        }

        let mut fields = vec![
            ("topic_id".to_string(), input.topic_id.to_string()),
            ("topic_time".to_string(), input.topic_time_ms.to_string()),
        ];
        for timing in input.timings {
            fields.push((
                format!("timings[{}]", timing.post_number),
                timing.milliseconds.to_string(),
            ));
        }

        let (trace_id, response) = self
            .execute_api_request_with_csrf_retry("report topic timings", || {
                self.build_form_request_with_headers(
                    "report topic timings",
                    Method::POST,
                    "/topics/timings",
                    fields.clone(),
                    vec![
                        ("X-SILENCE-LOGGER", "true".to_string()),
                        ("Discourse-Background", "true".to_string()),
                    ],
                    true,
                )
            })
            .await?;
        let response = match expect_success(self, "report topic timings", trace_id, response).await
        {
            Ok(response) => response,
            Err(FireCoreError::HttpStatus {
                status: 429, body, ..
            }) => {
                let cooldown = rate_limit::parse_rate_limit_cooldown(&body)
                    .unwrap_or(rate_limit::RATE_LIMIT_FALLBACK_COOLDOWN);
                apply_timing_rate_limit(&self.topic_timing, cooldown);
                info!(
                    topic_id = input.topic_id,
                    cooldown_ms = cooldown.as_millis() as u64,
                    "topic timings rate limited; deferring subsequent reports"
                );
                return Ok(false);
            }
            Err(error) => return Err(error),
        };
        let _ = self.read_response_text(trace_id, response).await?;
        info!(
            topic_id = input.topic_id,
            "topic timings reported successfully"
        );
        Ok(true)
    }
}

fn is_timing_rate_limited(runtime: &Arc<Mutex<FireTopicTimingRuntime>>) -> bool {
    let mut runtime = runtime.lock().expect("topic timing runtime lock poisoned");
    if let Some(cooldown_until) = runtime.cooldown_until {
        if cooldown_until > Instant::now() {
            return true;
        }
        runtime.cooldown_until = None;
    }
    false
}

fn apply_timing_rate_limit(runtime: &Arc<Mutex<FireTopicTimingRuntime>>, cooldown: Duration) {
    let mut runtime = runtime.lock().expect("topic timing runtime lock poisoned");
    runtime.cooldown_until = Some(Instant::now() + cooldown);
}
