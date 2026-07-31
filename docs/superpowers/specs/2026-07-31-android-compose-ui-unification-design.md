# Android Compose UI Unification — Login Page, Theme Foundation, App Icon

**Date:** 2026-07-31
**Status:** Draft (pending user spec review)
**Related:** iOS `FireTheme.swift`, `FireOnboardingView.swift`, `FireOnboardingCredentialFormView.swift`; Android `FireColors.kt`, `LoginWebViewFragment.kt`, `OnboardingFragment.kt`

## Problem Statement

Fire 的 iOS 和 Android 端 UI 视觉差异很大，根因是两端完全独立实现，没有共享设计语言：

1. **iOS 端**有成熟的设计系统：`FireTheme.swift`（383 行 token 体系）+ `FireComponents.swift`（1236 行 SwiftUI 组件库）+ `FireUIKitDesignLanguage.swift`（453 行 UIKit 组件库）。登录页是 UIKit 实现，三阶段状态机，视觉细节完善。
2. **Android 端**是纯 XML View + Fragment，几乎没有共享组件（`ui/common/` 目录为空），主题系统简陋（`FireColors.kt` 72 行，只能读 XML color resource）。登录页是 `LoginWebViewFragment`（718 行），视觉与 iOS 差距大。
3. **App 图标**：iOS 是真实的火焰 PNG 图标（全套尺寸），Android 是占位符——三条横线 vector。

目标是统一两端的视觉语言。iOS 的设计系统已经成熟，作为权威基准。Android 端需要建立与之对齐的 Compose 主题系统和组件实现。

## Design Decisions

| 决策 | 选择 | 理由 |
|------|------|------|
| 统一的含义 | 视觉一致，各自实现 | iOS 已有成熟的 UIKit/SwiftUI/Texture 体系，不值得为统一而重写。两端共享同一套设计 token，视觉上看起来一样。 |
| 设计基准 | iOS 现有设计系统 | `FireTheme.swift` + `FireComponents.swift` 已投入 1600+ 行设计系统代码，直接作为标准 |
| Android UI 框架 | Jetpack Compose | 渐进式迁移：Fragment 内嵌 ComposeView；主题/暗色模式/组件复用优势大；Kotlin 2.2.0 已支持 |
| 迁移范围 | 登录页 + 图标 + 主题基座 | 一次性把基础设施（Compose 依赖 + 主题系统）和登录页落地，为后续页面迁移铺路 |
| 迁移起点 | 仅登录页用 Compose | 其余页面保持 XML View + Fragment；Navigation graph 不动；业务逻辑不动 |
| 外观偏好 | system / light / dark（三档） | 对齐 iOS `FireAppearancePreference`；Android 是全新实现，没有 OLED 历史包袱 |
| 图标来源 | iOS `AppIcon-1024.png` 源图导出 | 确保 Android launcher icon 与 iOS 视觉完全一致 |

## Scope

### In Scope

- Android Compose 依赖引入 + 主题系统搭建
- Android 登录页（OnboardingFragment + LoginWebViewFragment）用 Compose 重写
- App 图标统一（Android adaptive icon 对齐 iOS 火焰图标）
- 登录 provider 品牌图标（Google/GitHub/X/Discord/Apple/Passkey）导入 Android

### Out of Scope

- iOS 端任何改动（iOS 是基准，不动）
- Android 其他页面迁移（Home/Profile/TopicDetail/Notifications 等）
- Navigation 架构变更（保持现有 Navigation Component XML graph）
- 外观偏好切换 UI（留到 Profile 页迁移时做）
- 旧 `FireColors.kt` + `fire_colors.xml` 的删除（其他页面仍在用，登录页迁移后旧系统与新 Compose 主题并存，后续页面逐个迁移后逐步清理）

## Architecture

### 总体结构

```
Android App
├── Compose 主题基座（新增）
│   ├── FireColorScheme.kt    ← light/dark ColorScheme，映射 iOS FireTheme.swift
│   ├── FireShapes.kt          ← 圆角 token（14/12/10/8）
│   ├── FireTypography.kt      ← 字号 token
│   ├── FireDimens.kt          ← 间距/尺寸 token
│   └── FireTheme.kt           ← Composable 入口，读取 FireAppearancePreference
│
├── 登录页（重写）
│   ├── OnboardingFragment.kt   ← 保留为 Fragment 容器，onCreateView 返回 ComposeView
│   ├── LoginWebViewFragment.kt ← 保留为 Fragment 容器，onCreateView 返回 ComposeView
│   ├── OnboardingScreen.kt     ← Composable，对齐 iOS FireOnboardingView 视觉
│   ├── CredentialForm.kt       ← Composable，对齐 iOS FireOnboardingCredentialFormView
│   └── OnboardingViewModel.kt  ← UI state（validating/credential/loggingIn）
│
├── App 图标（重做）
│   ├── ic_launcher_foreground   ← 火焰图形，从 iOS 1024px 源图导出
│   ├── ic_launcher.xml          ← adaptive-icon，更新 foreground 引用
│   └── colors.xml               ← launcher_background 对齐 iOS
│
├── 登录 provider 图标（新增）
│   └── res/drawable/
│       ├── ic_login_google.xml
│       ├── ic_login_github.xml
│       ├── ic_login_x.xml
│       ├── ic_login_discord.xml
│       ├── ic_login_apple.xml
│       └── ic_login_passkey.xml
│
└── 其他页面（不动）
    ├── Home / TopicDetail / Notifications / Profile ...
    └── 继续使用 XML View + FireColors.kt + fire_colors.xml
```

### 互操作策略

Fragment 作为 Compose 的宿主容器，不改变 Navigation graph：

```kotlin
class OnboardingFragment : Fragment() {
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View = ComposeView(requireContext()).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent {
            FireTheme {
                OnboardingScreen(onLogin = {
                    findNavController().navigate(R.id.action_onboarding_to_loginWebView)
                })
            }
        }
    }
}
```

WebView 在 Compose 中通过 `AndroidView` 嵌入，JS bridge 和 WebViewClient 逻辑原样复用：

```kotlin
AndroidView(factory = { context ->
    WebView(context).apply {
        configureLoginWebView(this)
        addJavascriptInterface(FireLoginJsInterface(...), "Android")
    }
})
```

## Component Design

### 1. Compose 主题 Token 系统

#### FireAppearancePreference

三档外观偏好，与 iOS 语义一致（不含 OLED）：

```kotlin
enum class FireAppearancePreference(val storageKey: String) {
    System("system"),
    Light("light"),
    Dark("dark");

    companion object {
        const val STORAGE_KEY = "fire.appearancePreference"
        private val prefs = FireApplication.getInstance()
            .getSharedPreferences("fire.appearance", Context.MODE_PRIVATE)

        fun load(): FireAppearancePreference =
            prefs.getString(STORAGE_KEY, null)?.let { from -> entries.firstOrNull { it.storageKey == from } } ?: System

        fun save(preference: FireAppearancePreference) =
            prefs.edit().putString(STORAGE_KEY, preference.storageKey).apply()
    }
}
```

#### FireColorScheme

从 iOS `FireTheme.swift` 逐条映射 RGB 值，构建 Compose `ColorScheme` + 扩展 token：

所有色值从 iOS `FireTheme.swift` 的 `UIColor(red:green:blue:alpha:)` 参数精确换算（`channel × 255` 四舍五入）。

**Accent（品牌橙色，`FireTheme.swift:68-81`）：**

| Token | Light | Dark | iOS Source |
|-------|-------|------|------------|
| `accent` | `Color(0xFFE8632E)` | `Color(0xFFFA7A3D)` | `uiAccent` |
| `accentSoft` | `Color(0xFFFAA666)` | `Color(0xFFFF9E66)` | `uiAccentSoft` |
| `accentGlow` | `Color(0xFFFCD1AD)` | `Color(0xFFFFB885)` | `uiAccentGlow` |

**Canvas（页面背景，`FireTheme.swift:109-136`）：**

| Token | Light | Dark |
|-------|-------|------|
| `canvasTop` | `Color(0xFFF5F2ED)` | `Color(0xFF000000)` |
| `canvasMid` | `Color(0xFFF2F0EB)` | `Color(0xFF000000)` |
| `canvasBottom` | `Color(0xFFEDEBE8)` | `Color(0xFF000000)` |

**Surface（卡片/行，`FireTheme.swift:138-198`）：**

| Token | Light | Dark |
|-------|-------|------|
| `surface` | `Color(0xFFFFFFFF)` | `Color(0xFF1C1C1E)` |
| `surfaceSecondary` | `Color(0xFFF2F0ED)` | `Color(0xFF2C2C2E)` |
| `chrome` | `Color(0xF0F2F0EB)` | `Color(0xEB141417)` |
| `iconWell` | `Color(0xFFF0EDEB)` | `Color(0xFF121213)` |

**Text（墨色级别，`FireTheme.swift:200-227`）：**

| Token | Light | Dark |
|-------|-------|------|
| `ink` | `Color(0xFF1C1C1F)` | `Color(red=1f, green=1f, blue=1f, alpha=0.96f)` |
| `subtleInk` | `Color(0xFF66666E)` | `Color(red=1f, green=1f, blue=1f, alpha=0.55f)` |
| `tertiaryInk` | `Color(0xFF8C8C94)` | `Color(red=1f, green=1f, blue=1f, alpha=0.38f)` |

> **注：** iOS dark ink 使用 `UIColor(white: 1.0, alpha: X)`，对应 Compose 的 `Color(red=1f, green=1f, blue=1f, alpha=Xf)`。实现时应定义为扩展函数或常量，不要强行用 ARGB hex 表示。

**Semantic：**

| Token | Light | Dark |
|-------|-------|------|
| `success` | `Color(0xFF40A173)` | `Color(0xFF61C78C)` |
| `warning` | `Color(0xFFCC7D33)` | `Color(0xFFF29E4D)` |
| `error` | `Color(0xFFE64738)` | `Color(0xFFFF6147)` |
| `info` | `Color(0xFF337AF5)` | `Color(0xFF669EFF)` |

**Borders / Dividers：**

| Token | Light | Dark |
|-------|-------|------|
| `divider` | `Color(0x14000000)` | `Color(0x14FFFFFF)` |
| `chromeBorder` | `Color(0x66FFFFFF)` | `Color(0x14FFFFFF)` |

#### FireShapes

```kotlin
object FireShapes {
    val cornerRadius: Dp = 14.dp       // 大卡片
    val mediumCornerRadius: Dp = 12.dp  // 中型卡片/chip 容器
    val smallCornerRadius: Dp = 10.dp   // 输入框/小控件
    val iconWellCornerRadius: Dp = 8.dp // 图标背景
    val chipCornerRadius: Dp = 100.dp   // pill 形 chip
    val iconWellSize: Dp = 30.dp
    val pageHorizontalInset: Dp = 16.dp
    val sectionSpacing: Dp = 16.dp
    val panelShadowRadius: Dp = 12.dp
}
```

来源：`FireTheme.swift` extension lines 365-383。

#### FireTheme Composable

```kotlin
@Composable
fun FireTheme(
    preference: FireAppearancePreference = FireAppearancePreference.load(),
    content: @Composable () -> Unit,
) {
    val colorScheme = when (preference) {
        System -> when {
            isSystemInDarkTheme() -> darkFireColorScheme()
            else -> lightFireColorScheme()
        }
        Light -> lightFireColorScheme()
        Dark -> darkFireColorScheme()
    }
    MaterialTheme(
        colorScheme = colorScheme,
        typography = fireTypography,
        shapes = fireShapes,
        content = content,
    )
}
```

自定义 token 通过 `CompositionLocal` 或 `MaterialTheme.colorScheme` 扩展属性暴露。

### 2. 登录页 Compose UI

#### 页面结构

对齐 iOS `FireOnboardingView`（1178 行）+ `FireOnboardingCredentialFormView`（623 行）：

```
OnboardingScreen (Composable)
├── BrandHeader
│   ├── FlameIcon (应用图标/品牌图标)
│   ├── AppName "Fire"
│   └── Subtitle
├── ErrorBanner (条件显示，FireErrorBanner 样式)
├── CredentialForm
│   ├── IdentifierField
│   │   ├── placeholder "用户名或邮箱"
│   │   ├── 48dp 高，10dp 圆角
│   │   └── 自定义背景 + 1px separator 描边
│   ├── PasswordField
│   │   ├── placeholder "密码"
│   │   ├── 48dp 高，10dp 圆角
│   │   ├── 右侧眼睛 toggle（显示/隐藏密码）
│   │   └── password keyboardType
│   ├── OptionsRow
│   │   ├── RememberCheckbox (checkmark.circle.fill / circle)
│   │   │   └── "记住密码" label，13sp
│   │   └── ForgotPasswordButton
│   │       └── "忘记密码?" 链接，13sp，系统蓝
│   ├── LoginButton
│   │   ├── 50dp 高，accent 背景，白色文字
│   │   ├── 禁用态：identifier/password 为空时
│   │   ├── 加载态：CircularProgressIndicator + "登录中…"
│   │   └── 上次使用密码登录时：1.5px accent 描边高亮
│   ├── LastLoginHint (条件显示)
│   │   └── "上次使用：xxx"，12sp，居中
│   └── ExternalLoginRow
│       ├── DividerLabel "- 其他方式 -"
│       └── 6 个 provider 按钮
│           ├── Google / GitHub / X / Discord / Apple / Passkey
│           ├── 52dp 高，14dp 圆角
│           ├── 1px 描边，上次使用的 provider 加 1.5px accent 描边
│           └── 各自品牌图标，24×24dp，alwaysOriginal rendering
└── DeveloperToolsButton (条件显示，iOS 有此入口)
```

#### OnboardingViewModel

```kotlin
sealed interface OnboardingPhase {
    data object Validating : OnboardingPhase
    data object Credential : OnboardingPhase
    data object LoggingIn : OnboardingPhase
}

data class OnboardingUiState(
    val phase: OnboardingPhase = OnboardingPhase.Credential,
    val error: String? = null,
    val savedCredential: FireSavedCredential? = null,
    val lastLoginMethod: FireLastLoginMethod? = null,
    val isLoggingIn: Boolean = false,
)

class OnboardingViewModel(
    private val sessionStore: FireSessionStore,
    private val loginCoordinator: FireWebViewLoginCoordinator,
) : ViewModel() {
    val uiState: StateFlow<OnboardingUiState>

    fun performLogin(identifier: String, password: String, remember: Boolean) {
        // Delegates to loginCoordinator / sessionStore (existing business logic, unchanged)
    }

    fun performExternalLogin(method: FireExternalLoginMethod) {
        // Delegates to loginCoordinator for OAuth provider flow
    }
}
```

业务逻辑（`FireSessionStore`, `FireWebViewLoginCoordinator`, `FireCredentialStore`, `FireCloudflareChallengeCoordinator`）完全复用，不改动。

#### WebView 交互

iOS 的 captcha 弹窗（`FireCaptchaLoginDialogController`）在 Android 端对应的是 `LoginWebViewFragment` 中的 WebView 内联。Android 的登录流程比 iOS 更 WebView-centric（hCaptcha 直接在 WebView 内渲染），这是平台差异，保持现有模式：

- `LoginWebViewFragment` 的 ComposeView 内部布局：native credential form（Compose）+ WebView（`AndroidView` 嵌入）
- WebView 的 `configureLoginWebView`、`FireLoginJsInterface`、OAuth polling、CF challenge retry 逻辑原样保留

#### 登录 Provider 枚举

新建 Android `FireExternalLoginMethod` enum，对齐 iOS：

```kotlin
enum class FireExternalLoginMethod(
    val displayName: String,
    @DrawableRes val iconRes: Int,
    val discourseProviderName: String?,  // null for passkey
) {
    Google("Google", R.drawable.ic_login_google, "google_oauth2"),
    GitHub("GitHub", R.drawable.ic_login_github, "github"),
    X("X", R.drawable.ic_login_x, "twitter"),
    Discord("Discord", R.drawable.ic_login_discord, "discord"),
    Apple("Apple", R.drawable.ic_login_apple, "apple"),
    Passkey("Passkey", R.drawable.ic_login_passkey, null);
}
```

### 3. App 图标统一

#### 图标导出流程

1. 从 iOS `App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 获取源图
2. 提取火焰前景图形，导出为 Android adaptive icon foreground：
   - **优先**：Vector drawable（`ic_launcher_foreground.xml`），108×108dp viewport，前景区域在中心 72×72dp 安全区内
   - **备选**：如果火焰图形过于复杂不适合 vector，导出 PNG 到 `mipmap-xxxhdpi/`（432×432px）等密度桶
3. 背景色从 iOS 源图采样，更新 `colors.xml` 中 `launcher_background`
4. `ic_launcher.xml` / `ic_launcher_round.xml` 结构不变，只更新 foreground 和 background 引用
5. Play Store 营销图标：从 1024 源图缩放到 512×512

#### 登录 Provider 图标

从 iOS `Assets.xcassets/LoginProvider*.imageset/` 的 PNG 源图提取，转换为 Android vector drawable，命名 `ic_login_{provider}.xml`，放入 `res/drawable/`。这些图标在 Compose UI 中通过 `painterResource()` 引用。

## File Change Summary

### 新增文件

| 文件路径 | 职责 |
|----------|------|
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt` | 三档外观偏好 enum + SharedPreferences 持久化 |
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt` | light/dark Compose ColorScheme + 扩展 token |
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireShapes.kt` | 圆角/尺寸 token |
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireTypography.kt` | 字号 token |
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireDimens.kt` | 间距 token |
| `android-app/src/main/java/com/fire/app/core/theme/compose/FireTheme.kt` | Composable 主题入口 |
| `android-app/src/main/java/com/fire/app/ui/auth/OnboardingScreen.kt` | Composable 登录主屏幕 |
| `android-app/src/main/java/com/fire/app/ui/auth/CredentialForm.kt` | Composable 凭据表单 |
| `android-app/src/main/java/com/fire/app/ui/auth/OnboardingViewModel.kt` | 登录页 UI state + 业务调用 |
| `android-app/src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt` | 外部登录 provider enum |
| `android-app/src/main/res/drawable/ic_login_google.xml` | Google 品牌图标 vector |
| `android-app/src/main/res/drawable/ic_login_github.xml` | GitHub 品牌图标 vector |
| `android-app/src/main/res/drawable/ic_login_x.xml` | X 品牌图标 vector |
| `android-app/src/main/res/drawable/ic_login_discord.xml` | Discord 品牌图标 vector |
| `android-app/src/main/res/drawable/ic_login_apple.xml` | Apple 品牌图标 vector |
| `android-app/src/main/res/drawable/ic_login_passkey.xml` | Passkey 图标 vector |

### 修改文件

| 文件路径 | 变更内容 |
|----------|----------|
| `android-app/build.gradle.kts` | 新增 Compose BOM + compiler + material3 + activity-compose 依赖；启用 `buildFeatures.compose` |
| `android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt` | `onCreateView` 改为返回 `ComposeView`，内部 `setContent { FireTheme { OnboardingScreen(...) } }` |
| `android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt` | UI 层改为 ComposeView（Compose form + AndroidView WebView），业务逻辑不动 |
| `android-app/src/main/res/drawable/ic_launcher_foreground.xml` | 替换占位符三条横线为火焰图形 |
| `android-app/src/main/res/values/colors.xml` | 更新 `launcher_background` 对齐 iOS |

### 不动的文件

- iOS 端所有文件（iOS 是视觉基准）
- `android-app/src/main/res/navigation/fire_nav_graph.xml`（导航图不变）
- `android-app/src/main/java/com/fire/app/session/` 下所有文件（业务逻辑不变）
- `android-app/src/main/java/com/fire/app/core/theme/FireColors.kt`（旧系统，其他页面仍在用）
- `android-app/src/main/res/values/fire_colors.xml` + `values-night/fire_colors.xml`（同上）
- 其他所有页面（Home/Profile/TopicDetail/Notifications/...）

## Implementation Phases

### Phase 1: Compose 依赖 + 主题基座

- `build.gradle.kts` 新增 Compose 依赖
- 新建 `core/theme/compose/` 下 6 个文件
- 从 iOS `FireTheme.swift` 逐条提取 RGB 值，填入 `FireColorScheme.kt`
- 验证：编译通过，`FireTheme` Composable 可在 preview 中渲染 light/dark

### Phase 2: 登录页 Compose 重写

- 新建 `OnboardingScreen.kt` + `CredentialForm.kt` + `OnboardingViewModel.kt`
- 新建 `FireExternalLoginMethod.kt`
- 导入 6 个 provider 图标 vector drawable
- `OnboardingFragment` 改为 ComposeView 容器
- `LoginWebViewFragment` UI 层改为 Compose（业务逻辑不动）
- 验证：登录流程端到端可用，视觉与 iOS 登录页对齐

### Phase 3: App 图标统一

- 从 iOS 1024px 源图导出 Android adaptive icon foreground
- 更新 `ic_launcher_foreground.xml` / `colors.xml`
- 验证：launcher 图标在 Android 设备上与 iOS 视觉一致

## Risks and Mitigations

| 风险 | 缓解 |
|------|------|
| Compose + XML View 混用的性能 | 登录页是低频页面，不会有性能问题。后续列表页迁移时再评估 |
| WebView 在 Compose 中的互操作 | `AndroidView` 是官方稳定的互操作 API。现有 `LoginWebViewFragment` 的 WebView 逻辑成熟，原样移入 |
| 两套主题系统并存（旧 `FireColors.kt` + 新 Compose theme） | token 值保持一致（都从 iOS 映射），登录页用新系统，其他页面用旧系统，不会有视觉不一致。后续逐页迁移后清理旧系统 |
| 图标导出质量 | iOS 1024px 源图分辨率足够。Vector drawable 优先，复杂图形用 PNG fallback。最终在真机上对比 iOS 确认 |
| Compose BOM 版本与 Kotlin 2.2.0 兼容性 | 使用 Compose BOM 2024.x（最新稳定版），Kotlin 2.2.0 自带 Compose compiler plugin，无需额外配置 |
