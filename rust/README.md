# Rust Workspace

This directory contains the shared Rust core for the native clients.

Current crates:

- `fire-models`: shared serializable models for session/bootstrap state.
- `fire-core`: Discourse client state, shared session logic, and future API entrypoint.
- `fire-uniffi`: UniFFI bindings exposed to Swift and Kotlin.

Local third-party dependencies are wired in from:

- `third_party/openwire`
- `third_party/xlog-rs`

Those repositories live inside this repository tree and are tracked as Git submodules.
