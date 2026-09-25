use std::collections::HashSet;
use std::sync::{Arc, Mutex, RwLock};

use fire_models::{
    CanonicalCookie, CanonicalCookieStore, CookieSameSite, CookieSnapshot, CookieSource,
    CookieTrust,
};
use http::header::HeaderValue;
use openwire::CookieJar;
use time::{format_description::well_known::Rfc2822, OffsetDateTime};
use tracing::warn;
use url::Url;

use crate::core::{
    mutate_runtime_session_tracking_auth_change, FireAuthChangeSource, FireSessionRuntimeState,
};
use crate::sync_utils::{read_rwlock, write_rwlock};

include!("ingress.rs");
include!("request.rs");
include!("matching.rs");
include!("parse.rs");
include!("tests.rs");
