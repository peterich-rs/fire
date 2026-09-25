use std::sync::Arc;

use http::header::{HeaderName, ACCEPT_LANGUAGE, COOKIE, ORIGIN, REFERER, USER_AGENT};
use http::{Request, Response};
use openwire::{RequestBody, ResponseBody};
use url::Url;

use super::{FireChallengePresentation, FireRequestEpoch, FireRequestProfile};
use crate::diagnostics::FireDiagnosticsStore;

pub(crate) struct TracedRequest {
    pub(crate) trace_id: u64,
    pub(crate) operation: &'static str,
    pub(crate) request: Request<RequestBody>,
}

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct FireSkipCsrfHeader;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct FireSkipCloudflareBlock;

#[derive(Clone, Copy, Debug, Default)]
pub(crate) struct FireSkipCookieSelfHeal;

impl TracedRequest {
    pub(crate) fn with_challenge_presentation(
        mut self,
        presentation: FireChallengePresentation,
    ) -> Self {
        self.request.extensions_mut().insert(presentation);
        self
    }

    pub(crate) fn without_csrf_header(mut self) -> Self {
        self.request.extensions_mut().insert(FireSkipCsrfHeader);
        self
    }
}

pub(super) fn clone_request_for_retry(
    request: &Request<RequestBody>,
) -> Option<Request<RequestBody>> {
    let cloned_body = request.body().try_clone()?;
    let request_profile = request.extensions().get::<FireRequestProfile>().copied();
    let request_epoch = request.extensions().get::<FireRequestEpoch>().copied();
    let skip_csrf_header = request.extensions().get::<FireSkipCsrfHeader>().copied();
    let skip_cloudflare_block = request
        .extensions()
        .get::<FireSkipCloudflareBlock>()
        .copied();
    let skip_cookie_self_heal = request
        .extensions()
        .get::<FireSkipCookieSelfHeal>()
        .copied();
    let challenge_presentation = request
        .extensions()
        .get::<FireChallengePresentation>()
        .copied();
    let mut builder = Request::builder()
        .method(request.method().clone())
        .uri(request.uri().clone())
        .version(request.version());
    for (name, value) in request.headers() {
        if should_rebuild_header_for_retry(name) {
            continue;
        }
        builder = builder.header(name, value);
    }
    let mut request = builder.body(cloned_body).ok()?;
    if let Some(profile) = request_profile {
        request.extensions_mut().insert(profile);
    }
    if let Some(epoch) = request_epoch {
        request.extensions_mut().insert(epoch);
    }
    if let Some(skip) = skip_csrf_header {
        request.extensions_mut().insert(skip);
    }
    if let Some(skip) = skip_cloudflare_block {
        request.extensions_mut().insert(skip);
    }
    if let Some(skip) = skip_cookie_self_heal {
        request.extensions_mut().insert(skip);
    }
    if let Some(presentation) = challenge_presentation {
        request.extensions_mut().insert(presentation);
    }
    Some(request)
}

fn should_rebuild_header_for_retry(name: &HeaderName) -> bool {
    name == COOKIE
        || name == USER_AGENT
        || name == ACCEPT_LANGUAGE
        || name == ORIGIN
        || name == REFERER
        || name.as_str().eq_ignore_ascii_case("x-csrf-token")
        || name.as_str().eq_ignore_ascii_case("x-requested-with")
        || name.as_str().eq_ignore_ascii_case("sec-fetch-dest")
        || name.as_str().eq_ignore_ascii_case("sec-fetch-mode")
        || name.as_str().eq_ignore_ascii_case("sec-fetch-site")
        || name.as_str().eq_ignore_ascii_case("priority")
        || name.as_str().eq_ignore_ascii_case("discourse-logged-in")
        || name.as_str().eq_ignore_ascii_case("discourse-present")
}

pub(super) fn trace_request(
    diagnostics: &Arc<FireDiagnosticsStore>,
    operation: &'static str,
    mut request: Request<RequestBody>,
) -> TracedRequest {
    let trace_id = diagnostics.prepare_request_trace(operation, &mut request);
    TracedRequest {
        trace_id,
        operation,
        request,
    }
}

pub(super) fn response_from_parts<B>(
    parts: http::response::Parts,
    body: B,
) -> Response<ResponseBody>
where
    ResponseBody: From<B>,
{
    Response::from_parts(parts, body.into())
}

pub(super) fn request_url_string(request: &Request<RequestBody>) -> String {
    request.uri().to_string()
}

pub(super) fn request_origin_url(base_url: &Url, request: &Request<RequestBody>) -> Option<String> {
    let request_url = base_url.join(request.uri().path()).ok()?;
    let path = request_url.path();
    let trims_json_route = path.ends_with(".json")
        && (path.starts_with("/c/") || path.starts_with("/tags/") || path.starts_with("/t/"));

    let canonical_path = if path == "/latest.json" {
        Some("/latest".to_string())
    } else if trims_json_route {
        Some(path.trim_end_matches(".json").to_string())
    } else {
        None
    }?;

    let mut url = base_url.clone();
    url.set_path(&canonical_path);
    url.set_query(None);
    url.set_fragment(None);
    Some(url.to_string())
}
