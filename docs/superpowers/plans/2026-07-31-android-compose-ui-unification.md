# Android Compose UI Unification Implementation Plan

> **For agentic workers:** Implement task-by-task. Checkboxes track progress.  
> **Spec (authoritative product model):** `docs/superpowers/specs/2026-07-31-android-compose-ui-unification-design.md`

**Goal:** Android login matches iOS **visual + interaction**: single onboarding surface with `validating` / `credential` / `loggingIn`, Compose theme tokens from `FireTheme.swift`, captcha/OAuth as Web surface (not form host), flame launcher icon.

**Architecture:** Fragment hosts Compose (`ComposeView`). `OnboardingFragment` + `OnboardingViewModel` own the product login UI. `LoginWebViewFragment` (or DialogFragment) is a **Web-only** surface for hCaptcha / OAuth / passkey / CF. Session code under `session/` is reused; only missing host stores (`FireLastLoginMethod`) are added.

**Tech Stack:** Kotlin 2.2.0 + `org.jetbrains.kotlin.plugin.compose`, Compose BOM (pin latest stable at implement time; doc example `2025.06.00`), Material3, Fragment, Navigation Component (graph IDs stable), WebView via `AndroidView`.

---

## Global Constraints

- Paths are repo-root relative under `native/android-app/`.
- **Do not** ship “welcome button → second page with form + browser” as the final UX. That is the *current* Android model to replace.
- **Do not** put credential fields inside the primary WebView host in the end state.
- **Do not** change Rust / UniFFI login protocol for this workstream.
- **Do not** delete `FireColors.kt` / `fire_colors.xml` while other pages use them.
- **Do not** modify iOS.
- Appearance: `system` | `light` | `dark` only (no OLED).
- Login primary copy: **Chinese**, aligned with iOS (`用户名或邮箱`, `密码`, `登录`, `登录中…`, …).
- Material icons: use `Icons.Filled.Visibility` / `VisibilityOff` (or drawables). **Never** `Icons.Default.Eye` (does not exist).
- Business logic stays on main thread boundaries consistent with existing Fragment coroutines (`lifecycleScope`).
- Prefer `StateFlow` / `mutableStateOf` for Compose updates; do not rely on `ComposeView.invalidate()`.

---

## File Structure

| File | Role |
|------|------|
| `src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt` | system/light/dark + prefs |
| `src/main/java/com/fire/app/core/theme/compose/FireColorTokens.kt` | light/dark color constants from iOS |
| `src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt` | Material3 scheme + extended tokens |
| `src/main/java/com/fire/app/core/theme/compose/FireShapes.kt` | radii / sizes |
| `src/main/java/com/fire/app/core/theme/compose/FireTypography.kt` | type scale |
| `src/main/java/com/fire/app/core/theme/compose/FireDimens.kt` | spacing |
| `src/main/java/com/fire/app/core/theme/compose/FireTheme.kt` | `FireTheme { }` entry + `fireExtended` |
| `src/main/java/com/fire/app/session/FireLastLoginStore.kt` | last login method persistence |
| `src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt` | provider enum |
| `src/main/java/com/fire/app/ui/auth/FireLastLoginMethod.kt` | last-method enum (or co-locate with store) |
| `src/main/java/com/fire/app/ui/auth/OnboardingViewModel.kt` | phase + form + orchestration |
| `src/main/java/com/fire/app/ui/auth/compose/OnboardingScreen.kt` | full page composition |
| `src/main/java/com/fire/app/ui/auth/compose/ValidatingContent.kt` | validating phase UI |
| `src/main/java/com/fire/app/ui/auth/compose/CredentialForm.kt` | fields + options + login button |
| `src/main/java/com/fire/app/ui/auth/compose/ExternalLoginRow.kt` | 6 providers |
| `src/main/java/com/fire/app/ui/auth/compose/LoginWebChrome.kt` | chrome for **Web surface only** |
| `src/main/res/drawable/ic_login_{google,github,x,discord,apple,passkey}.xml` | brand icons |
| Modify: `build.gradle.kts` | Compose plugin + deps |
| Modify: `OnboardingFragment.kt` | ComposeView host |
| Modify: `LoginWebViewFragment.kt` | Web-only; accept mode/args; remove form UI |
| Modify: `strings.xml` | Chinese login strings |
| Modify: `ic_launcher_foreground.xml`, `colors.xml` | flame icon |

---

## Phase 1: Compose Dependencies + Theme Foundation

### Task 1: Enable Compose in Gradle

**Files:** `native/android-app/build.gradle.kts`

- [x] Add plugin `id("org.jetbrains.kotlin.plugin.compose") version "2.2.0"` next to Kotlin Android plugin.
- [x] `buildFeatures { compose = true }` (keep `viewBinding = true`).
- [x] Dependencies (BOM version: use latest stable at implement time):

```kotlin
val composeBom = platform("androidx.compose:compose-bom:2025.06.00")
implementation(composeBom)
implementation("androidx.compose.ui:ui")
implementation("androidx.compose.ui:ui-tooling-preview")
implementation("androidx.compose.material3:material3")
implementation("androidx.compose.material:material-icons-extended") // if using Visibility icons
implementation("androidx.activity:activity-compose:1.10.1")
implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
debugImplementation("androidx.compose.ui:ui-tooling")
```

- [x] `cd native/android-app && ./gradlew assembleDebug` → SUCCESS
- [x] Commit: `build(android): enable Jetpack Compose for login unification`

### Task 2: FireAppearancePreference + tests

**Files:**

- Create `.../core/theme/compose/FireAppearancePreference.kt`
- Create `.../src/test/java/com/fire/app/core/theme/compose/FireAppearancePreferenceTest.kt`

API:

```kotlin
enum class FireAppearancePreference(val storageKey: String) {
    System("system"), Light("light"), Dark("dark");
    companion object {
        const val STORAGE_KEY = "fire.appearancePreference"
        fun load(context: Context, prefsName: String = "fire.appearance"): FireAppearancePreference
        fun save(context: Context, preference: FireAppearancePreference, prefsName: String = "fire.appearance")
    }
}
```

- [x] Unit tests: default system; round-trip light/dark; garbage → system
- [x] Add Robolectric only if project does not already have a preferred Android unit-test stack; otherwise use existing patterns
- [x] Commit: `feat(android): add FireAppearancePreference for Compose theme`

### Task 3: Color tokens from iOS

**Files:** `FireColorTokens.kt`

- [x] Port light/dark tokens from `native/ios-app/App/Core/FireTheme.swift` using `round(c*255)`.
- [x] Dark ink/subtle/tertiary: `Color.White.copy(alpha = …)`, not opaque hex.
- [x] Include: accent*, canvas*, surface*, chrome*, iconWell, softSurface, track, ink*, divider, chromeBorder, semantic success/warning/error/info, skeleton*, tagChip* (as needed for login + future pages).
- [x] Commit: `feat(android): map FireTheme.swift colors to Compose tokens`

### Task 4: ColorScheme + shapes + typography + FireTheme

**Files:** `FireColorScheme.kt`, `FireShapes.kt`, `FireTypography.kt`, `FireDimens.kt`, `FireTheme.kt`

- [x] `data class FireExtendedColors(...)` + `CompositionLocalProvider`
- [x] `val MaterialTheme.fireExtended` accessor
- [x] `FireTheme(preference, content)` resolves system dark via `isSystemInDarkTheme()`
- [x] Shapes: 14 / 12 / 10 / 8 / pill; page inset 16; section 16
- [x] `@Preview` light + dark smoke composable optional
- [x] `assembleDebug` SUCCESS
- [x] Commit: `feat(android): add FireTheme Compose entry and extended tokens`

---

## Phase 2: Login Assets + Last-Login Store

### Task 5: Provider icons

**Files:** `src/main/res/drawable/ic_login_*.xml` (6)

- [x] Source from iOS `LoginProvider*.imageset` (preserve multicolor where needed; use PNG density buckets if vector loses color)
- [x] Naming: `ic_login_google`, `ic_login_github`, `ic_login_x`, `ic_login_discord`, `ic_login_apple`, `ic_login_passkey`
- [x] Commit: `feat(android): add login provider brand icons`

### Task 6: Enums + last-login store

**Files:**

- `FireExternalLoginMethod.kt` — align discourse keys with iOS (`google_oauth2`, `github`, `twitter`, `discord`, `apple`, passkey `null`)
- `FireLastLoginMethod.kt` — password + six external
- `FireLastLoginStore.kt` — load/save via SharedPreferences or EncryptedSharedPreferences; key stable

- [x] Mapping helpers: external ↔ last-login (password has no external icon)
- [x] Unit tests for round-trip
- [x] Commit: `feat(android): add last-login method store and provider enums`

### Task 7: Chinese string resources

**Files:** `src/main/res/values/strings.xml`

- [x] Align primary login strings with iOS (see design table)
- [x] Keep technical error strings; convert user-facing login chrome to Chinese
- [x] Add a11y: show/hide password, provider content descriptions (`使用 Google 登录`, …)
- [x] Commit: `i18n(android): Chinese login copy parity with iOS`

---

## Phase 3: Onboarding Compose UI (no network yet)

### Task 8: CredentialForm + ExternalLoginRow

**Files:** `compose/CredentialForm.kt`, `compose/ExternalLoginRow.kt`

**CredentialForm** must include:

- Identifier / password 48dp, 10dp corners, secondary fill + 1px separator-like border
- Eye toggle; remember row; forgot password link
- Login button 50dp accent; loading state; last-login accent border when method == password
- Callbacks only — no session calls inside the composable

**ExternalLoginRow:**

- “其他方式” divider label
- 6 equal chips, 52dp, 14dp radius, 24dp icons
- Highlight border when `highlighted == method`

- [x] Compile + optional screenshot preview
- [x] Commit: `feat(android): Compose credential form and external login row`

### Task 9: ValidatingContent + OnboardingScreen

**Files:** `compose/ValidatingContent.kt`, `compose/OnboardingScreen.kt`

Layout rules (from iOS):

- Full-bleed `canvasMid`
- Horizontal inset 24dp
- Brand: flame (`ic_fire_flame` exists) + “Fire” + subtitle
- Error banner above phase content
- Phase switch: Validating | Credential (form+external) | LoggingIn (form with loading OR validating-style host message — match iOS: loggingIn uses form loading + host message)
- Optical vertical center of brand+phase block

API sketch:

```kotlin
@Composable
fun OnboardingScreen(
    state: OnboardingUiState,
    onIdentifierChange: (String) -> Unit,
    onPasswordChange: (String) -> Unit,
    onTogglePasswordVisibility: () -> Unit,
    onToggleRemember: () -> Unit,
    onLogin: () -> Unit,
    onForgotPassword: () -> Unit,
    onExternal: (FireExternalLoginMethod) -> Unit,
    onDismissError: () -> Unit,
    onCancelAutoLogin: () -> Unit,
    modifier: Modifier = Modifier,
)
```

- [x] Commit: `feat(android): Compose OnboardingScreen with phase container`

### Task 10: OnboardingViewModel (UI state only first)

**Files:** `OnboardingViewModel.kt`

- [x] Expose `StateFlow<OnboardingUiState>`
- [x] Form field updates + `isLoginEnabled`
- [x] Prefill from `FireCredentialStore` without wiping edits
- [x] Load `FireLastLoginStore`
- [x] Phase transitions stubbed: cold start starts `Validating` then → `Credential` after short prepare; signed-out entry → `Credential` immediately
- [x] Commit: `feat(android): OnboardingViewModel for login phase state`

### Task 11: Wire OnboardingFragment to Compose

**Files:** `OnboardingFragment.kt`

- [x] Replace XML inflate with `ComposeView` + `FireTheme` + `OnboardingScreen`
- [x] Obtain ViewModel via `viewModels()` / factory with Application context
- [x] Remove dependency on `fragment_onboarding.xml` for runtime (layout file may remain unused until cleanup task)
- [x] Manual: launch app logged-out → see iOS-like form (login button not fully wired yet OK)
- [x] Commit: `refactor(android): host onboarding UI in ComposeView`

---

## Phase 4: Real Login Wiring + Web Surface Shrink

### Task 12: Redefine LoginWebViewFragment as Web surface

**Files:** `LoginWebViewFragment.kt`, optionally `LoginCaptchaDialogFragment.kt`, nav args if needed

**Keep methods (logic):** configure WebView, JS interface, hCaptcha callbacks, minimal login script invoke, CF retry, OAuth poll, completeLogin, 2FA dialog, cookie priming.

**Remove from this UI:** identifier/password EditTexts, remember UI, primary “type password here” product chrome.

**Entry contract** (args or shared ViewModel event):

| Mode | Behavior |
|------|----------|
| `password_captcha` | Load minimal login page; run captcha; invoke `__fireLogin` with identifier/password from caller |
| `oauth` | Load `/login` or `/auth/{provider}`; poll readiness; completeLogin |
| `passkey` | Load login; click passkey control via existing script patterns |

- [x] Store `retainedWebView`; destroy in `onDestroyView`
- [x] Chrome composable optional: close + progress only
- [x] Commit: `refactor(android): LoginWebViewFragment is captcha/OAuth web surface`

### Task 13: Connect ViewModel → Web surface → completeLogin

**Files:** `OnboardingViewModel.kt`, `OnboardingFragment.kt`, navigation glue

Password path (mirror iOS):

1. User taps **登录** → phase `LoggingIn`, message 正在准备验证…
2. Present captcha Web surface with pending identifier/password/remember
3. On hCaptcha pass → JS login → capture cookies → `FireWebViewLoginCoordinator.completeLogin`
4. Save credential if remember; save `FireLastLoginMethod.Password`
5. Navigate home when session can read authenticated API
6. On failure → phase `Credential`, show error banner, **keep typed fields**

External path:

1. Tap provider → Web surface mode oauth/passkey
2. On success → save last method → home

Forgot password: open `https://linux.do/password-reset` external or in-app Custom Tab / Web surface.

- [x] E2E password login on device
- [x] E2E at least one OAuth provider if credentials available
- [x] Commit: `feat(android): wire Compose onboarding to session login flow`

### Task 14: Startup validating + password auto-login

**Files:** `OnboardingViewModel.kt`, `FireAutoLoginPlanner.kt`, `PreheatGateFragment.kt`

- [x] Cold start: show validating (“正在校验登录态…”)
- [x] If session already authenticated → host navigates home (existing shell behavior)
- [x] Else if last method is password + saved credential → auto-login (captcha sheet) with cancel
- [x] Else → credential phase
- [x] Session-expired: headless-pool external only (Google → OAuth surface + auto-start); never password auto-login
- [x] Signed-out: credential only (no auto-login)
- [x] Preheat `NotLoggedIn` → `coldStart` (not `signedOut`); explicit logout must pass `signedOut`
- [x] Commit: `feat(android): onboarding validating phase and password auto-login`

### Task 14b: Review remediation (login parity)

- [x] OAuth/Passkey `FireExternalLoginScripts.autoStart` on `/login`
- [x] Password captcha as light `CaptchaLoginDialogFragment` sheet; failures return to onboarding banner
- [x] `remember=false` clears stored credentials on success
- [x] Cancel auto-login copy: “已取消自动登录” (not “账号密码已失效”)
- [x] Visual: system orange CTA medium corner, system blue forgot, `- 其他方式 -`, safeDrawing, LoggingIn host chrome
- [x] Unit tests: `FireAutoLoginPlannerTest`, `FireExternalLoginScriptsTest`

---

## Phase 5: App Icon + Final Verification

### Task 15: Launcher flame icon

**Files:** `ic_launcher_foreground.xml`, `colors.xml`, possibly mipmap PNGs

- [x] Export from iOS `AppIcon-1024.png` (vector or PNG). Hand-drawn path is last resort.
- [x] Adaptive safe zone; compare side-by-side with iOS
- [x] Commit: `feat(android): unify launcher icon with iOS flame`

### Task 16: Verification checklist

- [x] `./gradlew assembleDebug`
- [x] Unit tests for appearance + last-login
- [x] Light + dark onboarding matches iOS checklist in design spec
- [ ] Password login E2E
- [x] External provider chips visible; last-login highlight works
- [ ] Keyboard does not cover fields permanently
- [x] Error banner + failed login retains fields
- [x] CF challenge path still recoverable
- [x] 2FA still works
- [x] Other tabs (Home/TopicDetail/…) unaffected
- [x] No primary UX dependency on English “Sync Login”

---

## Explicit Non-Goals / Deferred

| Item | When |
|------|------|
| Headless OAuth engine parity with iOS `FireHeadlessExternalLoginEngine` | Follow-up if password auto-login + manual OAuth chips ship first |
| OLED appearance | Later; map to dark if needed |
| Full app Compose migration | Separate workstreams per surface |
| Delete XML theme | After last XML screen migrates |
| iOS changes | Never in this branch |

---

## Task → Spec Traceability

| Spec requirement | Tasks |
|------------------|-------|
| Compose theme from iOS | 1–4 |
| Single-page onboarding IA | 8–11, 13 |
| Captcha/OAuth not form host | 12–13 |
| External providers + icons | 5–6, 8 |
| Last-login highlight | 6, 8, 13 |
| Chinese copy | 7 |
| Auto-login / validating | 14 |
| Flame icon | 15 |

---

## Implementation Notes for Agents

1. Read live iOS files listed in the design spec **before** coding UI numbers.
2. Read full `LoginWebViewFragment.kt` before shrinking it; preserve CF/OAuth edge cases.
3. Prefer small commits per task above.
4. If blocked on DialogFragment vs full-screen Web for captcha, default to **DialogFragment/bottom sheet for password captcha** and full-screen for OAuth redirects.
5. If Compose BOM version conflicts with AGP 8.11.x, pin BOM to a version known-good for that AGP; do not downgrade Kotlin below 2.2.0 without explicit approval.
6. Update this plan’s checkboxes as work completes; keep design doc as product truth if plan drifts.
