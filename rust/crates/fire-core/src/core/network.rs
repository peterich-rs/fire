use http::{header::HeaderMap, Method, Request, Response};
use openwire::{RequestBody, ResponseBody};
use url::Url;

use super::FireCore;
use crate::error::FireCoreError;

impl FireCore {
    pub(crate) fn build_home_request(&self) -> Result<Request<RequestBody>, FireCoreError> {
        let uri = self.base_url.join("/")?;
        Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header("Accept", "text/html")
            .header("User-Agent", "Fire/0.1")
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)
    }

    pub(crate) fn build_json_get_request(
        &self,
        path: &str,
        query_params: Vec<(&str, String)>,
        extra_headers: &[(&str, String)],
    ) -> Result<Request<RequestBody>, FireCoreError> {
        let mut uri = self.base_url.join(path)?;
        if !query_params.is_empty() {
            let mut serializer = uri.query_pairs_mut();
            for (key, value) in query_params {
                serializer.append_pair(key, &value);
            }
        }

        let origin = request_origin(&self.base_url);
        let referer = request_referer(&self.base_url);
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(Method::GET)
            .uri(uri.as_str())
            .header(
                "Accept",
                "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("X-Requested-With", "XMLHttpRequest")
            .header("User-Agent", "Fire/0.1")
            .header("Origin", origin)
            .header("Referer", referer);

        if snapshot.cookies.has_login_session() {
            builder = builder
                .header("Discourse-Logged-In", "true")
                .header("Discourse-Present", "true");
        }

        for (name, value) in extra_headers {
            builder = builder.header(*name, value);
        }

        builder
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)
    }

    pub(crate) fn build_api_request(
        &self,
        method: Method,
        path: &str,
        requires_csrf: bool,
    ) -> Result<Request<RequestBody>, FireCoreError> {
        let uri = self.base_url.join(path)?;
        let origin = request_origin(&self.base_url);
        let referer = request_referer(&self.base_url);
        let snapshot = self.snapshot();

        let mut builder = Request::builder()
            .method(method)
            .uri(uri.as_str())
            .header(
                "Accept",
                "application/json;q=0.9, text/plain;q=0.8, */*;q=0.5",
            )
            .header("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
            .header("X-Requested-With", "XMLHttpRequest")
            .header("User-Agent", "Fire/0.1")
            .header("Origin", origin)
            .header("Referer", referer);

        if snapshot.cookies.has_login_session() {
            builder = builder
                .header("Discourse-Logged-In", "true")
                .header("Discourse-Present", "true");
        }

        if requires_csrf {
            let csrf_token = snapshot
                .cookies
                .csrf_token
                .ok_or(FireCoreError::MissingCsrfToken)?;
            builder = builder.header("X-CSRF-Token", csrf_token);
        }

        builder
            .body(RequestBody::empty())
            .map_err(FireCoreError::RequestBuild)
    }
}

pub(crate) async fn expect_success(
    operation: &'static str,
    response: Response<ResponseBody>,
) -> Result<Response<ResponseBody>, FireCoreError> {
    if response.status().is_success() {
        return Ok(response);
    }

    let status = response.status().as_u16();
    let body = response
        .into_body()
        .text()
        .await
        .unwrap_or_else(|error| format!("<failed to read error body: {error}>"));
    Err(FireCoreError::HttpStatus {
        operation,
        status,
        body,
    })
}

pub(crate) fn header_value(headers: &HeaderMap, name: &str) -> Option<String> {
    headers
        .get(name)
        .and_then(|value| value.to_str().ok())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

pub(crate) fn is_bad_csrf_body(body: &str) -> bool {
    body == r#"["BAD CSRF"]"#
}

fn request_origin(base_url: &Url) -> String {
    let mut origin = base_url.clone();
    origin.set_path("");
    origin.set_query(None);
    origin.set_fragment(None);
    let value = origin.as_str().trim_end_matches('/');
    value.to_string()
}

fn request_referer(base_url: &Url) -> String {
    let mut referer = base_url.clone();
    referer.set_path("/");
    referer.set_query(None);
    referer.set_fragment(None);
    referer.to_string()
}
