# Contributing to Fire

感谢为 Fire 提交改动。

本仓库当前处于原生重建阶段，代码边界、文档同步和 PR 范围控制比“快速堆功能”更重要。

## 开始之前

1. Fork 本仓库，并基于你的 fork 创建工作分支。
2. 初始化子模块：

```bash
git submodule update --init --recursive
```

3. 按改动类型使用清晰的分支前缀：
   - `feature/*`
   - `bugfix/*`
   - `refactor/*`
   - `docs/*`

## 提交流程

对于非微小改动，推荐先整理本地工作文档，再开始实现。

- 本仓库默认采用 `document -> code -> feedback` 的开发方式。
- `.codex/` 目录仅用于本地工作文档，不应提交到 git。
- 一个分支只做一条可独立评审的工作流，避免把无关功能混在同一个 PR 中。
- 修改实现时，请同步更新受影响的仓库文档，而不是只改代码。

## 代码边界

- `references/fluxdo/` 仅作为行为参考，不是当前产品实现目录。
- `third_party/` 是共享基础设施仓库，不要把 Fire 业务逻辑直接塞进去。
- `native/` 负责平台登录、Cookie 抽取、原生 UI 与平台能力。
- `rust/` 负责共享会话、协议编排、共享模型、MessageBus 与日志集成。

提交前请确认你的改动边界清晰，不要把多个无关主题塞进一个 PR。

## 本地验证

如果只修改 Rust 共享层，至少执行：

```bash
cargo fmt --all
cargo clippy -p fire-models -p fire-core -p fire-uniffi --all-targets --no-deps -- -D warnings
cargo test -p fire-models -p fire-core -p fire-uniffi --all-targets
```

如果修改 Android 原生工程，请尽量对齐 CI：

```bash
cd native/android-app
./gradlew testDebugUnitTest assembleDebug assembleRelease
```

如果修改 iOS 原生工程，请尽量对齐 CI：

```bash
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

如果某些验证因本地环境缺失而无法执行，请在 PR 描述中明确写出。

## 文档要求

- 后端协议变更或理解澄清，请同步更新 `docs/backend-api*.md`
- 架构边界变化，请同步更新 `docs/architecture/`
- 若只是本地过程文档，请放在 `.codex/`，不要提交

## Pull Request 要求

PR 描述至少应包含：

- 变更目的
- 范围说明
- 验证命令与结果
- 明确的 out-of-scope
- 是否涉及文档同步

如果你的改动依赖子模块变更、特定平台环境、或仍有已知限制，也请直接写在 PR 描述里。
