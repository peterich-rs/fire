# Fire

Fire 是一个全新的原生客户端工作区，目标栈为 `Swift + Kotlin + Rust + UniFFI`。

当前仓库根目录只承载 Fire 自己的实现骨架：

- `rust/`: 共享 Rust 核心、模型与 UniFFI 边界
- `native/`: iOS / Android 原生宿主工程占位
- `docs/backend-api*`: 供新客户端开发使用的后端协议文档
- `third_party/`: `openwire` 与 `xlog-rs` 两个 Rust 依赖子模块
- `references/fluxdo`: 旧 `fluxdo` Flutter 工程参考子模块

## 定位

- Fire 与旧 `fluxdo` 项目已经解耦。
- `references/fluxdo` 仅作为行为参考和逆向资料来源，不再是当前项目本体。
- 当前主线开发方向是原生平台登录 + Rust 共享核心，而不是继续扩展旧 Flutter 架构。

## 目录

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

## 当前状态

- Rust workspace 已初始化
- `openwire` / `xlog-rs` 已纳入仓内子模块位
- API 文档已按原生重构路径补充登录、CSRF、Cloudflare、MessageBus 等关键前置条件
- iOS / Android 宿主壳已打通登录、会话恢复、bootstrap 刷新与首个 topic list / detail 读取路径
- Android 现已在构建时生成 Kotlin UniFFI bindings 并打包真实 Rust `.so`
- iOS 现已在构建时生成 Swift UniFFI bindings、FFI headers/modulemap，并链接真实 Rust `staticlib`

## 本地验证

```bash
cargo check
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build
ANDROID_HOME=$HOME/Library/Android/sdk ANDROID_SDK_ROOT=$HOME/Library/Android/sdk JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home native/android-app/gradlew -p native/android-app assembleDebug
```

## 说明

- `references/fluxdo` 是历史参考，不是 Fire 的运行时依赖。
- Fire 的主仓库地址为 `https://github.com/peterich-rs/fire`。
- 根目录许可证当前仍沿用现有仓库的 `GPL-3.0`，如果 Fire 后续采用其他协议，需要单独重置。
