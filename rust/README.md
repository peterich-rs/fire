# Rust Workspace

This directory contains the shared Rust core for the native clients.

The workspace MSRV is Rust `1.88`, pinned in the repository with [`rust-toolchain.toml`](../rust-toolchain.toml) as `1.88.0`.

Current crates:

- `fire-models`: shared serializable models for session/bootstrap state.
- `fire-core`: Discourse client state, shared session logic, and future API entrypoint.
  - keeps config, logging, readable-log export, network request tracing, HTML/bootstrap parsing, cookie transport, topic payload mapping, and session persistence in focused internal modules
- `fire-uniffi`: UniFFI boundary exposed to Swift and Kotlin.
  - exports local session/persistence APIs, diagnostics APIs, plus async topic/bootstrap/logout APIs
  - wraps exported calls in a panic boundary so Rust panics are logged, mapped to `FireUniFfiError::Internal`, and poison the current handle for follow-up calls
  - keeps its generator settings in `crates/fire-uniffi/uniffi.toml`
  - is the only crate that should carry UniFFI-specific binding configuration

CI now validates this workspace in three layers:

- host Rust build/test on macOS, Windows, and Ubuntu
- Android cross-target Rust builds for the UniFFI shared library targets
- iOS cross-target Rust builds for the UniFFI static library targets

Local third-party dependencies are wired in from:

- `third_party/openwire`
- `third_party/xlog-rs`

Those repositories live inside this repository tree and are tracked as Git submodules.
