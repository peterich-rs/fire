use serde::{Deserialize, Serialize};
use url::Url;

pub const DEFAULT_DOH_ENDPOINT_URL: &str = "https://dns.alidns.com/dns-query";

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DohSettings {
    pub enabled: bool,
    pub endpoint_url: String,
}

impl Default for DohSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            endpoint_url: DEFAULT_DOH_ENDPOINT_URL.to_string(),
        }
    }
}

impl DohSettings {
    pub fn normalize(self) -> Result<Self, DohSettingsError> {
        Ok(Self {
            enabled: self.enabled,
            endpoint_url: normalize_doh_endpoint_url(&self.endpoint_url)?,
        })
    }

    pub fn matching_preset(&self) -> Option<&'static DohPreset> {
        DohPreset::all()
            .iter()
            .find(|preset| preset.endpoint_url == self.endpoint_url)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DohPreset {
    pub id: &'static str,
    pub display_name: &'static str,
    pub endpoint_url: &'static str,
    pub bootstrap_ips: &'static [&'static str],
}

impl DohPreset {
    pub const fn all() -> &'static [DohPreset] {
        &DOH_PRESETS
    }

    pub fn by_id(id: &str) -> Option<&'static DohPreset> {
        Self::all().iter().find(|preset| preset.id == id)
    }

    pub fn by_endpoint_url(url: &str) -> Option<&'static DohPreset> {
        Self::all().iter().find(|preset| preset.endpoint_url == url)
    }

    pub fn by_host(host: &str) -> Option<&'static DohPreset> {
        let host = host.trim().trim_end_matches('.').to_ascii_lowercase();
        Self::all().iter().find(|preset| {
            Url::parse(preset.endpoint_url)
                .ok()
                .and_then(|url| url.host_str().map(str::to_ascii_lowercase))
                .is_some_and(|preset_host| preset_host == host)
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DohProbeResult {
    pub ok: bool,
    pub host: String,
    pub resolved_addresses: Vec<String>,
    pub elapsed_ms: u64,
    pub error_message: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DohSettingsError {
    EmptyUrl,
    InvalidUrl(String),
    UnsupportedScheme(String),
    MissingHost,
}

impl std::fmt::Display for DohSettingsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::EmptyUrl => f.write_str("DoH URL is empty"),
            Self::InvalidUrl(value) => write!(f, "invalid DoH URL: {value}"),
            Self::UnsupportedScheme(scheme) => {
                write!(f, "DoH URL must use https, got {scheme}")
            }
            Self::MissingHost => f.write_str("DoH URL is missing a host"),
        }
    }
}

impl std::error::Error for DohSettingsError {}

pub fn normalize_doh_endpoint_url(raw: &str) -> Result<String, DohSettingsError> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(DohSettingsError::EmptyUrl);
    }
    let mut url = Url::parse(trimmed)
        .map_err(|error| DohSettingsError::InvalidUrl(format!("{trimmed}: {error}")))?;
    if url.scheme() != "https" {
        return Err(DohSettingsError::UnsupportedScheme(
            url.scheme().to_string(),
        ));
    }
    if url.host_str().is_none() {
        return Err(DohSettingsError::MissingHost);
    }
    if url.username() != "" || url.password().is_some() {
        return Err(DohSettingsError::InvalidUrl(
            "DoH URL must not include credentials".to_string(),
        ));
    }
    url.set_fragment(None);
    if url.path().is_empty() || url.path() == "/" {
        url.set_path("/dns-query");
    }
    Ok(url.to_string())
}

const DOH_PRESETS: [DohPreset; 7] = [
    DohPreset {
        id: "alidns",
        display_name: "阿里 DNS",
        endpoint_url: DEFAULT_DOH_ENDPOINT_URL,
        bootstrap_ips: &["223.5.5.5", "223.6.6.6"],
    },
    DohPreset {
        id: "dnspod",
        display_name: "DNSPod",
        endpoint_url: "https://doh.pub/dns-query",
        bootstrap_ips: &["1.12.12.12", "120.53.53.53"],
    },
    DohPreset {
        id: "tencent",
        display_name: "腾讯 DNS",
        endpoint_url: "https://dns.pub/dns-query",
        bootstrap_ips: &["1.12.12.12"],
    },
    DohPreset {
        id: "cloudflare",
        display_name: "Cloudflare",
        endpoint_url: "https://cloudflare-dns.com/dns-query",
        bootstrap_ips: &["1.1.1.1", "1.0.0.1"],
    },
    DohPreset {
        id: "google",
        display_name: "Google",
        endpoint_url: "https://dns.google/dns-query",
        bootstrap_ips: &["8.8.8.8", "8.8.4.4"],
    },
    DohPreset {
        id: "quad9",
        display_name: "Quad9",
        endpoint_url: "https://dns.quad9.net/dns-query",
        bootstrap_ips: &["9.9.9.9", "149.112.112.112"],
    },
    DohPreset {
        id: "cira",
        display_name: "Canadian Shield",
        endpoint_url: "https://private.canadianshield.cira.ca/dns-query",
        bootstrap_ips: &[],
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_settings_are_disabled_with_alidns() {
        let settings = DohSettings::default();
        assert!(!settings.enabled);
        assert_eq!(settings.endpoint_url, DEFAULT_DOH_ENDPOINT_URL);
        assert_eq!(
            settings.matching_preset().map(|preset| preset.id),
            Some("alidns")
        );
    }

    #[test]
    fn normalize_fills_default_path() {
        assert_eq!(
            normalize_doh_endpoint_url("https://dns.alidns.com").unwrap(),
            "https://dns.alidns.com/dns-query"
        );
        assert_eq!(
            normalize_doh_endpoint_url("https://dns.google/dns-query").unwrap(),
            "https://dns.google/dns-query"
        );
    }

    #[test]
    fn normalize_rejects_http_and_empty() {
        assert!(matches!(
            normalize_doh_endpoint_url("http://dns.alidns.com/dns-query"),
            Err(DohSettingsError::UnsupportedScheme(_))
        ));
        assert_eq!(
            normalize_doh_endpoint_url("   ").unwrap_err(),
            DohSettingsError::EmptyUrl
        );
    }

    #[test]
    fn normalize_rejects_credentials() {
        assert!(matches!(
            normalize_doh_endpoint_url("https://user:pass@dns.alidns.com/dns-query"),
            Err(DohSettingsError::InvalidUrl(_))
        ));
    }

    #[test]
    fn presets_have_unique_ids() {
        let mut ids: Vec<_> = DohPreset::all().iter().map(|preset| preset.id).collect();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), DohPreset::all().len());
    }
}
