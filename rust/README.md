# Rust Workspace

This directory contains the shared Rust core for the native clients.

Current crates:

- `fire-models`: shared serializable models for session/bootstrap state.
- `fire-core`: Discourse client state, shared session logic, and future API entrypoint.
  - keeps config, logging, HTML/bootstrap parsing, cookie transport, topic payload mapping, and session persistence in focused internal modules
- `fire-uniffi`: UniFFI boundary exposed to Swift and Kotlin.
  - exports local session/persistence APIs plus async topic/bootstrap/logout APIs
  - keeps its generator settings in `crates/fire-uniffi/uniffi.toml`
  - is the only crate that should carry UniFFI-specific binding configuration

Local third-party dependencies are wired in from:

- `third_party/openwire`
- `third_party/xlog-rs`

Those repositories live inside this repository tree and are tracked as Git submodules.
