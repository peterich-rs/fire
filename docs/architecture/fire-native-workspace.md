# Fire Native Workspace

This repository is now the root of the Fire native rebuild.

## Roles

- `references/fluxdo/`
  - keeps the legacy Flutter implementation as a read-only behavior reference
  - remains useful for runtime comparison, but no longer defines the new project structure
- `docs/backend-api*.md`
  - hold the backend protocol notes required for the native rebuild
- `third_party/`
  - stores reusable Rust infrastructure repositories
- `rust/`
  - contains the shared Rust core and the UniFFI boundary
- `native/`
  - contains the future iOS and Android native host apps

## Local Layout

```text
fire/
  docs/
    backend-api.md
    backend-api/
    architecture/
      fire-native-workspace.md
  native/
    ios-app/
    android-app/
  references/
    fluxdo/
  rust/
    crates/
      fire-models/
      fire-core/
      fire-uniffi/
  third_party/
    openwire/
    xlog-rs/
```

## Shared Core Boundaries

- Platform-owned:
  - WebView login
  - Cloudflare challenge completion
  - cookie extraction from platform stores
  - native UI, files, media, notifications, keychain/keystore
- Rust-owned:
  - session state
  - bootstrap parsing results
  - API orchestration
  - MessageBus
  - shared models
  - logging integration

## Dependency Strategy

- `openwire` is the shared Rust network layer.
- `mars-xlog` is the shared logging backend.
- `references/fluxdo` is a reference submodule, not a build dependency.
- `third_party/` stores build dependencies as submodules so the superproject can be pushed cleanly to GitHub.
- The root Cargo workspace owns only the local Fire crates.

## Next Build Steps

1. Flesh out `fire-core` around the documented bootstrap/session pipeline.
2. Expose stable Rust APIs through `fire-uniffi`.
3. Create the Swift and Kotlin host apps under `native/`.
4. Port WebView login and cookie sync first, then move topic browsing and posting flows.
