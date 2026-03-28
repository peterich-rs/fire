# AGENTS.md
This repository is the Fire native rebuild for the LinuxDo community.
The project uses Rust as the shared core and targets both iOS and Android native apps through the `native/` hosts plus the `rust/` workspace and UniFFI boundary.
Preserve clear boundaries between native platform code, shared Rust logic, backend protocol documentation, and third-party infrastructure repositories.
Treat code as the source of truth and keep documentation aligned with actual behavior.

Treat the following as the primary repository map:
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

Use these repository-specific rules when working in this codebase:
- `docs/backend-api*.md` is the current backend protocol documentation for Fire and should be kept in sync with implementation decisions.
- `references/fluxdo/` is a read-only reference project: an open-source, unofficial LinuxDo client implemented with Flutter. The backend API docs in `docs/` were derived from that project, so when documentation is incomplete or behavior is unclear, inspect `references/fluxdo/` for clues before guessing.
- `third_party/openwire/` is the shared Rust networking stack maintained by the repository owner. It is an OkHttp-style async network library and is the intended network foundation for Fire.
- `third_party/xlog-rs/` is the shared high-performance Rust logging library maintained by the repository owner and is the intended logging foundation for Fire.
- `references/` is for investigation and comparison, not for extending the current product architecture.
- `third_party/` contains reusable infrastructure repositories, not ad hoc app code.

Preserve the following architectural split:
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
  - networking integration
  - logging integration


# Workflow Orchestration

## 1. Plan Mode Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately — don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

## 2. Subagent Strategy
- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution
- Default subagent configuration is model `gpt-5.4-mini` with reasoning effort `high`

## 3. Worktree Strategy
- The repository root is the primary worktree
- For parallelizable and cleanly separated workstreams, use `git worktree`
- Keep secondary worktrees under `../fire-worktrees`
- Use conventional branch prefixes such as `feature/`, `bugfix/`, `refactor/`, and `docs/` based on the change type
- Prefer one reviewed workstream per secondary worktree branch so scope, verification, and doc sync stay isolated
- Do not let two active worktrees edit the same write-heavy area unless the split and merge plan is explicit up front
- Merge or retire a secondary worktree only after that workstream's code, tests, and docs are in sync
- Do not split tightly coupled or short single-path tasks into separate worktrees

## 4. Autonomous Documentation Maintenance
- Maintain documentation proactively after ANY implementation change — do not wait to be asked
- Before closing a task, sync all affected docs to the current code
- Treat the codebase as the single source of truth and align docs to it
- Remove obsolete, irrelevant, and duplicate content to keep docs clean
- Rewrite unclear sections when needed; do not just append patches onto stale documentation
- Ensure examples, commands, file paths, configs, and behavior descriptions reflect reality
- If documentation is already correct, explicitly confirm that it was checked

## 5. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

## 6. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: know everything you know, implement the elegant solution
- Skip this for simple, obvious fixes — don't over-engineer
- Challenge your own work before presenting it

## 7. Autonomous Bug Fixing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests — then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how
