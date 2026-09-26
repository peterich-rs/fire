use std::sync::{Arc, Mutex};

use bytes::Bytes;
use fire_models::{BrowserHttpRequest, BrowserHttpResponse};
use http::{HeaderName, HeaderValue, Request, Response, StatusCode};
use http_body_util::BodyExt;
use openwire::{RequestBody, ResponseBody};

use super::super::FireCore;
use super::traced::TracedRequest;
use crate::error::FireCoreError;

pub(crate) type FireBrowserHttpHandlerFn =
    Arc<dyn Fn(BrowserHttpRequest) -> Result<BrowserHttpResponse, String> + Send + Sync>;

#[derive(Clone, Default)]
pub(crate) struct FireBrowserHttpHandlerRegistry {
    inner: Arc<Mutex<Option<FireBrowserHttpHandlerFn>>>,
}

impl FireBrowserHttpHandlerRegistry {
    pub(crate) fn set(&self, handler: FireBrowserHttpHandlerFn) {
        *self
            .inner
            .lock()
            .expect("browser http handler mutex poisoned") = Some(handler);
    }

    pub(crate) fn clear(&self) {
        *self
            .inner
            .lock()
            .expect("browser http handler mutex poisoned") = None;
    }

    pub(crate) fn get(&self) -> Option<FireBrowserHttpHandlerFn> {
        self.inner
            .lock()
            .expect("browser http handler mutex poisoned")
            .clone()
    }
}

impl FireCore {
    pub fn set_browser_http_handler<F>(&self, handler: F)
    where
        F: Fn(BrowserHttpRequest) -> Result<BrowserHttpResponse, String> + Send + Sync + 'static,
    {
        self.browser_http_handler.set(Arc::new(handler));
    }

    pub fn clear_browser_http_handler(&self) {
        self.browser_http_handler.clear();
    }

    pub(crate) async fn execute_via_browser(
        &self,
        traced: TracedRequest,
    ) -> Result<(u64, Response<ResponseBody>), FireCoreError> {
        let handler =
            self.browser_http_handler
                .get()
                .ok_or_else(|| FireCoreError::InvalidArgument {
                    operation: traced.operation,
                    details: "browser http handler is not registered".to_string(),
                })?;
        let mut request = browser_request_from_traced(&traced);
        if request.body.is_none() {
            request.body = collect_request_body(traced.request.body()).await;
        }
        let response = handler(request).map_err(|details| FireCoreError::InvalidArgument {
            operation: traced.operation,
            details,
        })?;
        Ok((traced.trace_id, http_response_from_browser(response)?))
    }
}

fn browser_request_from_traced(traced: &TracedRequest) -> BrowserHttpRequest {
    let headers = traced
        .request
        .headers()
        .iter()
        .filter_map(|(name, value)| {
            value
                .to_str()
                .ok()
                .map(|value| (name.to_string(), value.to_string()))
        })
        .collect();
    BrowserHttpRequest {
        method: traced.request.method().as_str().to_string(),
        url: traced.request.uri().to_string(),
        headers,
        body: request_body_bytes(&traced.request),
        timeout_ms: 30_000,
    }
}

fn request_body_bytes(request: &Request<RequestBody>) -> Option<Vec<u8>> {
    let _ = request;
    None
}

async fn collect_request_body(body: &RequestBody) -> Option<Vec<u8>> {
    if body.is_absent() {
        return None;
    }
    let cloned = body.try_clone()?;
    let collected = cloned.collect().await.ok()?;
    let bytes = collected.to_bytes();
    if bytes.is_empty() {
        None
    } else {
        Some(bytes.to_vec())
    }
}

fn http_response_from_browser(
    response: BrowserHttpResponse,
) -> Result<Response<ResponseBody>, FireCoreError> {
    let status = StatusCode::from_u16(response.status).unwrap_or(StatusCode::BAD_GATEWAY);
    let mut builder = Response::builder().status(status);
    for (name, value) in response.headers {
        if let (Ok(name), Ok(value)) = (
            HeaderName::from_bytes(name.as_bytes()),
            HeaderValue::from_str(&value),
        ) {
            builder = builder.header(name, value);
        }
    }
    builder
        .body(ResponseBody::from_bytes(Bytes::from(response.body)))
        .map_err(FireCoreError::RequestBuild)
}
