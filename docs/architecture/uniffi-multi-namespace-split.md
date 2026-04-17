# Split fire-uniffi into Multi-Namespace Crates

## Breaking Change Notice

This change breaks the public Rust / UniFFI API surface exposed to iOS and Android. Downstream consumers (`native/ios-app`, `native/android-app`, their tests) must migrate.

Required migration steps for native call sites:

1. Replace `FireCoreHandle` constructor calls with `FireAppCore.new(baseUrl, workspacePath)`. The argument list and defaults are preserved verbatim from today's `FireCoreHandle::new(base_url: Option<String>, workspace_path: Option<String>)` (see `rust/crates/fire-uniffi/src/handle.rs:72-85`). Only the type name changes.
2. Replace direct method calls on the handle with a one-level domain prefix obtained from the facade:
   - `handle.fetchTopicDetail(...)` -> `handle.topics().fetchTopicDetail(...)`
   - `handle.snapshot()` -> `handle.session().snapshot()`
   - `handle.listLogFiles()` -> `handle.diagnostics().listLogFiles()`
   - etc. (mapping table lives in the implementation plan)
3. Top-level `#[uniffi::export]` free functions (`plain_text_from_html`, `preview_text_from_html`, `monogram_for_username`) remain in the root `fire_uniffi` namespace. No migration required for call sites such as `native/android-app/src/main/java/com/fire/app/TopicDetailActivity.kt:19,280-282`.
4. Update imports: types that move to `fire-uniffi-types` gain a new generated module name (`uniffi.fire_uniffi_types` on Kotlin, `fire_uniffi_types` on Swift). Many types keep their identifier; only the import source changes.
5. Delete the committed legacy file at `<repo_root>/uniffi/fire_uniffi/fire_uniffi.kt`; the active binding now lives under `native/android-app/build/generated/source/uniffi/<buildType>/...`.

## Feasibility Assessment

All impacted surface is inside this repo. `FireCoreHandle` is defined in a single module (`rust/crates/fire-uniffi/src/handle.rs`) with 60+ `#[uniffi::export]` methods that delegate to `Arc<FireCore>`; every method can be moved to a domain sub-handle without touching `fire-core`. The same module also exposes three top-level `#[uniffi::export]` free functions (`plain_text_from_html`, `preview_text_from_html`, `monogram_for_username`) which stay in the facade crate unchanged. UniFFI 0.28+ supports multiple `setup_scaffolding!` namespaces in a single cdylib and the `--library` bindgen mode emits one generated file per namespace; no fork or bespoke bindgen is required. Existing sync scripts for iOS (`native/ios-app/scripts/sync_uniffi_bindings.sh`) and Android (`native/android-app/scripts/sync_uniffi_bindings.sh`) already invoke `--library` mode against a single cdylib. Sourceset wiring on Android (`native/android-app/build.gradle.kts` lines 92-101) and the Xcode preBuild phase on iOS (`native/ios-app/project.yml` lines 94-112) continue to work unchanged in shape. Native call sites total 14 files and are pure mechanical rename. **Fully feasible.**

## Current Surface Inventory

Rust crates:

- `rust/crates/fire-uniffi/Cargo.toml` -- single crate with `crate-type = ["cdylib", "staticlib", "rlib"]`, `uniffi` with `cli` feature.
- `rust/crates/fire-uniffi/src/lib.rs` -- single `uniffi::setup_scaffolding!("fire_uniffi")`, re-exports every `state_*` module.
- `rust/crates/fire-uniffi/src/handle.rs` (~940 lines) -- single `FireCoreHandle` struct with 60+ `#[uniffi::export]` methods.
- `rust/crates/fire-uniffi/src/error.rs` -- `FireUniFfiError` enum used across all domains.
- `rust/crates/fire-uniffi/src/panic.rs` -- `PanicState` + `run_on_ffi_runtime` + `run_infallible` shared helpers.
- `rust/crates/fire-uniffi/src/state_diagnostics.rs` -- `LogFileSummaryState`, log / trace state records.
- `rust/crates/fire-uniffi/src/state_messagebus.rs` -- messagebus and topic-reply-presence state.
- `rust/crates/fire-uniffi/src/state_notification.rs` -- `NotificationCenterState` and notification records.
- `rust/crates/fire-uniffi/src/state_search.rs` -- search result records.
- `rust/crates/fire-uniffi/src/state_session.rs` -- `SessionState`, `CookieState`, bootstrap records.
- `rust/crates/fire-uniffi/src/state_topic_detail.rs` -- `TopicDetailState`, `TopicPostState`, `VoteResponseState`, etc.
- `rust/crates/fire-uniffi/src/state_topic_list.rs` -- `TopicListKindState`, `TopicRowState`, `TopicParticipantState`.
- `rust/crates/fire-uniffi/src/state_user.rs` -- `UserSummaryState` and related (exports currently unused; reserved for profile work).
- `rust/crates/fire-uniffi/src/bin/uniffi-bindgen.rs` -- bindgen entry point.
- `rust/crates/fire-uniffi/uniffi.toml` -- Kotlin package name `uniffi.fire_uniffi`, Swift module names.

Android build integration:

- `native/android-app/build.gradle.kts` lines 10-59, 92-101 -- registers `syncFireUniffiDebugBindings` / `syncFireUniffiReleaseBindings` tasks and wires `build/generated/uniffi/{debug,release}/kotlin` into sourceSets.
- `native/android-app/scripts/sync_uniffi_bindings.sh` -- runs bindgen in `--library` mode, copies generated `.kt` into Gradle output dir.
- `native/android-app/README.md` -- documents binding generation.

iOS build integration:

- `native/ios-app/project.yml` lines 94-112 -- preBuildScript declares single `Generated/fire_uniffi.swift` as output; `sources:` explicitly lists the same file.
- `native/ios-app/scripts/sync_uniffi_bindings.sh` -- runs bindgen, copies `fire_uniffi.swift`, `fire_uniffiFFI.h`, `fire_uniffiFFI.modulemap`; applies Python patch to guard `print(...)` with `#if DEBUG`.
- `native/ios-app/Generated/.gitignore` -- ignores all generated artifacts.

Native call sites:

- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- constructs and calls `FireCoreHandle`.
- `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt` -- constructs and calls `FireCoreHandle`.
- `native/android-app/src/main/java/com/fire/app/MainActivity.kt`
- `native/android-app/src/main/java/com/fire/app/TopicDetailActivity.kt`
- `native/android-app/src/main/java/com/fire/app/DiagnosticsActivity.kt`
- `native/android-app/src/main/java/com/fire/app/LogViewerActivity.kt`
- `native/android-app/src/main/java/com/fire/app/RequestTraceDetailActivity.kt`
- `native/android-app/src/main/java/com/fire/app/TopicPresentation.kt`
- `native/android-app/src/main/java/com/fire/app/DiagnosticsPresentation.kt`
- `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt`
- `native/android-app/src/test/java/com/fire/app/TopicPresentationTest.kt`

Legacy artifacts to remove:

- `uniffi/fire_uniffi/fire_uniffi.kt` -- tracked in git since commit `0fc52b5`; not written by any current build path.
- `uniffi/` directory at repo root.

## Design

### Key Design Decisions

1. **Split `fire-uniffi` into multiple `setup_scaffolding!` namespaces, one per business domain.** Rejected: post-processing AST splitter over a single generated file. Post-processing is fragile across UniFFI versions and is not upstream-supported; multi-namespace is UniFFI's recommended mechanism for splitting bindings. Each domain crate produces exactly one `.kt` / `.swift` file.

2. **Keep a single entry-point object via a facade crate (`fire-uniffi`) that composes sub-handles.** Rejected: require native code to construct each domain handle independently. The facade keeps bootstrap semantics ("construct once, share state") centralized in Rust and collapses native migration to a mechanical one-level prefix rename.

3. **Introduce a shared `fire-uniffi-types` crate** for records, enums, and errors referenced by 2+ domains. Rejected: duplicate shared types inside each domain crate. Duplication generates distinct Swift / Kotlin types per namespace (`TopicsTopicRowState` vs `SearchTopicRowState`) and pushes conversion onto native code. Shared types are referenced cross-crate via UniFFI external-type / `uniffi::remote` macros (exact macro name pinned in Phase 1 probe).

4. **Keep a single cdylib (`fire-uniffi`)**; domain crates are `rlib` only. Rejected: one cdylib per domain. Multiple cdylibs complicate JNA loading on Android, require a second modulemap on iOS, and bloat binary size. UniFFI `--library` mode discovers metadata for every namespace scaffolded into the one cdylib.

5. **Keep generated Android bindings in `build/generated/source/uniffi/<buildType>/` under the android module**, registered into sourceSets. Rejected: write into `src/main/kotlin/generated/`. AGP convention is that generated sources live under `build/generated/` and never in `src/main/` (to keep `src/` reserved for hand-written code and avoid git pollution). The previous confusion came from the legacy tracked directory at repo root, which is removed.

6. **Keep generated iOS Swift bindings in `Generated/FireUniFfi/` and let the xcodegen `sources:` stanza reference the directory**, not each file. This avoids editing `project.yml` every time a domain is added or removed.

### Target Crate Graph

```text
fire-models  fire-core
    \        /
     \      /
      v    v
 fire-uniffi-types                       (namespace: fire_uniffi_types)
      ^   ^   ^   ^   ^   ^   ^
      |   |   |   |   |   |   |
   +--+   |   |   |   |   |   +---------------+
   |      |   |   |   |   |                   |
fire-uniffi-session                           (namespace: fire_uniffi_session)
fire-uniffi-diagnostics                       (namespace: fire_uniffi_diagnostics)
fire-uniffi-messagebus                        (namespace: fire_uniffi_messagebus)
fire-uniffi-notifications                     (namespace: fire_uniffi_notifications)
fire-uniffi-topics                            (namespace: fire_uniffi_topics)
fire-uniffi-search                            (namespace: fire_uniffi_search)
fire-uniffi-user                              (namespace: fire_uniffi_user)
         \   \   \   \   \   \   \
          v   v   v   v   v   v   v
                fire-uniffi                   (namespace: fire_uniffi;
                                               cdylib + bindgen bin; FireAppCore facade)
```

### Facade Type

```rust
// rust/crates/fire-uniffi/src/lib.rs
uniffi::setup_scaffolding!("fire_uniffi");

use std::sync::Arc;

use fire_uniffi_diagnostics::FireDiagnosticsHandle;
use fire_uniffi_messagebus::FireMessageBusHandle;
use fire_uniffi_notifications::FireNotificationsHandle;
use fire_uniffi_search::FireSearchHandle;
use fire_uniffi_session::FireSessionHandle;
use fire_uniffi_topics::FireTopicsHandle;
use fire_uniffi_types::{FireUniFfiError, SharedFireCore};
use fire_uniffi_user::FireUserHandle;

#[derive(uniffi::Object)]
pub struct FireAppCore {
    session: Arc<FireSessionHandle>,
    diagnostics: Arc<FireDiagnosticsHandle>,
    messagebus: Arc<FireMessageBusHandle>,
    notifications: Arc<FireNotificationsHandle>,
    topics: Arc<FireTopicsHandle>,
    search: Arc<FireSearchHandle>,
    user: Arc<FireUserHandle>,
}

#[uniffi::export]
impl FireAppCore {
    #[uniffi::constructor]
    pub fn new(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Arc<Self>, FireUniFfiError> {
        let shared = Arc::new(SharedFireCore::bootstrap(base_url, workspace_path)?);
        Ok(Arc::new(Self {
            session: FireSessionHandle::from_shared(shared.clone()),
            diagnostics: FireDiagnosticsHandle::from_shared(shared.clone()),
            messagebus: FireMessageBusHandle::from_shared(shared.clone()),
            notifications: FireNotificationsHandle::from_shared(shared.clone()),
            topics: FireTopicsHandle::from_shared(shared.clone()),
            search: FireSearchHandle::from_shared(shared.clone()),
            user: FireUserHandle::from_shared(shared),
        }))
    }

    pub fn session(&self) -> Arc<FireSessionHandle> { self.session.clone() }
    pub fn diagnostics(&self) -> Arc<FireDiagnosticsHandle> { self.diagnostics.clone() }
    pub fn messagebus(&self) -> Arc<FireMessageBusHandle> { self.messagebus.clone() }
    pub fn notifications(&self) -> Arc<FireNotificationsHandle> { self.notifications.clone() }
    pub fn topics(&self) -> Arc<FireTopicsHandle> { self.topics.clone() }
    pub fn search(&self) -> Arc<FireSearchHandle> { self.search.clone() }
    pub fn user(&self) -> Arc<FireUserHandle> { self.user.clone() }
}
```

### Shared Infrastructure in `fire-uniffi-types`

```rust
// rust/crates/fire-uniffi-types/src/shared.rs
use std::sync::Arc;
use fire_core::FireCore;

pub struct SharedFireCore {
    pub core: Arc<FireCore>,
    pub panic_state: Arc<PanicState>,
    pub runtime: tokio::runtime::Handle,
}

impl SharedFireCore {
    pub fn bootstrap(
        base_url: Option<String>,
        workspace_path: Option<String>,
    ) -> Result<Self, FireUniFfiError> {
        // Same logic as today's FireCoreHandle::new (handle.rs:72-85):
        // hand base_url/workspace_path to fire_core::FireCoreConfig and construct FireCore.
    }
}
```

Each domain handle receives `Arc<SharedFireCore>` and calls `self.shared.core` plus `run_on_ffi_runtime` / `run_infallible` helpers, which are also re-homed to `fire-uniffi-types`.

### Domain Handle Skeleton

```rust
// rust/crates/fire-uniffi-topics/src/lib.rs
uniffi::setup_scaffolding!("fire_uniffi_topics");

use std::sync::Arc;
use fire_uniffi_types::{FireUniFfiError, SharedFireCore, TopicRowState, TopicPostState};

#[derive(uniffi::Object)]
pub struct FireTopicsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireTopicsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireTopicsHandle {
    pub async fn fetch_topic_list(/* ... */) -> Result<TopicListState, FireUniFfiError> { /* ... */ }
    pub async fn fetch_topic_detail(/* ... */) -> Result<TopicDetailState, FireUniFfiError> { /* ... */ }
    // ... moved verbatim from handle.rs
}
```

### Type Partitioning Rules

- **Types used by exactly one domain** stay in that domain crate (e.g., `LogFileSummaryState` in diagnostics; `SearchResultPageState` in search).
- **Types used by 2+ domains** move to `fire-uniffi-types`. Initial set: `FireUniFfiError`, `SessionState` (referenced by session handle constructor *and* cookie-apply returns consumed by multiple domains), `TopicRowState` (topics + search), `TopicPostState` (topics + messagebus events), `UserSummaryState` (user + notifications + search), `CategoryRefState`, `TagRefState`, `CookieState`, `BootstrapState`.
- **Infrastructure helpers** (`PanicState`, `run_on_ffi_runtime`, `run_infallible`) move to `fire-uniffi-types` and are `pub` for sibling crates but not `#[uniffi::export]`ed.
- When ambiguous, types go into `fire-uniffi-types`; moving a type out later is cheaper than creating two divergent copies.

### Top-Level `#[uniffi::export]` Free Functions

`rust/crates/fire-uniffi/src/handle.rs:48-61` exports three namespace-level `#[uniffi::export] pub fn`s that are not `FireCoreHandle` methods:

- `plain_text_from_html(raw_html: String) -> String`
- `preview_text_from_html(raw_html: Option<String>) -> Option<String>`
- `monogram_for_username(username: String) -> String`

These are stateless display helpers and have no affinity to any domain. They stay in the top-level `fire-uniffi` crate (namespace `fire_uniffi`) alongside `FireAppCore`. Existing Android call sites (e.g., `native/android-app/src/main/java/com/fire/app/TopicDetailActivity.kt:19,280-282` uses `plainTextFromHtml`) continue to reference `uniffi.fire_uniffi.plainTextFromHtml` / `FireUniFfi.plainTextFromHtml` with no rename. Any future stateless helper that is domain-specific (e.g., a topic-detail-only sanitizer) goes into its domain crate instead.

### Namespace to Generated File Mapping

| Namespace | Kotlin package | Kotlin filename | Swift filename |
|---|---|---|---|
| `fire_uniffi_types` | `uniffi.fire_uniffi_types` | `fire_uniffi_types.kt` | `fire_uniffi_types.swift` |
| `fire_uniffi_session` | `uniffi.fire_uniffi_session` | `fire_uniffi_session.kt` | `fire_uniffi_session.swift` |
| `fire_uniffi_diagnostics` | `uniffi.fire_uniffi_diagnostics` | `fire_uniffi_diagnostics.kt` | `fire_uniffi_diagnostics.swift` |
| `fire_uniffi_messagebus` | `uniffi.fire_uniffi_messagebus` | `fire_uniffi_messagebus.kt` | `fire_uniffi_messagebus.swift` |
| `fire_uniffi_notifications` | `uniffi.fire_uniffi_notifications` | `fire_uniffi_notifications.kt` | `fire_uniffi_notifications.swift` |
| `fire_uniffi_topics` | `uniffi.fire_uniffi_topics` | `fire_uniffi_topics.kt` | `fire_uniffi_topics.swift` |
| `fire_uniffi_search` | `uniffi.fire_uniffi_search` | `fire_uniffi_search.kt` | `fire_uniffi_search.swift` |
| `fire_uniffi_user` | `uniffi.fire_uniffi_user` | `fire_uniffi_user.kt` | `fire_uniffi_user.swift` |
| `fire_uniffi` | `uniffi.fire_uniffi` | `fire_uniffi.kt` | `fire_uniffi.swift` |

Each generated file loads the same cdylib (`libfire_uniffi.so` / `libfire_uniffi.a` / `libfire_uniffi.dylib`); there is no duplicate JNA `System.loadLibrary` or duplicate iOS module.

### Android Path Strategy

- Active path moves from `native/android-app/build/generated/uniffi/<buildType>/kotlin/` to `native/android-app/build/generated/source/uniffi/<buildType>/` to mirror AGP conventions (`build/generated/source/buildConfig`, `build/generated/source/viewBinding`, etc.).
- `sourceSets` registers the new path under `java.srcDir(...)`.
- The legacy `<repo_root>/uniffi/` directory and its tracked file are removed; a root `.gitignore` entry prevents accidental reintroduction.

### iOS Project Integration

- `project.yml` `sources:` entry changes from `Generated/fire_uniffi.swift` (single file) to `Generated/FireUniFfi` (directory group); xcodegen auto-includes any `.swift` file landed there by the sync script.
- preBuildScript `outputFiles:` explicitly enumerates all expected `.swift` files; this keeps Xcode's incremental-build dependency graph accurate.
- The existing Python post-processing step (guarding UniFFI `print` statements with `#if DEBUG`) iterates over every `.swift` under `Generated/FireUniFfi/`.

## Phased Implementation

Each phase leaves both iOS and Android builds green. Each phase is a separate PR.

### Phase 0: Legacy Cleanup

**File: `uniffi/fire_uniffi/fire_uniffi.kt`**
- Delete. This file was generated by an older build path and has not been written by any current script since commit `0fc52b5`.

**File: `uniffi/` (directory)**
- Delete.

**File: `.gitignore`** (repo root)
- Add:
  ```
  /uniffi/
  ```
  Rationale: prevents any future bindgen regression from accidentally writing back to a repo-root path.

**File: `docs/architecture/ios-topic-detail-loading-and-notification-routing.md`**
- Update line 553: replace `uniffi/fire_uniffi/fire_uniffi.kt` reference with a general description ("regenerate Android bindings"). The old path is gone; docs must not point at it.

Build verification: `./gradlew assembleDebug` in `native/android-app` continues to produce a working app using the existing `build/generated/uniffi/...` path (this phase does not yet touch Gradle paths).

### Phase 1: Introduce `fire-uniffi-types` and Probe Multi-Namespace

This phase validates the UniFFI multi-namespace pipeline before doing any domain splits. It ships the permanent `fire-uniffi-types` crate (second namespace) but does not yet split any handle methods. The existence of a second namespace is the probe.

**File: `Cargo.toml`** (workspace root)
- Add `rust/crates/fire-uniffi-types` to `members`.

**File: `rust/crates/fire-uniffi-types/Cargo.toml` (new)**
```toml
[package]
name = "fire-uniffi-types"
version = "0.1.0"
edition.workspace = true
license.workspace = true
rust-version.workspace = true
authors.workspace = true
publish = false

[lib]
crate-type = ["rlib"]

[dependencies]
fire-core = { path = "../fire-core" }
fire-models = { path = "../fire-models" }
thiserror.workspace = true
tokio.workspace = true
tracing.workspace = true
uniffi.workspace = true
```

**File: `rust/crates/fire-uniffi-types/src/lib.rs` (new)**
- `uniffi::setup_scaffolding!("fire_uniffi_types");`
- `pub mod error;` -- verbatim move of `rust/crates/fire-uniffi/src/error.rs`.
- `pub mod panic;` -- verbatim move of `rust/crates/fire-uniffi/src/panic.rs`.
- `pub mod shared;` -- new `SharedFireCore` struct + `bootstrap` (carved out of `FireCoreHandle::new`).
- `pub mod records;` -- holds `TopicRowState`, `TopicPostState`, `UserSummaryState`, `CategoryRefState`, `TagRefState`, `CookieState`, `SessionState`, `BootstrapState`. Move bodies from `state_*.rs` with `git mv` where possible.

**File: `rust/crates/fire-uniffi/src/lib.rs`**
- Replace direct re-exports of moved types with `pub use fire_uniffi_types::*;` for the duration of Phase 1 so downstream compiles unchanged.
- Keep `uniffi::setup_scaffolding!("fire_uniffi");` in place.

**File: `rust/crates/fire-uniffi/src/error.rs`, `panic.rs`, and relevant `state_*.rs`**
- Delete the moved items; leave each file if it still hosts non-moved content, or delete outright.

**iOS build-system scaffolding must ship in this same phase.** The moment bindgen emits a second `.swift` (the new `fire_uniffi_types.swift`), the single-file iOS pipeline breaks: `native/ios-app/scripts/sync_uniffi_bindings.sh:229-231` copies only `fire_uniffi.swift`, and `native/ios-app/project.yml:51-56,108-112` compiles only that one file. Without the changes below, Xcode links against a `fire_uniffi.swift` that references types defined in `fire_uniffi_types.swift` which never reach the compiler, and iOS fails to build. Address all of that here, not in Phase 4.

**File: `native/ios-app/Generated/FireUniFfi/` (new directory)**
- Create directory. All per-namespace `.swift` files land here; `Generated/fire_uniffiFFI/` and `Generated/lib/` keep their current roles.

**File: `native/ios-app/project.yml`**
- Lines 51-56: replace the explicit single-file source entry with a directory group:
  ```yaml
  - path: Generated/FireUniFfi
    optional: true
    type: group
    buildPhase: sources
  ```
  xcodegen now auto-includes every `.swift` file landed by the sync script; future namespaces do not require another `project.yml` edit.
- Lines 108-112: rewrite preBuildScript `outputFiles:` to enumerate each expected per-namespace Swift file (at this phase: `Generated/FireUniFfi/fire_uniffi.swift`, `Generated/FireUniFfi/fire_uniffi_types.swift`). Subsequent phases append entries as each domain namespace lands, which keeps Xcode's incremental-build graph accurate.

**File: `native/ios-app/scripts/sync_uniffi_bindings.sh`**
- Lines 229-231: replace the three explicit `cp` commands with:
  ```bash
  mkdir -p "$swift_out_dir/FireUniFfi"
  rm -f "$swift_out_dir/FireUniFfi"/*.swift
  cp "$tmp_dir/bindings"/*.swift "$swift_out_dir/FireUniFfi/"
  cp "$tmp_dir/bindings/fire_uniffiFFI.h" "$ffi_out_dir/fire_uniffiFFI.h"
  cp "$tmp_dir/bindings/fire_uniffiFFI.modulemap" "$ffi_out_dir/module.modulemap"
  rm -f "$swift_out_dir/fire_uniffi.swift"
  ```
  `.h` and `.modulemap` remain single files (UniFFI emits one pair per cdylib regardless of namespace count). The trailing `rm -f` wipes the pre-split `Generated/fire_uniffi.swift` artifact so Xcode does not link it alongside the directory-group files.
- Lines 233-252: update the Python post-processing step to iterate over `"$swift_out_dir/FireUniFfi"/*.swift` instead of patching a single file. Same replacement dictionary.

**File: `native/ios-app/Fire.xcodeproj/project.pbxproj`**
- Regenerate via xcodegen after updating `project.yml` (repo convention).

**File: `native/android-app/scripts/sync_uniffi_bindings.sh`**
- No change. The existing `cp -R "$tmp_dir"/. "$generated_kotlin_dir"/` already copies every generated `.kt`; `java.srcDir` on the output directory picks up any file in the tree.

**File: `rust/crates/fire-uniffi/uniffi.toml`**
- Add per-namespace override section for `fire_uniffi_types` (package name, Swift module name) if needed; UniFFI accepts multiple `[bindings.kotlin.<namespace>]` sections.

**iOS Swift import semantics:** UniFFI-generated Swift files share the app's default module (no separate Swift module per namespace). Types declared in `fire_uniffi_types.swift` are directly visible to code in `fire_uniffi.swift` and app sources without an `import fire_uniffi_types` statement. The only UniFFI-declared Swift module is `fire_uniffiFFI` (the C-level helper, from `rust/crates/fire-uniffi/uniffi.toml:6-9`), which is unchanged. References to "import fire_uniffi_diagnostics" in later phases should be read as "types are in scope via the same app target", not as a Swift module import.

Verification:
- `cargo build -p fire-uniffi` succeeds.
- Android bindgen produces two `.kt` files: `fire_uniffi.kt` (now smaller; contains `FireCoreHandle` methods and the three top-level free functions minus type definitions moved to types) and `fire_uniffi_types.kt`.
- iOS bindgen produces two `.swift` files under `Generated/FireUniFfi/`; `ls native/ios-app/Generated/FireUniFfi/*.swift` shows exactly `fire_uniffi.swift` and `fire_uniffi_types.swift`.
- `xcodebuild -scheme Fire` compiles both Swift files; linker resolves cross-file type references without `import fire_uniffi_types`.
- `./gradlew assembleDebug` and existing test suites pass without any Swift/Kotlin call-site edits. Native call-site code still calls `FireCoreHandle` as before; type identifiers and the three free functions are unchanged.

Addressing review feedback: if probe shows UniFFI external-type macro syntax differs from this plan's assumption, adjust and document in the types crate before Phase 2. All subsequent phases assume the probe's pattern.

### Phase 2: Extract `fire-uniffi-diagnostics` (First Domain)

Start with diagnostics because it has the fewest cross-domain dependencies (reads logs and traces, owns `LogFileSummaryState`, does not nest topic/user types) and is consumed by a bounded set of native sites (`DiagnosticsActivity`, `LogViewerActivity`, `RequestTraceDetailActivity`, `FireSessionStore.swift` / `.kt`). It validates the full pipeline: sub-handle construction, facade composition, generated file emission, native rename.

**File: `Cargo.toml`** (workspace root)
- Add `rust/crates/fire-uniffi-diagnostics` to `members`.

**File: `rust/crates/fire-uniffi-diagnostics/Cargo.toml` (new)**
- Mirrors `fire-uniffi-types/Cargo.toml`; depends on `fire-uniffi-types`, `fire-core`, `fire-models`, `uniffi`.

**File: `rust/crates/fire-uniffi-diagnostics/src/lib.rs` (new)**
```rust
uniffi::setup_scaffolding!("fire_uniffi_diagnostics");

use std::sync::Arc;
use fire_uniffi_types::{FireUniFfiError, SharedFireCore};

pub mod records;          // LogFileSummaryState, NetworkTraceSummaryState, ...

#[derive(uniffi::Object)]
pub struct FireDiagnosticsHandle {
    shared: Arc<SharedFireCore>,
}

impl FireDiagnosticsHandle {
    pub fn from_shared(shared: Arc<SharedFireCore>) -> Arc<Self> {
        Arc::new(Self { shared })
    }
}

#[uniffi::export]
impl FireDiagnosticsHandle {
    pub fn diagnostic_session_id(&self) -> Result<String, FireUniFfiError> { /* moved */ }
    pub fn export_support_bundle(/* ... */) -> Result<String, FireUniFfiError> { /* moved */ }
    pub fn flush_logs(&self, sync: bool) -> Result<(), FireUniFfiError> { /* moved */ }
    pub fn log_host(/* ... */) -> Result<(), FireUniFfiError> { /* moved */ }
    pub fn list_log_files(&self) -> Result<Vec<LogFileSummaryState>, FireUniFfiError> { /* moved */ }
    pub fn read_log_file(/* ... */) -> Result<String, FireUniFfiError> { /* moved */ }
    pub fn read_log_file_page(/* ... */) -> Result<LogFilePageState, FireUniFfiError> { /* moved */ }
    pub fn list_network_traces(/* ... */) -> Result<Vec<NetworkTraceSummaryState>, FireUniFfiError> { /* moved */ }
    pub fn network_trace_detail(/* ... */) -> Result<NetworkTraceDetailState, FireUniFfiError> { /* moved */ }
    pub fn network_trace_body_page(/* ... */) -> Result<NetworkTraceBodyPageState, FireUniFfiError> { /* moved */ }
}
```

**File: `rust/crates/fire-uniffi-diagnostics/src/records.rs` (new)**
- Move `LogFileSummaryState`, `LogFilePageState`, `NetworkTraceSummaryState`, `NetworkTraceDetailState`, `NetworkTraceBodyPageState` verbatim from `state_diagnostics.rs`.

**File: `rust/crates/fire-uniffi/Cargo.toml`**
- Add `fire-uniffi-diagnostics = { path = "../fire-uniffi-diagnostics" }` dependency.

**File: `rust/crates/fire-uniffi/src/lib.rs`**
- Import `FireDiagnosticsHandle`.
- Add `diagnostics: Arc<FireDiagnosticsHandle>` field + getter on `FireAppCore`.
- First incremental version of `FireAppCore` keeps the old `FireCoreHandle` side-by-side for one commit; a subsequent commit in this same phase deletes the diagnostics methods from `FireCoreHandle`. This keeps each commit compilable.

**File: `rust/crates/fire-uniffi/src/handle.rs`**
- Remove all 10 diagnostics methods and their helpers (now in the diagnostics crate).

**File: `rust/crates/fire-uniffi/src/state_diagnostics.rs`**
- Delete (content moved).

**File: `native/ios-app/Sources/FireAppSession/FireSessionStore.swift`**
- `handle.listLogFiles()` -> `handle.diagnostics().listLogFiles()`
- `handle.networkTraceDetail(...)` -> `handle.diagnostics().networkTraceDetail(...)`
- etc., for every diagnostics call.
- No new Swift `import` needed: all generated Swift files compile into the same app target (Phase 1 sets this up). Types defined in `fire_uniffi_diagnostics.swift` are directly visible by name to the rest of the target.

**File: `native/ios-app/project.yml`**
- Extend preBuildScript `outputFiles:` (set up in Phase 1) with `Generated/FireUniFfi/fire_uniffi_diagnostics.swift`. Regenerate `Fire.xcodeproj/project.pbxproj` via xcodegen.

**File: `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt`**
- Same rename.
- Imports: `import uniffi.fire_uniffi_diagnostics.FireDiagnosticsHandle` (only where the type itself is referenced); method calls do not require additional imports because they go through the facade.

**File: `native/android-app/src/main/java/com/fire/app/DiagnosticsActivity.kt`, `LogViewerActivity.kt`, `RequestTraceDetailActivity.kt`, `DiagnosticsPresentation.kt`**
- Replace every `handle.<diagnosticsMethod>(...)` with `handle.diagnostics().<diagnosticsMethod>(...)`.
- Update imports.

**File: `native/android-app/build.gradle.kts` (lines 92-101)**
- No change this phase. Path rename deferred to Phase 4.

Verification:
- `cargo test -p fire-uniffi-diagnostics` passes (tests for diagnostics helpers move with their owning module).
- `cargo test -p fire-uniffi` passes.
- `./gradlew assembleDebug` passes; `DiagnosticsActivity` launches and lists log files.
- `xcodebuild -scheme Fire` passes.

### Phase 3: Extract Remaining Domain Crates

Repeat Phase 2's structure for each of these, one phase (one PR) each, in this order (dependency-light first):

1. **`fire-uniffi-search`** -- small surface (3 methods, few types). Depends on `TopicRowState` + `UserSummaryState` from types.
2. **`fire-uniffi-notifications`** -- 11 methods (notifications + bookmarks + drafts + read-history). Depends on `UserSummaryState`, `TopicRowState` from types.
3. **`fire-uniffi-messagebus`** -- 7 methods (subscribe + topic-reply-presence). Depends on `TopicPostState` from types.
4. **`fire-uniffi-topics`** -- largest domain: 18 methods (topic list + detail + posts + reactions + votes + polls). Depends on `TopicRowState`, `TopicPostState`, `UserSummaryState` from types.
5. **`fire-uniffi-session`** -- 15 methods (session, cookies, CSRF, bootstrap). Depends on `SessionState`, `CookieState`, `BootstrapState` from types.
6. **`fire-uniffi-user`** -- empty shell, wired into facade; actual profile methods land with the profile feature (tracked separately in `docs/architecture/profile-page-redesign.md`).

Each sub-phase:
- Adds one crate with `setup_scaffolding!("fire_uniffi_<domain>")`.
- Moves the domain's handle methods from `handle.rs`; moves exclusive record types from `state_<domain>.rs`.
- Adds `Arc<FireDomainHandle>` field + getter to `FireAppCore`.
- Renames every call site in native code via a domain-method mapping table (the mapping table is maintained in the implementation plan and verified via `git grep`).
- Deletes the corresponding `state_<domain>.rs` after its contents are empty.

After all sub-phases: `handle.rs` is deleted; `state_*.rs` files are deleted; `fire-uniffi/src/lib.rs` contains the `FireAppCore` facade plus the three top-level `#[uniffi::export]` free functions (`plain_text_from_html`, `preview_text_from_html`, `monogram_for_username`).

### Phase 4: Android Generated Path Rename

The iOS directory layout (`Generated/FireUniFfi/`), the updated `project.yml` source group, and the sync-script rewrite all landed in Phase 1 — they had to, because multi-namespace bindgen breaks the single-file iOS pipeline on contact. This phase only finishes the Android side.

**File: `native/android-app/build.gradle.kts`**
- Line 10: change `val generatedUniffiRootDir = layout.buildDirectory.dir("generated/uniffi")` to `layout.buildDirectory.dir("generated/source/uniffi")`.
- Lines 45-48 path variables follow.
- Update `inputs` / `outputs` paths used by `registerSyncFireUniffiBindingsTask`.

**File: `native/android-app/scripts/sync_uniffi_bindings.sh`**
- No change (receives paths as arguments from Gradle).

**File: `native/android-app/README.md`**
- Replace the current "generated Kotlin bindings" description with the new path and a sentence that clarifies why generated sources live under `build/generated/source/` (AGP convention, not `src/main/kotlin`).

**File: `native/ios-app/README.md`**
- Replace any references to the single `Generated/fire_uniffi.swift` with the `Generated/FireUniFfi/` directory layout (reflect the Phase 1 change in docs).

Verification:
- `./gradlew clean assembleDebug` produces Kotlin files under `build/generated/source/uniffi/debug/`.
- `ls native/ios-app/Generated/FireUniFfi/*.swift | wc -l` shows 9 (only Swift surface count; Android path rename is orthogonal to this count).

### Phase 5: Verification

**File: (no source changes)**
- Run: `cargo test --workspace` -- unit tests for all 9 crates pass.
- Run: `./gradlew :app:testDebugUnitTest` -- Android unit tests (including `TopicPresentationTest`) pass.
- Run: `xcodebuild test -scheme FireUnitTests -destination 'platform=iOS Simulator,name=iPhone 15'` -- iOS tests pass.
- Manual smoke: login flow (iOS + Android), topic list, topic detail (post + reply + reaction), notifications tap-through, diagnostics log export. Matches pre-refactor behavior.
- Inspect file sizes: `find native/ios-app/Generated/FireUniFfi -name '*.swift' -exec wc -l {} +` -- each file under ~5,000 lines. `find native/android-app/build/generated/source/uniffi -name '*.kt' -exec wc -l {} +` -- each under ~3,000 lines.

## Architectural Notes

- **Semver impact:** breaking to iOS and Android app crates only. No external / third-party consumer of `fire-uniffi` exists.
- **Single cdylib preserved:** `fire-uniffi` remains the sole `cdylib`/`staticlib` producer. Android JNA `System.loadLibrary("fire_uniffi")` loads once; iOS links `libfire_uniffi.a` once. Generated bindings in each namespace reference the same `UniffiLib.INSTANCE` / same C symbols.
- **UniFFI callback interface (`MessageBusEventHandler`) handling:** moves with `fire-uniffi-messagebus`. The Python post-processing patch that guards `print(...)` with `#if DEBUG` continues to apply because the `print(...)` is in the generated file that defines the callback interface, which follows the type into its new Swift file.
- **Async runtime:** `ffi_runtime()` currently lives in `fire-uniffi/src/panic.rs` via `uniffi::async_runtime`. Moves to `fire-uniffi-types` and each domain crate declares `#[uniffi::export(async_runtime = "tokio")]` on async methods. No functional change.
- **Cross-crate external types:** shared records are referenced across namespaces via UniFFI's external-type machinery. If the workspace's pinned UniFFI version exposes `#[uniffi::remote(Record)]`, use it; otherwise `uniffi::use_remote_type!` from the crate's `build.rs`. Exact syntax pinned during Phase 1 probe.
- **What is explicitly NOT changed:**
  - `fire-core` and `fire-models` public API -- UniFFI crates only re-shape the bridging layer.
  - `openwire` and `xlog-rs` submodules -- unaffected.
  - Native WebView login, Cloudflare challenge, cookie extraction from platform stores -- remain platform-owned per `CLAUDE.md`.
  - `fire_uniffiFFI` C header / modulemap output for iOS -- UniFFI emits one header + one modulemap per cdylib, unchanged.
  - Android AGP version, Kotlin version, minSdk, targetSdk.
- **New cross-crate dependencies:** every domain crate depends on `fire-uniffi-types`; the facade (`fire-uniffi`) depends on every domain crate. No cycles.
- **Build caching:** Gradle `inputs.dir(fireRepoRoot.resolve("rust/crates"))` continues to trigger rebuilds when any crate changes. Cargo handles per-crate incremental builds.
- **Rollback:** each phase is a single PR on its own branch merging into `main`; reverting a phase merge restores the prior state without cascading changes.

## File Change Summary

- `.gitignore` -- add `/uniffi/` to prevent regression.
- `Cargo.toml` -- register 8 new workspace members.
- `docs/architecture/ios-topic-detail-loading-and-notification-routing.md` -- update stale path reference.
- `docs/architecture/uniffi-multi-namespace-split.md` -- this document (new).
- `native/android-app/README.md` -- document new generated path.
- `native/android-app/build.gradle.kts` -- rename output path to `build/generated/source/uniffi/`.
- `native/android-app/scripts/sync_uniffi_bindings.sh` -- receives new path via arguments; no change required.
- `native/android-app/src/main/java/com/fire/app/DiagnosticsActivity.kt` -- rename handle calls to `handle.diagnostics().*`.
- `native/android-app/src/main/java/com/fire/app/DiagnosticsPresentation.kt` -- same.
- `native/android-app/src/main/java/com/fire/app/LogViewerActivity.kt` -- same.
- `native/android-app/src/main/java/com/fire/app/MainActivity.kt` -- rename handle calls to domain getters as needed.
- `native/android-app/src/main/java/com/fire/app/RequestTraceDetailActivity.kt` -- same.
- `native/android-app/src/main/java/com/fire/app/TopicDetailActivity.kt` -- rename topic-domain calls.
- `native/android-app/src/main/java/com/fire/app/TopicPresentation.kt` -- rename topic-domain calls.
- `native/android-app/src/main/java/com/fire/app/session/FireSessionStore.kt` -- rename every call; now constructs `FireAppCore`.
- `native/android-app/src/main/java/com/fire/app/session/FireWebViewLoginCoordinator.kt` -- rename session-domain calls.
- `native/android-app/src/test/java/com/fire/app/TopicPresentationTest.kt` -- rename call sites.
- `native/ios-app/Fire.xcodeproj/project.pbxproj` -- regenerated by xcodegen.
- `native/ios-app/README.md` -- document new Swift layout.
- `native/ios-app/Sources/FireAppSession/FireSessionStore.swift` -- rename every call; constructs `FireAppCore`.
- `native/ios-app/project.yml` -- `sources:` points at `Generated/FireUniFfi` directory; preBuildScript `outputFiles:` enumerates per-namespace swifts.
- `native/ios-app/scripts/sync_uniffi_bindings.sh` -- copy all `.swift` into `Generated/FireUniFfi/`; iterate Python patch over the directory.
- `rust/crates/fire-uniffi-diagnostics/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-diagnostics/src/lib.rs` -- `FireDiagnosticsHandle` + `setup_scaffolding!("fire_uniffi_diagnostics")`.
- `rust/crates/fire-uniffi-diagnostics/src/records.rs` -- diagnostics-only records.
- `rust/crates/fire-uniffi-messagebus/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-messagebus/src/lib.rs` -- `FireMessageBusHandle` + `setup_scaffolding!("fire_uniffi_messagebus")`.
- `rust/crates/fire-uniffi-messagebus/src/records.rs` -- messagebus-only records (includes presence).
- `rust/crates/fire-uniffi-notifications/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-notifications/src/lib.rs` -- `FireNotificationsHandle`.
- `rust/crates/fire-uniffi-notifications/src/records.rs` -- notification / bookmark / draft records.
- `rust/crates/fire-uniffi-search/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-search/src/lib.rs` -- `FireSearchHandle`.
- `rust/crates/fire-uniffi-search/src/records.rs` -- search-only records.
- `rust/crates/fire-uniffi-session/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-session/src/lib.rs` -- `FireSessionHandle`.
- `rust/crates/fire-uniffi-topics/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-topics/src/lib.rs` -- `FireTopicsHandle`.
- `rust/crates/fire-uniffi-topics/src/records.rs` -- topic-detail-only records (voters, votes, poll results).
- `rust/crates/fire-uniffi-types/Cargo.toml` -- new crate manifest.
- `rust/crates/fire-uniffi-types/src/error.rs` -- moved from `fire-uniffi`.
- `rust/crates/fire-uniffi-types/src/lib.rs` -- `setup_scaffolding!("fire_uniffi_types")`; re-exports error, panic, shared, records.
- `rust/crates/fire-uniffi-types/src/panic.rs` -- moved from `fire-uniffi`; `PanicState`, `run_on_ffi_runtime`, `run_infallible`, `ffi_runtime`.
- `rust/crates/fire-uniffi-types/src/records.rs` -- cross-domain records.
- `rust/crates/fire-uniffi-types/src/shared.rs` -- `SharedFireCore::bootstrap` carved from `FireCoreHandle::new`.
- `rust/crates/fire-uniffi-user/Cargo.toml` -- new crate manifest (empty shell for profile work).
- `rust/crates/fire-uniffi-user/src/lib.rs` -- `FireUserHandle` empty shell.
- `rust/crates/fire-uniffi/Cargo.toml` -- depend on all 8 new crates; retains cdylib/staticlib/rlib.
- `rust/crates/fire-uniffi/src/bin/uniffi-bindgen.rs` -- unchanged.
- `rust/crates/fire-uniffi/src/error.rs` -- deleted (moved to types).
- `rust/crates/fire-uniffi/src/handle.rs` -- deleted. `FireCoreHandle` methods disperse to per-domain handles; the three top-level `#[uniffi::export]` free functions (`plain_text_from_html`, `preview_text_from_html`, `monogram_for_username`) move verbatim into `fire-uniffi/src/lib.rs`.
- `rust/crates/fire-uniffi/src/lib.rs` -- reduces to `setup_scaffolding!("fire_uniffi")` + `FireAppCore` facade + the three top-level free functions carried over from `handle.rs`.
- `rust/crates/fire-uniffi/src/panic.rs` -- deleted (moved to types).
- `rust/crates/fire-uniffi/src/state_diagnostics.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_messagebus.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_notification.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_search.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_session.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_topic_detail.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_topic_list.rs` -- deleted.
- `rust/crates/fire-uniffi/src/state_user.rs` -- deleted.
- `rust/crates/fire-uniffi/uniffi.toml` -- add per-namespace Kotlin package names.
- `uniffi/` -- deleted directory (was legacy tracked output).
