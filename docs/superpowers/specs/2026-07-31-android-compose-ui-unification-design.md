# Android Compose UI Unification — Login Parity, Theme Foundation, App Icon

**Date:** 2026-07-31  
**Status:** Spec (revised after code review against live iOS/Android login)  
**Related (authoritative sources):**

| Platform | Paths |
|----------|--------|
| iOS visual / interaction | `native/ios-app/App/Core/FireTheme.swift`, `App/Views/Other/FireOnboardingView.swift`, `App/Startup/FireOnboardingCredentialFormView.swift`, `App/Startup/FireOnboardingValidatingView.swift`, `App/Startup/FireExternalLoginMethod.swift`, `App/Views/Other/FireCaptchaLoginDialogController.swift`, `App/Startup/FireAutoLoginPlanner.swift`, `App/Startup/FireHeadlessExternalLoginEngine.swift` |
| Android current host | `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`, `LoginWebViewFragment.kt`, `core/theme/FireColors.kt`, `session/*` |
| Protocol knowledge | `docs/knowledge/discourse-official-login-flow.md`, `docs/knowledge/discourse-webview-login-guide.md` |

## Problem Statement

Fire Android 与 iOS 的登录体验差距不是“皮肤色差”，而是**产品交互模型不同**：

1. **iOS（目标基准）** — 单页 onboarding：
   - 三阶段状态机：`validating` → `credential` → `loggingIn`
   - 同一屏：品牌头 + error banner + 凭据表单 + 外部登录行
   - hCaptcha / 2FA 在 **sheet 弹层**（`FireCaptchaLoginDialogController`），不是主表单宿主
   - 支持自动登录、上次登录方式高亮、记住密码、键盘避让、开发者工具入口
2. **Android（现状）** — 两段式 WebView 中心：
   - `OnboardingFragment`：仅品牌 +「登录」按钮，跳转下一页
   - `LoginWebViewFragment`：chrome 栏 + 表单 + 全屏 WebView 内联 captcha
   - 无三阶段机、无外部登录图标行、无上次登录高亮、无 auto-login、文案多为英文
3. **主题 / 图标** — Android `FireColors.kt` 简陋；launcher 为占位三条横线，iOS 为完整火焰图标。

目标：Android 登录的**视觉 + 交互路径**对齐 iOS，达到可上架的生产级一致性。Compose 是实现手段；iOS 是产品与视觉权威。

## Review Findings (why the prior draft was incomplete)

| Issue | Prior draft | Required correction |
|-------|-------------|---------------------|
| Interaction model | 保留「欢迎页 → LoginWebView 表单+WebView」 | **单页 onboarding 承载表单**；WebView 仅作 captcha/OAuth/CF 辅助 surface |
| Phase machine | Design 写了 `Validating/Credential/LoggingIn`，plan Task 8 却只做欢迎按钮 | Design 与 plan **统一为三阶段单页** |
| Captcha UX | “Android 更 WebView-centric，保持内联” | 对齐 iOS：**弹层 / DialogFragment sheet**，主屏保持 native 表单 |
| External providers | Design 有，plan 未接到 onboarding 主路径 | 主屏 `ExternalLoginRow` 必做；OAuth 经 WebView sheet 启动 |
| Last-login / auto-login | 未规划 Android 缺的 store API | 新增 `FireLastLoginMethod` + 持久化；auto-login 作为同批或紧随 parity 任务 |
| Copy language | 混用 `Sync Login` 等英文 | 登录主路径文案 **中文对齐 iOS**（用户名或邮箱 / 密码 / 登录 / 登录中…） |
| Paths | 部分写成 `android-app/...` | 一律 `native/android-app/...` |
| Material icons | plan 使用不存在的 `Icons.Default.Eye` | 使用 `Icons.Filled.Visibility` / `VisibilityOff`（或 material-icons-extended） |
| ViewModel | Design 有 `OnboardingViewModel`，plan 无独立任务 | plan 必须有 ViewModel（或等价 state owner）任务 |
| OLED | 刻意三档 | 保持 system/light/dark；文档注明 iOS 另有 OLED，Android 首期不引入 |
| Scope creep risk | 2100 行 plan 把 `LoginWebViewFragment` 整页换成 form+WebView | 拆成：主屏 Compose parity + WebView surface 职责收缩 |

## Design Decisions

| # | Decision | Choice | Rejected | Why |
|---|----------|--------|----------|-----|
| 1 | Parity meaning | Visual + interaction path parity with iOS | Code-share / rewrite iOS | iOS stack is mature; Android adopts Compose |
| 2 | Login IA | **Single onboarding screen** owns form + phases | Two-step welcome → browser form | Matches `FireOnboardingView` |
| 3 | WebView role | Captcha / OAuth / CF challenge surface only | Form host with chrome + sync | Matches captcha sheet + external browser roles on iOS |
| 4 | UI framework | Jetpack Compose inside Fragment hosts | Full Activity rewrite / Nav graph rewrite | Incremental; keeps `fire_nav_graph.xml` stable during phase 1 |
| 5 | Theme baseline | Map `FireTheme.swift` tokens 1:1 | Invent Android-only palette | One brand language |
| 6 | Appearance | `system` / `light` / `dark` | Include OLED now | Avoid iOS OLED migration baggage; leave hook for later |
| 7 | Business logic | Reuse `session/*` + UniFFI; extend only missing host stores | Rewrite login in Rust for this task | Cookie / CF / JS login already work on Android |
| 8 | Navigation | Keep graph IDs; change destinations’ **content** | New Compose Navigation root | Lower risk; can collapse graph later |
| 9 | Icon | iOS `AppIcon-1024.png` → adaptive foreground | Keep three-bar placeholder | Production brand |

## Scope

### In Scope (this workstream)

1. Compose deps + `core/theme/compose/*` token system aligned to iOS
2. Login **interaction + visual parity**:
   - `OnboardingFragment` → Compose single-page onboarding (phases + brand + form + external row + error + keyboard)
   - Captcha/OAuth/CF via DialogFragment or full-screen secondary fragment **without** embedding the credential form
   - Provider brand icons + `FireExternalLoginMethod`
   - `FireLastLoginMethod` persistence + UI highlight
   - Chinese string parity for login chrome
3. App launcher icon unification (flame)
4. Unit tests for appearance preference + last-login store

### Explicitly Out of Scope (follow-ups)

- Migrating Home / TopicDetail / Notifications / Profile to Compose
- Deleting `FireColors.kt` / `fire_colors.xml` while other pages still use them
- Full iOS auto-login sophistication (headless external engine) if blocked — **minimum**: password auto-login when saved credential exists; headless OAuth can be phase-extend
- iOS code changes
- OLED appearance mode
- Rewriting Rust login protocol

## Target Architecture

### Interaction map (must match iOS)

```
Cold start / session expired
        │
        ▼
┌───────────────────────────────────────────┐
│ OnboardingFragment (Compose)              │
│  brand header (flame / Fire / subtitle)   │
│  error banner                             │
│  phase container:                         │
│    • Validating  (spinner + message)      │
│    • Credential  (form + external row)    │
│    • LoggingIn   (loading on form/host)   │
└───────────────┬───────────────────────────┘
                │ password login
                ▼
     CaptchaSheet / LoginWebSurface
     (WebView: hCaptcha + __fireLogin JS)
                │ success cookies
                ▼
           completeLogin → home

External provider / passkey
                │
                ▼
     LoginWebSurface (OAuth or passkey click)
                │
                ▼
           completeLogin → home
```

**Do not** keep the current product path “tap 登录 → second page that is half form half browser chrome” as the end state. Intermediate migration may temporarily route, but acceptance is single-page parity.

### Package layout

```
native/android-app/src/main/java/com/fire/app/
├── core/theme/compose/
│   ├── FireAppearancePreference.kt
│   ├── FireColorTokens.kt
│   ├── FireColorScheme.kt
│   ├── FireShapes.kt
│   ├── FireTypography.kt
│   ├── FireDimens.kt
│   └── FireTheme.kt
├── session/
│   ├── FireCredentialStore.kt          (existing)
│   ├── FireLastLoginStore.kt           (new — method enum + prefs/encrypted store)
│   └── … coordinators unchanged
└── ui/auth/
    ├── OnboardingFragment.kt           (ComposeView host)
    ├── OnboardingViewModel.kt          (phase + form state + login orchestration)
    ├── LoginWebViewFragment.kt         (Web surface host; form UI removed)
    ├── LoginCaptchaDialogFragment.kt   (optional DialogFragment alternative)
    └── compose/
        ├── OnboardingScreen.kt
        ├── ValidatingContent.kt
        ├── CredentialForm.kt
        ├── ExternalLoginRow.kt
        └── LoginWebChrome.kt           (only for Web surface, not main form)
```

Paths in all tables below use repo-root relative `native/android-app/...`.

### Fragment ↔ Compose host pattern

```kotlin
// OnboardingFragment — host only
override fun onCreateView(...): View =
    ComposeView(requireContext()).apply {
        setViewCompositionStrategy(DisposeOnViewTreeLifecycleDestroyed)
        setContent {
            FireTheme {
                val vm: OnboardingViewModel = viewModel()
                OnboardingScreen(
                    state = vm.uiState.collectAsStateWithLifecycle().value,
                    actions = vm,
                )
            }
        }
    }
```

WebView surfaces use `AndroidView` factory; retain a single `WebView` instance on the Fragment/Dialog for cookie/JS continuity. Destroy on `onDestroyView`.

### Theme tokens

Source of truth: `native/ios-app/App/Core/FireTheme.swift`.

Conversion rule: for opaque `UIColor(red:g:b:a:1)`,  
`hex_channel = round(channel * 255)`.

Verified samples (must match implementation):

| Token | Light | Dark |
|-------|-------|------|
| accent | `#E8632E` (0.91, 0.39, 0.18) | `#FA7A3D` (0.98, 0.48, 0.24) |
| canvasMid | `#F2F0EB` (0.95, 0.94, 0.92) | `#000000` |
| surface | `#FFFFFF` | `#1C1C1E` |
| surfaceSecondary | `#F2F0ED` (0.95, 0.94, 0.93) | `#2C2C2E` |
| ink | `#1C1C1F` (0.11, 0.11, 0.12) | white @ 0.96 alpha |
| subtleInk | `#66666E` (0.40, 0.40, 0.43) | white @ 0.55 alpha |

Dark ink **must** use alpha white, not opaque `#FFFFFF`.

Shapes (from iOS `FireTheme` extensions): corner 14 / 12 / 10 / 8; chip pill 100; page inset 16; section spacing 16.

`FireTheme { }` reads `FireAppearancePreference` and applies `MaterialTheme` + `CompositionLocal` for extended tokens (`fireExtended.accent`, `canvasMid`, …).

### Visual / interaction parity checklist (login)

Must match iOS `FireOnboardingView` + `FireOnboardingCredentialFormView`:

| Element | Spec |
|---------|------|
| Canvas | Full-bleed `canvasMid`; no top app bar on onboarding |
| Brand | Flame 44–56dp, title **Fire** bold title1-scale, subtitle **LinuxDo 原生客户端** secondary |
| Content layout | Brand + form as one vertical block, optically centered (~centerY − 24dp equivalent), horizontal inset 24dp |
| Error banner | Dismissible; shows host error strings; aborts logging-in phase |
| Identifier field | 48dp, 10dp radius, placeholder **用户名或邮箱**, no autocap |
| Password field | 48dp, 10dp radius, eye toggle (show/hide), go/ime → login |
| Options row | **记住密码** checkbox (circle / checkmark.circle style) + **忘记密码?** systemBlue link |
| Login button | 50dp, accent fill, white label **登录**; disabled when empty; loading **登录中…** + spinner |
| Last-login | Password method: accent border on login button; external method: accent border on that provider chip; hint text **上次使用：…** |
| External row | Label **其他方式**; 6 chips: Google / GitHub / X / Discord / Apple / Passkey; 52dp height, 14dp radius, 24dp brand icons, alwaysOriginal |
| Validating | Spinner + **正在校验登录态…**; optional cancel during auto-login |
| Keyboard | IME padding / scroll; tap outside dismisses |
| Captcha | Sheet/dialog WebView; white captcha chrome preferred; password fields **not** remounted under WebView |
| Success | Navigate home only after `canReadAuthenticatedApi` / existing Android completeLogin path |

### State model

```kotlin
enum class OnboardingPhase { Validating, Credential, LoggingIn }

enum class FireLastLoginMethod {
    Password, Google, GitHub, X, Discord, Apple, Passkey
}

enum class FireExternalLoginMethod(
    val displayName: String,
    val discourseProviderName: String?, // null = passkey
) {
    Google("Google", "google_oauth2"),
    GitHub("GitHub", "github"),
    X("X", "twitter"),
    Discord("Discord", "discord"),
    Apple("Apple", "apple"),
    Passkey("Passkey", null);
}

data class OnboardingUiState(
    val phase: OnboardingPhase = OnboardingPhase.Validating,
    val errorMessage: String? = null,
    val identifier: String = "",
    val password: String = "",
    val isPasswordVisible: Boolean = false,
    val rememberPassword: Boolean = false,
    val lastLoginMethod: FireLastLoginMethod? = null,
    val isLoginEnabled: Boolean = false,
    // entry: coldStart | sessionExpired | signedOut (mirror iOS FireOnboardingEntry)
    val entry: OnboardingEntry = OnboardingEntry.ColdStart,
)
```

`OnboardingViewModel` responsibilities:

- Drive phase transitions (mirror iOS publisher logic at host level, not pixel-perfect Combine)
- Prefill from `FireCredentialStore`; never wipe in-progress edits on nil credential
- Password login: enter `LoggingIn` → present captcha surface with identifier/password → on success save credential (if remember) + last method + `completeLogin`
- External login: present Web surface with auto-start provider / passkey script
- Startup: validating → optional auto-login (password if saved) → credential
- Signed-out entry: skip validating auto-login; show credential immediately

### Web surface (ex–LoginWebViewFragment)

**Keep** all proven machinery:

- `configureLoginWebView`, JS bridge, `FireLoginScripts`, OAuth polling
- Cloudflare challenge coordination / retry
- Second-factor handling
- `FireWebViewLoginCoordinator.completeLogin` / cookie capture

**Remove from this surface as product UI:**

- Credential form fields and “Sync Login” as the primary CTA for typing passwords  
  (password entry lives on onboarding)

**Chrome for Web surface** may retain close + progress + optional title for OAuth debugging; it is not the brand login page.

Navigation options (pick one in implementation; default recommended):

1. **Recommended:** `LoginCaptchaDialogFragment` / bottom sheet for password captcha; full-screen `LoginWebViewFragment` only for OAuth that needs multi-hop redirects  
2. Alternative: single `LoginWebViewFragment` with args `mode=captcha|oauth|passkey` and no form

### Strings (Chinese parity)

Add/replace login-facing strings so primary UI matches iOS:

| Key (suggested) | Value |
|-----------------|--------|
| `login_identifier_hint` | 用户名或邮箱 |
| `login_password_hint` | 密码 |
| `login_action` | 登录 |
| `login_in_progress` | 登录中… |
| `login_remember_password` | 记住密码 |
| `login_forgot_password` | 忘记密码? |
| `login_other_methods` | 其他方式 |
| `login_last_used` | 上次使用：%1$s |
| `onboarding_checking_login_state` | 正在校验登录态… |
| `onboarding_subtitle` | LinuxDo 原生客户端 (exists) |

Deprecate user-facing **Sync Login** as the main password CTA.

### App icon

1. Source: `native/ios-app/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
2. Adaptive foreground: vector preferred; else density mipmaps; safe zone 72/108
3. Background: sample from iOS source; update `launcher_background`
4. Visual QA against iOS home screen

Provider icons: from iOS `LoginProvider*.imageset` → `res/drawable/ic_login_*.xml` (or PNG if multicolor).

## Implementation Phases

### Phase 0 — Spec lock (this doc)

- [x] Align design to iOS single-page model  
- [x] Correct file paths and out-of-scope boundaries  
- [ ] User confirms captcha presentation (dialog vs full-screen fragment) if needed  

### Phase 1 — Compose + theme foundation

- Enable Compose compiler plugin + BOM in `native/android-app/build.gradle.kts`
- Add `core/theme/compose/*`
- Preview light/dark `FireTheme`
- Unit tests for `FireAppearancePreference`

### Phase 2 — Login stores + assets

- `FireLastLoginMethod` + store
- Provider drawables + `FireExternalLoginMethod`
- Chinese string resources

### Phase 3 — Onboarding Compose UI + ViewModel

- `OnboardingScreen` / `ValidatingContent` / `CredentialForm` / `ExternalLoginRow`
- Wire `OnboardingFragment` → ComposeView
- Keyboard + error banner + last-login chrome
- Phase transitions without captcha first (mock/no-op) for UI QA

### Phase 4 — Wire real login + shrink Web surface

- Present captcha/OAuth Web surface from ViewModel actions
- Move password JS login invocation off form-host fragment
- Preserve CF / 2FA / cookie completeLogin
- Auto-login password path when credential saved
- E2E: password, OAuth, passkey (if device supports), 2FA

### Phase 5 — App icon + verification

- Replace launcher foreground
- Full checklist below

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| WebView recreation loses cookies mid-login | Retain WebView on Fragment/Dialog field; prime cookies before load |
| Compose state not updating from WebView callbacks | Use `mutableStateOf` / `StateFlow` on main; never `ComposeView.invalidate()` as primary |
| Two theme systems | Token values match iOS; login uses Compose theme only |
| OAuth redirect needs full browser chrome | Full-screen Web surface mode; form stays on onboarding |
| Auto-login / headless OAuth gap vs iOS | Ship password auto-login first; document OAuth headless as follow-up if cost high |
| Material icon missing glyphs | Use Visibility icons or drawable resources; no nonexistent `Eye` |
| Navigation graph thrash | Keep IDs; only change destination view implementations |

## Acceptance Criteria

- [ ] Visual side-by-side with iOS login (light + dark): layout, type hierarchy, accent, field chrome
- [ ] Single primary login surface; no “welcome-only” dead-end page in final UX
- [ ] Password login completes via captcha sheet/surface and lands home
- [ ] External provider chips present and launch correct Discourse auth path
- [ ] Remember password + last-login highlight work across process death
- [ ] System dark mode tokens match table above
- [ ] Launcher icon is flame-aligned with iOS
- [ ] Home / TopicDetail / other XML pages still compile and run
- [ ] `./gradlew assembleDebug` and relevant unit tests pass

## File Change Summary

### New

- `native/android-app/src/main/java/com/fire/app/core/theme/compose/*` (theme package)
- `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingViewModel.kt`
- `native/android-app/src/main/java/com/fire/app/ui/auth/compose/*.kt`
- `native/android-app/src/main/java/com/fire/app/session/FireLastLoginStore.kt` (name flexible)
- `native/android-app/src/main/res/drawable/ic_login_*.xml`
- Tests under `native/android-app/src/test/java/com/fire/app/...`

### Modified

- `native/android-app/build.gradle.kts`
- `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`
- `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt` (role shrink)
- `native/android-app/src/main/res/values/strings.xml` (+ night colors only if needed)
- `native/android-app/src/main/res/drawable/ic_launcher_foreground.xml`
- `native/android-app/src/main/res/values/colors.xml` (`launcher_background`)
- Possibly `fire_nav_graph.xml` **only** if args/modes are required (prefer no structural change)

### Unchanged

- iOS tree
- Rust / UniFFI login protocol
- Non-auth feature Fragments
- `FireColors.kt` until later migrations

## Relationship to Implementation Plan

Executable task breakdown:  
`docs/superpowers/plans/2026-07-31-android-compose-ui-unification.md`

That plan **must** follow this interaction model. Any task that reintroduces form-on-WebView as the primary UX is out of date.
