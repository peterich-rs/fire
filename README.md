# Fire

> Fire 是面向 [Linux.do](https://linux.do/) 社区的非官方第三方原生客户端，与 Linux.do 官方无直接关联。

Fire 是一个全新的原生客户端工作区，目标栈为 `Swift + Kotlin + Rust + UniFFI`。

当前仓库根目录只承载 Fire 自己的实现骨架：

- `rust/`: 共享 Rust 核心、模型与 UniFFI 边界
- `native/`: iOS / Android 原生宿主工程占位
- `docs/knowledge/`: 供不同客户端和技术栈复刻使用的后端协议知识库
- `third_party/`: 仓内第三方基础设施检出位；Fire 构建依赖优先从 crates.io 解析
- `references/fluxdo`: `fluxdo` 参考子模块，只用于协议行为核对

## 定位

- Fire 与旧 `fluxdo` 项目已经解耦。
- `references/fluxdo` 仅作为行为参考和逆向资料来源，不再是当前项目本体；初始化时不要递归拉取它自己的内部 submodule。
- 当前主线开发方向是原生平台登录 + Rust 共享核心，而不是继续扩展旧参考项目架构。

## 功能预览

### 明暗主题

界面已适配深色与浅色主题，下面两张图分别展示深色帖子详情和浅色首页。

<table>
  <tr>
    <td align="center">
      <img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.53.54.png" alt="深色主题帖子详情" width="260" />
      <br />
      <sub>深色主题</sub>
    </td>
    <td align="center">
      <img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.55.06.png" alt="浅色主题帖子详情" width="260" />
      <br />
      <sub>浅色主题</sub>
    </td>
  </tr>
</table>

### 首页

首页展示话题流、作者信息、浏览量和点赞数，整体布局保持了原生列表的阅读效率。

<img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.54.37.png" alt="首页" width="320" />

### 帖子详情

帖子详情页支持楼层回复、表情反应、统计信息和媒体内容展示。

<table>
  <tr>
    <td align="center">
      <img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.55.38.png" alt="帖子详情含媒体" width="260" />
    </td>
  </tr>
</table>

### 通知

通知页展示社区消息、系统通知和私信列表，便于快速查看未读动态。

<img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.54.05.png" alt="通知页" width="320" />

### 网络请求查看

内置网络请求查看页用于观察接口调用、状态码和耗时，方便调试登录、消息和列表加载流程。

<img src="native/ios-app/screenshoot/Simulator%20Screenshot%20-%20iPhone%2017%20Pro%20-%202026-04-06%20at%2019.54.16.png" alt="网络请求查看" width="320" />

## 目录

```text
fire/
  docs/
    knowledge/
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
    xlog-rs/
```

## 当前状态

- Rust workspace 已初始化
- `openwire` 已切换为 crates.io `0.1.0` 标准依赖；`mars-xlog` / `mars-xlog-core` 也从 crates.io 解析
- API 文档已按原生重构路径补充登录、CSRF、Cloudflare、MessageBus 等关键前置条件
- iOS / Android 宿主壳已打通登录、会话恢复、bootstrap 刷新与首个 topic list / detail 读取路径
- Android 现已在构建时生成 Kotlin UniFFI bindings 并打包真实 Rust `.so`
- iOS 现已在构建时生成 Swift UniFFI bindings、FFI headers/modulemap，并链接真实 Rust `staticlib`

## 本地验证

当前仓库通过根目录 `rust-toolchain.toml` 固定 Rust `1.88.0`，workspace 的 `rust-version` 与之对齐为 `1.88`。

```bash
cargo check
xcodegen generate --spec native/ios-app/project.yml
xcodebuild -project native/ios-app/Fire.xcodeproj -scheme Fire -destination 'generic/platform=iOS Simulator' build
ANDROID_HOME=$HOME/Library/Android/sdk ANDROID_SDK_ROOT=$HOME/Library/Android/sdk JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home native/android-app/gradlew -p native/android-app assembleDebug
```

## 说明

- `references/fluxdo` 是历史参考，不是 Fire 的运行时依赖。
- 如需初始化参考项目，只执行 `git submodule update --init references/fluxdo`；不要对 `references/fluxdo` 使用 `--recursive`，Fire 不编译也不依赖它的内部 submodule。
- Fire 的主仓库地址为 `https://github.com/peterich-rs/fire`。
- 根目录许可证当前仍沿用现有仓库的 `GPL-3.0`，如果 Fire 后续采用其他协议，需要单独重置。
