# Android Compose UI Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a Compose theme foundation on Android that mirrors iOS `FireTheme.swift`, rewrite the login page in Compose aligned with iOS `FireOnboardingView` visual, and unify the app icon with iOS.

**Architecture:** Fragment-as-host pattern — `OnboardingFragment` and `LoginWebViewFragment` keep their Fragment shells and Navigation graph entries, but `onCreateView` returns `ComposeView` instead of inflated XML. A new Compose theme package (`core/theme/compose/`) maps every iOS `FireTheme` token to Compose `ColorScheme` + extension properties. All existing business logic (`FireSessionStore`, `FireWebViewLoginCoordinator`, `FireCredentialStore`, `FireCloudflareChallengeCoordinator`, `FireLoginScripts`) is reused unchanged.

**Tech Stack:** Jetpack Compose (BOM 2025.06.00), Material3, Kotlin 2.2.0 (built-in Compose compiler), AndroidX Fragment + Navigation Component (unchanged), WebView via `AndroidView`.

**Spec:** `docs/superpowers/specs/2026-07-31-android-compose-ui-unification-design.md`

---

## Global Constraints

- **Kotlin version:** 2.2.0 (already in `build.gradle.kts` line 5 — built-in Compose compiler, no `plugin.compose` needed)
- **compileSdk:** 35, **minSdk:** 26, **targetSdk:** 35
- **Java/Kotlin target:** JVM 17
- **Appearance preference:** Three modes only — `system`, `light`, `dark`. No OLED mode. Storage key `"fire.appearancePreference"` in SharedPreferences `"fire.appearance"`.
- **Color token source of truth:** iOS `FireTheme.swift` at `native/ios-app/App/Core/FireTheme.swift`. All hex values verified against `UIColor(red:green:blue:alpha:)` parameters.
- **Business logic:** Zero changes to anything under `session/`, `data/`, `messagebus/`, `push/`, or UniFFI-generated code.
- **Navigation graph:** `src/main/res/navigation/fire_nav_graph.xml` must not change.
- **Old theme system:** `FireColors.kt` + `fire_colors.xml` stay for other pages. Do not delete or modify them.
- **String resources:** Reuse existing string resources where they exist (`R.string.onboarding_login`, `R.string.login_identifier_hint`, etc.). Do not duplicate.
- **No comments in code** unless explicitly requested.

---

## File Structure

| File | Responsibility |
|------|----------------|
| **New: Compose theme** | |
| `src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt` | Enum (system/light/dark) + SharedPreferences load/save |
| `src/main/java/com/fire/app/core/theme/compose/FireColorTokens.kt` | All color token constants (light + dark), mapped from iOS `FireTheme.swift` |
| `src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt` | `lightFireColorScheme()` + `darkFireColorScheme()` returning Compose `ColorScheme` + custom token holder |
| `src/main/java/com/fire/app/core/theme/compose/FireShapes.kt` | Corner radius + dimension tokens |
| `src/main/java/com/fire/app/core/theme/compose/FireTypography.kt` | Typography tokens |
| `src/main/java/com/fire/app/core/theme/compose/FireTheme.kt` | `@Composable` entry: reads `FireAppearancePreference`, wraps `MaterialTheme`, provides custom tokens via `CompositionLocal` |
| **New: Login UI** | |
| `src/main/java/com/fire/app/ui/auth/compose/OnboardingScreen.kt` | Full onboarding/login Composable screen |
| `src/main/java/com/fire/app/ui/auth/compose/CredentialForm.kt` | Credential form Composable (identifier/password/options/login button/external providers) |
| `src/main/java/com/fire/app/ui/auth/compose/LoginChrome.kt` | WebView chrome bar (close/title/url/sync button) + progress bar Composable |
| `src/main/java/com/fire/app/ui/auth/compose/ExternalLoginRow.kt` | External login provider buttons row Composable |
| `src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt` | Enum of OAuth providers (Google/GitHub/X/Discord/Apple/Passkey) |
| **New: Drawable resources** | |
| `src/main/res/drawable/ic_login_google.xml` | Google brand icon (vector) |
| `src/main/res/drawable/ic_login_github.xml` | GitHub brand icon (vector) |
| `src/main/res/drawable/ic_login_x.xml` | X brand icon (vector) |
| `src/main/res/drawable/ic_login_discord.xml` | Discord brand icon (vector) |
| `src/main/res/drawable/ic_login_apple.xml` | Apple brand icon (vector) |
| `src/main/res/drawable/ic_login_passkey.xml` | Passkey icon (vector) |
| **Modified** | |
| `build.gradle.kts` | Add Compose BOM + material3 + activity-compose dependencies; enable `buildFeatures.compose` |
| `src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt` | `onCreateView` returns `ComposeView` with `FireTheme { OnboardingScreen(...) }` |
| `src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt` | Replace XML view lookups with state holders; UI rendered via `ComposeView` + `AndroidView` for WebView |
| `src/main/res/drawable/ic_launcher_foreground.xml` | Replace placeholder three-bar vector with flame graphic |
| `src/main/res/values/colors.xml` | Update `launcher_background` to match iOS icon background |

---

## Phase 1: Compose Dependencies + Theme Foundation

### Task 1: Add Compose Dependencies to build.gradle.kts

**Files:**
- Modify: `native/android-app/build.gradle.kts`

**Context:** Kotlin 2.2.0 has a built-in Compose compiler plugin. We need to enable it via the `org.jetbrains.kotlin.plugin.compose` plugin, add the Compose BOM, and enable `buildFeatures.compose`. We also need `androidx.activity:activity-compose` for `setContent`.

- [ ] **Step 1: Add the Compose compiler plugin**

In `build.gradle.kts`, add the plugin to the `plugins` block (after line 5, the kotlin android plugin):

```kotlin
plugins {
    id("com.android.application") version "8.11.2"
    id("org.jetbrains.kotlin.android") version "2.2.0"
    id("org.jetbrains.kotlin.plugin.compose") version "2.2.0"
    id("androidx.navigation.safeargs.kotlin") version "2.8.9"
    id("com.google.gms.google-services") version "4.4.2" apply false
}
```

- [ ] **Step 2: Enable Compose build feature**

In the `buildFeatures` block (currently lines 93-95), add `compose = true`:

```kotlin
    buildFeatures {
        viewBinding = true
        compose = true
    }
```

- [ ] **Step 3: Add Compose dependencies**

In the `dependencies` block, after the existing material dependency (line 148), add:

```kotlin
    val composeBom = platform("androidx.compose:compose-bom:2025.06.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.10.1")
    debugImplementation("androidx.compose.ui:ui-tooling")
```

- [ ] **Step 4: Verify build compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add native/android-app/build.gradle.kts
git commit -m "build: add Jetpack Compose dependencies and enable compose build feature"
```

---

### Task 2: Create FireAppearancePreference

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt`
- Test: `native/android-app/src/test/java/com/fire/app/core/theme/compose/FireAppearancePreferenceTest.kt`

**Interfaces:**
- Produces: `FireAppearancePreference` enum with `System`, `Light`, `Dark` cases; `STORAGE_KEY = "fire.appearancePreference"`; `load(context)` and `save(context, preference)` methods.

- [ ] **Step 1: Write the failing test**

Create `native/android-app/src/test/java/com/fire/app/core/theme/compose/FireAppearancePreferenceTest.kt`:

```kotlin
package com.fire.app.core.theme.compose

import android.content.Context
import org.junit.Assert.assertEquals
import org.junit.Test
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.junit.runner.RunWith

@RunWith(RobolectricTestRunner::class)
class FireAppearancePreferenceTest {

    private fun context(): Context = RuntimeEnvironment.getApplication()

    @Test
    fun loadReturnsSystemWhenNoPreferenceStored() {
        val prefs = context().getSharedPreferences("test_appearance", Context.MODE_PRIVATE)
        prefs.edit().clear().apply()
        val loaded = FireAppearancePreference.load(context(), "test_appearance")
        assertEquals(FireAppearancePreference.System, loaded)
    }

    @Test
    fun saveThenLoadRoundTripsDark() {
        FireAppearancePreference.save(context(), FireAppearancePreference.Dark, "test_appearance")
        assertEquals(FireAppearancePreference.Dark, FireAppearancePreference.load(context(), "test_appearance"))
    }

    @Test
    fun saveThenLoadRoundTripsLight() {
        FireAppearancePreference.save(context(), FireAppearancePreference.Light, "test_appearance")
        assertEquals(FireAppearancePreference.Light, FireAppearancePreference.load(context(), "test_appearance"))
    }

    @Test
    fun loadFallsBackToSystemOnGarbageValue() {
        val prefs = context().getSharedPreferences("test_appearance", Context.MODE_PRIVATE)
        prefs.edit().putString("fire.appearancePreference", "garbage").apply()
        assertEquals(FireAppearancePreference.System, FireAppearancePreference.load(context(), "test_appearance"))
    }
}
```

- [ ] **Step 2: Add Robolectric test dependency**

In `build.gradle.kts`, in the `dependencies` block, add to test dependencies:

```kotlin
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
```

Add to `android` block (inside `android { }`), the test runner config:

```kotlin
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd native/android-app && ./gradlew test --tests "com.fire.app.core.theme.compose.FireAppearancePreferenceTest"`
Expected: FAIL — `FireAppearancePreference` class not found

- [ ] **Step 4: Write the implementation**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt`:

```kotlin
package com.fire.app.core.theme.compose

import android.content.Context

enum class FireAppearancePreference(val storageKey: String) {
    System("system"),
    Light("light"),
    Dark("dark");

    companion object {
        const val STORAGE_KEY = "fire.appearancePreference"
        private const val DEFAULT_PREFS_NAME = "fire.appearance"

        fun load(context: Context, prefsName: String = DEFAULT_PREFS_NAME): FireAppearancePreference {
            val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
            val stored = prefs.getString(STORAGE_KEY, null)
            return entries.firstOrNull { it.storageKey == stored } ?: System
        }

        fun save(context: Context, preference: FireAppearancePreference, prefsName: String = DEFAULT_PREFS_NAME) {
            context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                .edit()
                .putString(STORAGE_KEY, preference.storageKey)
                .apply()
        }
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd native/android-app && ./gradlew test --tests "com.fire.app.core.theme.compose.FireAppearancePreferenceTest"`
Expected: PASS — 4 tests pass

- [ ] **Step 6: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/core/theme/compose/FireAppearancePreference.kt \
        native/android-app/src/test/java/com/fire/app/core/theme/compose/FireAppearancePreferenceTest.kt \
        native/android-app/build.gradle.kts
git commit -m "feat: add FireAppearancePreference enum with system/light/dark modes"
```

---

### Task 3: Create FireColorTokens — Color Constants from iOS

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorTokens.kt`

**Context:** This file contains two internal objects (`LightTokens` and `DarkTokens`) holding every color constant from iOS `FireTheme.swift`. The hex values were verified by computing `round(channel * 255)` from the `UIColor(red:green:blue:alpha:)` parameters.

**Interfaces:**
- Produces: `LightTokens` and `DarkTokens` objects with `Color` properties for accent, canvas, surface, text, semantic, border tokens.

- [ ] **Step 1: Create the color token constants**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorTokens.kt`:

```kotlin
package com.fire.app.core.theme.compose

import androidx.compose.ui.graphics.Color

internal object LightTokens {
    val accent = Color(0xFFE8632E)
    val accentSoft = Color(0xFFFAA666)
    val accentGlow = Color(0xFFFCD1AD)

    val canvasTop = Color(0xFFF5F2ED)
    val canvasMid = Color(0xFFF2F0EB)
    val canvasBottom = Color(0xFFEDEBE8)

    val surface = Color(0xFFFFFFFF)
    val surfaceSecondary = Color(0xFFF2F0ED)
    val chrome = Color(0xF0F2F0EB)
    val chromeStrong = Color(0xFAF2F0EB)
    val iconWell = Color(0xFFF0EDEB)
    val softSurface = Color(0x8FFFFFFF)
    val track = Color(0xFFEBE9E8)

    val ink = Color(0xFF1C1C1F)
    val subtleInk = Color(0xFF66666E)
    val tertiaryInk = Color(0xFF8C8C94)
    val inverseInk = Color(0xFFFAF5ED)
    val inverseSubtleInk = Color(0xFFC7BCB1)

    val divider = Color(0x14000000)
    val chromeBorder = Color(0x66FFFFFF)
    val threadLine = Color(0x1A000000)

    val success = Color(0xFF40A173)
    val warning = Color(0xFFCC7D33)
    val error = Color(0xFFE64738)
    val info = Color(0xFF337AF5)

    val tagChipBackground = Color(0x1473737A)
    val tagChipForeground = Color(0xFF4D4D54)

    val skeletonBase = Color(0xFFE6E6E6)
    val skeletonHighlight = Color(0xFFF5F5F5)
}

internal object DarkTokens {
    val accent = Color(0xFFFA7A3D)
    val accentSoft = Color(0xFFFF9E66)
    val accentGlow = Color(0xFFFFB885)

    val canvasTop = Color(0xFF000000)
    val canvasMid = Color(0xFF000000)
    val canvasBottom = Color(0xFF000000)

    val surface = Color(0xFF1C1C1E)
    val surfaceSecondary = Color(0xFF2C2C2E)
    val chrome = Color(0xEB141417)
    val chromeStrong = Color(0xF5141415)
    val iconWell = Color(0xFF121213)
    val softSurface = Color(0x0FFFFFFF)
    val track = Color(0x1AFFFFFF)

    val ink = Color(0xFFFFFFFF).copy(alpha = 0.96f)
    val subtleInk = Color(0xFFFFFFFF).copy(alpha = 0.55f)
    val tertiaryInk = Color(0xFFFFFFFF).copy(alpha = 0.38f)
    val inverseInk = Color(0xFF1F1F21)
    val inverseSubtleInk = Color(0xFF66666B)

    val divider = Color(0x14FFFFFF)
    val chromeBorder = Color(0x14FFFFFF)
    val threadLine = Color(0x14FFFFFF)

    val success = Color(0xFF61C78C)
    val warning = Color(0xFFF29E4D)
    val error = Color(0xFFFF6147)
    val info = Color(0xFF669EFF)

    val tagChipBackground = Color(0x14FFFFFF)
    val tagChipForeground = Color(0xB8FFFFFF)

    val skeletonBase = Color(0xFF292929)
    val skeletonHighlight = Color(0xFF424242)
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorTokens.kt
git commit -m "feat: add FireColorTokens mapping iOS FireTheme.swift color values"
```

---

### Task 4: Create FireColorScheme + Custom Token Holder

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt`

**Context:** Compose's `ColorScheme` doesn't have slots for all our custom tokens (accentSoft, canvasTop/Mid/Bottom, iconWell, etc.). We extend it with a `FireExtendedColors` data class provided via `CompositionLocal`. The `ColorScheme` is built from Material3's standard slots (primary = accent, etc.) and the extended tokens are provided alongside.

**Interfaces:**
- Produces: `FireExtendedColors` data class; `CompositionLocal<FireExtendedColors>` named `LocalFireExtendedColors`; `lightFireColorScheme()` and `darkFireColorScheme()` functions; `fireExtendedColors(isLight: Boolean)` function; extension properties on `MaterialTheme` for accessing custom tokens (e.g., `MaterialTheme.fireExtended`).

- [ ] **Step 1: Create the color scheme and extended colors file**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt`:

```kotlin
package com.fire.app.core.theme.compose

import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.StaticProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color

data class FireExtendedColors(
    val accent: Color,
    val accentSoft: Color,
    val accentGlow: Color,
    val canvasTop: Color,
    val canvasMid: Color,
    val canvasBottom: Color,
    val surfaceSecondary: Color,
    val chrome: Color,
    val chromeStrong: Color,
    val iconWell: Color,
    val softSurface: Color,
    val track: Color,
    val ink: Color,
    val subtleInk: Color,
    val tertiaryInk: Color,
    val inverseInk: Color,
    val inverseSubtleInk: Color,
    val divider: Color,
    val chromeBorder: Color,
    val threadLine: Color,
    val tagChipBackground: Color,
    val tagChipForeground: Color,
    val skeletonBase: Color,
    val skeletonHighlight: Color,
)

val LocalFireExtendedColors: StaticProvidableCompositionLocal<FireExtendedColors> =
    compositionLocalOf { error("FireExtendedColors not provided. Wrap content in FireTheme.") }

fun lightFireColorScheme(): ColorScheme = lightColorScheme(
    primary = LightTokens.accent,
    onPrimary = Color.White,
    primaryContainer = LightTokens.accentSoft,
    onPrimaryContainer = Color.White,
    secondary = LightTokens.accentSoft,
    onSecondary = Color.White,
    error = LightTokens.error,
    onError = Color.White,
    background = LightTokens.canvasMid,
    onBackground = LightTokens.ink,
    surface = LightTokens.surface,
    onSurface = LightTokens.ink,
    surfaceVariant = LightTokens.surfaceSecondary,
    onSurfaceVariant = LightTokens.subtleInk,
    outline = LightTokens.divider,
    outlineVariant = LightTokens.divider,
)

fun darkFireColorScheme(): ColorScheme = darkColorScheme(
    primary = DarkTokens.accent,
    onPrimary = Color.White,
    primaryContainer = DarkTokens.accentSoft,
    onPrimaryContainer = Color.White,
    secondary = DarkTokens.accentSoft,
    onSecondary = Color.White,
    error = DarkTokens.error,
    onError = Color.White,
    background = DarkTokens.canvasMid,
    onBackground = DarkTokens.ink,
    surface = DarkTokens.surface,
    onSurface = DarkTokens.ink,
    surfaceVariant = DarkTokens.surfaceSecondary,
    onSurfaceVariant = DarkTokens.subtleInk,
    outline = DarkTokens.divider,
    outlineVariant = DarkTokens.divider,
)

fun fireExtendedColors(isLight: Boolean): FireExtendedColors = if (isLight) {
    FireExtendedColors(
        accent = LightTokens.accent,
        accentSoft = LightTokens.accentSoft,
        accentGlow = LightTokens.accentGlow,
        canvasTop = LightTokens.canvasTop,
        canvasMid = LightTokens.canvasMid,
        canvasBottom = LightTokens.canvasBottom,
        surfaceSecondary = LightTokens.surfaceSecondary,
        chrome = LightTokens.chrome,
        chromeStrong = LightTokens.chromeStrong,
        iconWell = LightTokens.iconWell,
        softSurface = LightTokens.softSurface,
        track = LightTokens.track,
        ink = LightTokens.ink,
        subtleInk = LightTokens.subtleInk,
        tertiaryInk = LightTokens.tertiaryInk,
        inverseInk = LightTokens.inverseInk,
        inverseSubtleInk = LightTokens.inverseSubtleInk,
        divider = LightTokens.divider,
        chromeBorder = LightTokens.chromeBorder,
        threadLine = LightTokens.threadLine,
        tagChipBackground = LightTokens.tagChipBackground,
        tagChipForeground = LightTokens.tagChipForeground,
        skeletonBase = LightTokens.skeletonBase,
        skeletonHighlight = LightTokens.skeletonHighlight,
    )
} else {
    FireExtendedColors(
        accent = DarkTokens.accent,
        accentSoft = DarkTokens.accentSoft,
        accentGlow = DarkTokens.accentGlow,
        canvasTop = DarkTokens.canvasTop,
        canvasMid = DarkTokens.canvasMid,
        canvasBottom = DarkTokens.canvasBottom,
        surfaceSecondary = DarkTokens.surfaceSecondary,
        chrome = DarkTokens.chrome,
        chromeStrong = DarkTokens.chromeStrong,
        iconWell = DarkTokens.iconWell,
        softSurface = DarkTokens.softSurface,
        track = DarkTokens.track,
        ink = DarkTokens.ink,
        subtleInk = DarkTokens.subtleInk,
        tertiaryInk = DarkTokens.tertiaryInk,
        inverseInk = DarkTokens.inverseInk,
        inverseSubtleInk = DarkTokens.inverseSubtleInk,
        divider = DarkTokens.divider,
        chromeBorder = DarkTokens.chromeBorder,
        threadLine = DarkTokens.threadLine,
        tagChipBackground = DarkTokens.tagChipBackground,
        tagChipForeground = DarkTokens.tagChipForeground,
        skeletonBase = DarkTokens.skeletonBase,
        skeletonHighlight = DarkTokens.skeletonHighlight,
    )
}

val MaterialTheme.fireExtended: FireExtendedColors
    @Composable
    @ReadOnlyComposable
    get() = LocalFireExtendedColors.current
```

- [ ] **Step 2: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/core/theme/compose/FireColorScheme.kt
git commit -m "feat: add FireColorScheme with extended color tokens via CompositionLocal"
```

---

### Task 5: Create FireShapes + FireTypography + FireTheme Composable

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireShapes.kt`
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTypography.kt`
- Create: `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTheme.kt`

**Interfaces:**
- Produces: `FireShapes` object with dimension constants; `fireTypography` Typography instance; `FireTheme(preference, content)` composable that wires everything together.

- [ ] **Step 1: Create FireShapes**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireShapes.kt`:

```kotlin
package com.fire.app.core.theme.compose

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

object FireShapes {
    val cornerRadius: Dp = 14.dp
    val mediumCornerRadius: Dp = 12.dp
    val smallCornerRadius: Dp = 10.dp
    val iconWellCornerRadius: Dp = 8.dp
    val chipCornerRadius: Dp = 100.dp
    val iconWellSize: Dp = 30.dp
    val pageHorizontalInset: Dp = 16.dp
    val sectionSpacing: Dp = 16.dp
    val panelShadowRadius: Dp = 12.dp
    val panelShadowY: Dp = 6.dp
}
```

- [ ] **Step 2: Create FireTypography**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTypography.kt`:

```kotlin
package com.fire.app.core.theme.compose

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

val fireTypography = Typography(
    displayLarge = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold),
    displayMedium = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold),
    headlineLarge = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Medium),
    titleSmall = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    bodyLarge = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Normal),
    bodyMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Normal),
    bodySmall = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Normal),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium),
)
```

- [ ] **Step 3: Create FireTheme composable entry**

Create `native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTheme.kt`:

```kotlin
package com.fire.app.core.theme.compose

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

@Composable
fun FireTheme(
    preference: FireAppearancePreference = FireAppearancePreference.load(LocalContext.current),
    content: @Composable () -> Unit,
) {
    val isDark = when (preference) {
        FireAppearancePreference.System -> isSystemInDarkTheme()
        FireAppearancePreference.Light -> false
        FireAppearancePreference.Dark -> true
    }
    val colorScheme = if (isDark) darkFireColorScheme() else lightFireColorScheme()
    val extended = fireExtendedColors(isLight = !isDark)

    androidx.compose.runtime.CompositionLocalProvider(
        LocalFireExtendedColors provides extended,
    ) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = fireTypography,
            content = content,
        )
    }
}
```

- [ ] **Step 4: Verify the full theme compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 5: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/core/theme/compose/FireShapes.kt \
        native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTypography.kt \
        native/android-app/src/main/java/com/fire/app/core/theme/compose/FireTheme.kt
git commit -m "feat: add FireTheme composable with shapes, typography, and extended colors"
```

---

## Phase 2: Login Provider Icons + ExternalLoginMethod

### Task 6: Add Login Provider Vector Drawables

**Files:**
- Create: `native/android-app/src/main/res/drawable/ic_login_google.xml`
- Create: `native/android-app/src/main/res/drawable/ic_login_github.xml`
- Create: `native/android-app/src/main/res/drawable/ic_login_x.xml`
- Create: `native/android-app/src/main/res/drawable/ic_login_discord.xml`
- Create: `native/android-app/src/main/res/drawable/ic_login_apple.xml`
- Create: `native/android-app/src/main/res/drawable/ic_login_passkey.xml`

**Context:** iOS has these as PNG images in `Assets.xcassets/LoginProvider*.imageset/`. For Android, we use Material Icons vector drawables where matching icons exist, and simple brand-styled vectors otherwise. The icons are 24dp, monochrome (tinted at runtime to match iOS `.alwaysOriginal` rendering).

- [ ] **Step 1: Create the provider icon drawables**

Create `native/android-app/src/main/res/drawable/ic_login_google.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M22.56,12.25c0,-0.78 -0.07,-1.53 -0.2,-2.25H12v4.26h5.92c-0.26,1.37 -1.04,2.53 -2.21,3.31v2.77h3.57c2.08,-1.92 3.28,-4.74 3.28,-8.09z" />
    <path
        android:fillColor="@android:color/white"
        android:pathData="M12,23c2.97,0 5.46,-0.98 7.28,-2.66l-3.57,-2.77c-0.98,0.66 -2.23,1.06 -3.71,1.06 -2.86,0 -5.29,-1.93 -6.16,-4.53H2.18v2.84C3.99,20.53 7.7,23 12,23z" />
    <path
        android:fillColor="@android:color/white"
        android:pathData="M5.84,14.09c-0.22,-0.66 -0.35,-1.36 -0.35,-2.09s0.13,-1.43 0.35,-2.09V7.07H2.18C1.43,8.55 1,10.22 1,12s0.43,3.45 1.18,4.93l2.85,-2.22 0.81,-0.62z" />
    <path
        android:fillColor="@android:color/white"
        android:pathData="M12,5.38c1.62,0 3.06,0.56 4.21,1.64l3.15,-3.15C17.45,2.09 14.97,1 12,1 7.7,1 3.99,3.47 2.18,7.07l3.66,2.84c0.87,-2.6 3.3,-4.53 6.16,-4.53z" />
</vector>
```

Create `native/android-app/src/main/res/drawable/ic_login_github.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M12,2C6.48,2 2,6.48 2,12c0,4.42 2.87,8.17 6.84,9.5 0.5,0.09 0.68,-0.22 0.68,-0.48 0,-0.24 -0.01,-0.87 -0.01,-1.71 -2.78,0.6 -3.37,-1.34 -3.37,-1.34 -0.45,-1.16 -1.11,-1.47 -1.11,-1.47 -0.91,-0.62 0.07,-0.61 0.07,-0.61 1,0.07 1.53,1.03 1.53,1.03 0.89,1.53 2.34,1.09 2.91,0.83 0.09,-0.65 0.35,-1.09 0.63,-1.34 -2.22,-0.25 -4.55,-1.11 -4.55,-4.94 0,-1.09 0.39,-1.98 1.03,-2.68 -0.1,-0.25 -0.45,-1.27 0.1,-2.64 0,0 0.84,-0.27 2.75,1.02 0.8,-0.22 1.65,-0.33 2.5,-0.34 0.85,0.01 1.7,0.12 2.5,0.34 1.91,-1.29 2.75,-1.02 2.75,-1.02 0.55,1.37 0.2,2.39 0.1,2.64 0.64,0.7 1.03,1.59 1.03,2.68 0,3.84 -2.34,4.69 -4.57,4.94 0.36,0.31 0.68,0.92 0.68,1.85 0,1.34 -0.01,2.42 -0.01,2.75 0,0.27 0.18,0.58 0.69,0.48C19.14,20.16 22,16.42 22,12A10,10 0,0,0 12,2z" />
</vector>
```

Create `native/android-app/src/main/res/drawable/ic_login_x.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M18.244,2.25h3.308l-7.227,8.26 8.502,11.24H16.17l-5.214,-6.817L4.99,21.75H1.68l7.73,-8.835L1.254,2.25H8.08l4.713,6.231zm-1.161,17.52h1.833L7.084,4.126H5.117z" />
</vector>
```

Create `native/android-app/src/main/res/drawable/ic_login_discord.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M19.27,5.33C17.94,4.71 16.5,4.26 15,4a0.09,0.09 0,0 0,-0.07 0.03c-0.18,0.33 -0.39,0.76 -0.53,1.09a16.09,16.09 0,0 0,-4.8 0c-0.14,-0.34 -0.35,-0.76 -0.54,-1.09c-0.01,-0.02 -0.04,-0.03 -0.07,-0.03c-1.5,0.26 -2.93,0.71 -4.27,1.33c-0.01,0 -0.02,0.01 -0.03,0.02c-2.72,4.07 -3.47,8.03 -3.1,11.95c0,0.02 0.01,0.04 0.03,0.05c1.8,1.32 3.53,2.12 5.24,2.65c0.03,0.01 0.06,0 0.07,-0.02c0.4,-0.55 0.76,-1.13 1.07,-1.74c0.02,-0.04 0,-0.08 -0.04,-0.09c-0.57,-0.22 -1.11,-0.48 -1.64,-0.78c-0.04,-0.02 -0.04,-0.08 0,-0.11c0.11,-0.08 0.22,-0.17 0.33,-0.25c0.02,-0.02 0.05,-0.02 0.07,-0.01c3.44,1.57 7.15,1.57 10.55,0c0.02,-0.01 0.05,-0.01 0.07,0.01c0.11,0.09 0.22,0.17 0.33,0.26c0.04,0.03 0.04,0.09 -0.01,0.11c-0.52,0.31 -1.07,0.56 -1.64,0.78c-0.04,0.01 -0.05,0.06 -0.04,0.09c0.32,0.61 0.68,1.19 1.07,1.74c0.03,0.01 0.06,0.02 0.09,0.01c1.72,-0.53 3.45,-1.33 5.25,-2.65c0.02,-0.01 0.03,-0.03 0.03,-0.05c0.44,-4.53 -0.73,-8.46 -3.1,-11.95c-0.01,-0.01 -0.02,-0.02 -0.04,-0.02zM8.52,14.91c-1.03,0 -1.89,-0.95 -1.89,-2.12s0.84,-2.12 1.89,-2.12c1.06,0 1.9,0.96 1.89,2.12c0,1.17 -0.84,2.12 -1.89,2.12zm6.97,0c-1.03,0 -1.89,-0.95 -1.89,-2.12s0.84,-2.12 1.89,-2.12c1.06,0 1.9,0.96 1.89,2.12c0,1.17 -0.83,2.12 -1.89,2.12z" />
</vector>
```

Create `native/android-app/src/main/res/drawable/ic_login_apple.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M17.05,12.04c-0.03,-2.85 2.33,-4.22 2.44,-4.29c-1.33,-1.95 -3.4,-2.22 -4.14,-2.25c-1.77,-0.18 -3.45,1.04 -4.35,1.04c-0.89,0 -2.27,-1.02 -3.74,-0.99c-1.93,0.03 -3.71,1.12 -4.7,2.86c-2.01,3.48 -0.51,8.64 1.44,11.47c0.95,1.39 2.08,2.94 3.56,2.88c1.43,-0.06 1.97,-0.92 3.7,-0.92c1.73,0 2.22,0.92 3.74,0.89c1.55,-0.03 2.53,-1.41 3.48,-2.81c1.09,-1.61 1.54,-3.17 1.57,-3.25c-0.03,-0.01 -3.01,-1.15 -3.04,-4.57zM14.08,3.59c0.79,-0.96 1.32,-2.29 1.18,-3.62c-1.14,0.05 -2.52,0.76 -3.34,1.71c-0.73,0.85 -1.37,2.21 -1.2,3.51c1.27,0.1 2.57,-0.65 3.36,-1.6z" />
</vector>
```

Create `native/android-app/src/main/res/drawable/ic_login_passkey.xml`:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24"
    android:tint="?attr/colorControlNormal">
    <path
        android:fillColor="@android:color/white"
        android:pathData="M9,1C6.24,1 4,3.24 4,6c0,2.05 1.24,3.81 3,4.58V11c0,2.76 2.24,5 5,5h0.17c-0.11,0.31 -0.17,0.65 -0.17,1c0,1.66 1.34,3 3,3s3,-1.34 3,-3c0,-0.35 -0.06,-0.69 -0.17,-1H19c0.55,0 1,-0.45 1,-1V8c0,-0.55 -0.45,-1 -1,-1h-2.42C15.44,4.39 12.97,1 9,1zM9,3c2.21,0 4,1.79 4,4c0,0.73 -0.2,1.41 -0.54,2H7v2h3c-1.65,0 -3,-1.35 -3,-3V6c0,-1.65 1.35,-3 3,-3zM17,9v2h-6c-1.65,0 -3,-1.35 -3,-3h2c0,0.55 0.45,1 1,1h5c0.55,0 1,-0.45 1,-1zM14.5,16c0.83,0 1.5,0.67 1.5,1.5S15.33,19 14.5,19S13,18.33 13,17.5S13.67,16 14.5,16z" />
</vector>
```

- [ ] **Step 2: Verify build**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/res/drawable/ic_login_*.xml
git commit -m "feat: add login provider brand icon vector drawables"
```

---

### Task 7: Create FireExternalLoginMethod Enum

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt`
- Test: `native/android-app/src/test/java/com/fire/app/ui/auth/FireExternalLoginMethodTest.kt`

**Interfaces:**
- Produces: `FireExternalLoginMethod` enum with `Google`, `GitHub`, `X`, `Discord`, `Apple`, `Passkey` cases. Each has `displayName`, `iconRes`, `discourseProviderName`.

- [ ] **Step 1: Write the failing test**

Create `native/android-app/src/test/java/com/fire/app/ui/auth/FireExternalLoginMethodTest.kt`:

```kotlin
package com.fire.app.ui.auth

import com.fire.app.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FireExternalLoginMethodTest {

    @Test
    fun allCasesHasSixProviders() {
        assertEquals(6, FireExternalLoginMethod.entries.size)
    }

    @Test
    fun discourseProviderNameMapsCorrectly() {
        assertEquals("google_oauth2", FireExternalLoginMethod.Google.discourseProviderName)
        assertEquals("github", FireExternalLoginMethod.GitHub.discourseProviderName)
        assertEquals("twitter", FireExternalLoginMethod.X.discourseProviderName)
        assertEquals("discord", FireExternalLoginMethod.Discord.discourseProviderName)
        assertEquals("apple", FireExternalLoginMethod.Apple.discourseProviderName)
        assertNull(FireExternalLoginMethod.Passkey.discourseProviderName)
    }

    @Test
    fun iconResIsSetForEachProvider() {
        FireExternalLoginMethod.entries.forEach { method ->
            assert(method.iconRes != 0) { "iconRes not set for $method" }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd native/android-app && ./gradlew test --tests "com.fire.app.ui.auth.FireExternalLoginMethodTest"`
Expected: FAIL — `FireExternalLoginMethod` not found

- [ ] **Step 3: Write the implementation**

Create `native/android-app/src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt`:

```kotlin
package com.fire.app.ui.auth

import androidx.annotation.DrawableRes
import com.fire.app.R

enum class FireExternalLoginMethod(
    val displayName: String,
    @DrawableRes val iconRes: Int,
    val discourseProviderName: String?,
) {
    Google("Google", R.drawable.ic_login_google, "google_oauth2"),
    GitHub("GitHub", R.drawable.ic_login_github, "github"),
    X("X", R.drawable.ic_login_x, "twitter"),
    Discord("Discord", R.drawable.ic_login_discord, "discord"),
    Apple("Apple", R.drawable.ic_login_apple, "apple"),
    Passkey("Passkey", R.drawable.ic_login_passkey, null),
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd native/android-app && ./gradlew test --tests "com.fire.app.ui.auth.FireExternalLoginMethodTest"`
Expected: PASS — 3 tests pass

- [ ] **Step 5: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/FireExternalLoginMethod.kt \
        native/android-app/src/test/java/com/fire/app/ui/auth/FireExternalLoginMethodTest.kt
git commit -m "feat: add FireExternalLoginMethod enum for OAuth providers"
```

---

## Phase 3: Login Page Compose Rewrite

### Task 8: Create OnboardingScreen Composable

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/auth/compose/OnboardingScreen.kt`

**Context:** This is the welcome/onboarding screen shown when the user is not logged in. It displays the app flame icon, app name, subtitle, and a login button that navigates to `LoginWebViewFragment`. Visually aligned with iOS `FireOnboardingView` brand header section.

This screen replaces the current `OnboardingFragment`'s XML layout (`fragment_onboarding.xml`). The Fragment itself stays — it just hosts this Composable via `ComposeView`.

**Interfaces:**
- Produces: `OnboardingScreen(onLogin: () -> Unit, error: String?)` composable.

- [ ] **Step 1: Create the OnboardingScreen composable**

Create `native/android-app/src/main/java/com/fire/app/ui/auth/compose/OnboardingScreen.kt`:

```kotlin
package com.fire.app.ui.auth.compose

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun OnboardingScreen(
    onLogin: () -> Unit,
    error: String? = null,
    modifier: Modifier = Modifier,
) {
    val fire = MaterialTheme.fireExtended

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(fire.canvasMid)
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Image(
            painter = painterResource(R.drawable.ic_fire_flame),
            contentDescription = stringResource(R.string.app_name),
            modifier = Modifier.size(56.dp),
        )

        Spacer(modifier = Modifier.height(20.dp))

        Text(
            text = stringResource(R.string.app_name),
            style = MaterialTheme.typography.displayMedium,
            color = fire.ink,
            fontWeight = FontWeight.Bold,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = stringResource(R.string.onboarding_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = fire.subtleInk,
        )

        Spacer(modifier = Modifier.weight(1f))

        if (error != null) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(FireShapes.smallCornerRadius))
                    .background(fire.surfaceSecondary)
                    .padding(12.dp),
            ) {
                Text(
                    text = error,
                    style = MaterialTheme.typography.bodySmall,
                    color = fire.subtleInk,
                    maxLines = 3,
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
        }

        Button(
            onClick = onLogin,
            modifier = Modifier
                .fillMaxWidth()
                .height(46.dp),
            shape = RoundedCornerShape(FireShapes.mediumCornerRadius),
            colors = ButtonDefaults.buttonColors(
                containerColor = fire.accent,
                contentColor = Color.White,
            ),
        ) {
            Text(
                text = stringResource(R.string.onboarding_login),
                fontSize = 16.sp,
            )
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/compose/OnboardingScreen.kt
git commit -m "feat: add OnboardingScreen composable aligned with iOS brand header"
```

---

### Task 9: Create CredentialForm Composable

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/auth/compose/CredentialForm.kt`

**Context:** This is the credential input form with identifier/password fields, remember-password checkbox, forgot-password link, login button, and last-login hint. Aligned with iOS `FireOnboardingCredentialFormView` (623 lines).

In the iOS version, the "sync" button triggers the WebView login flow (hCaptcha + session). In Android, the `LoginWebViewFragment` already has this logic. The Composable exposes callbacks for each action; the Fragment wires them to the existing business logic.

**Interfaces:**
- Produces:
  - `CredentialForm(identifier, password, isPasswordVisible, isRememberChecked, isLoginEnabled, isLoggingIn, onIdentifierChanged, onPasswordChanged, onPasswordVisibilityToggled, onRememberToggled, onLogin, onForgotPassword, lastLoginHint)` composable
  - `CredentialFormState` data class to hold form state

- [ ] **Step 1: Create the CredentialFormState**

Create `native/android-app/src/main/java/com/fire/app/ui/auth/compose/CredentialForm.kt`:

```kotlin
package com.fire.app.ui.auth.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Eye
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun CredentialForm(
    identifier: String,
    password: String,
    isPasswordVisible: Boolean,
    isRememberChecked: Boolean,
    isLoginEnabled: Boolean,
    isLoggingIn: Boolean,
    onIdentifierChanged: (String) -> Unit,
    onPasswordChanged: (String) -> Unit,
    onPasswordVisibilityToggled: () -> Unit,
    onRememberToggled: () -> Unit,
    onLogin: () -> Unit,
    onForgotPassword: () -> Unit,
    lastLoginHint: String? = null,
    modifier: Modifier = Modifier,
) {
    val fire = MaterialTheme.fireExtended
    val fieldShape = RoundedCornerShape(FireShapes.smallCornerRadius)

    Column(modifier = modifier) {
        OutlinedTextField(
            value = identifier,
            onValueChange = onIdentifierChanged,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
            placeholder = {
                Text(
                    text = stringResource(R.string.login_identifier_hint),
                    color = fire.subtleInk,
                )
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Email,
                imeAction = ImeAction.Next,
            ),
            shape = fieldShape,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = fire.surfaceSecondary,
                unfocusedContainerColor = fire.surfaceSecondary,
                focusedIndicatorColor = fire.divider,
                unfocusedIndicatorColor = fire.divider,
                focusedTextColor = fire.ink,
                unfocusedTextColor = fire.ink,
            ),
        )

        Spacer(modifier = Modifier.height(12.dp))

        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChanged,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp),
            placeholder = {
                Text(
                    text = stringResource(R.string.login_password_hint),
                    color = fire.subtleInk,
                )
            },
            singleLine = true,
            visualTransformation = if (isPasswordVisible) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            keyboardOptions = KeyboardOptions(
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done,
            ),
            keyboardActions = KeyboardActions(
                onDone = { if (isLoginEnabled) onLogin() },
            ),
            trailingIcon = {
                IconButton(onClick = onPasswordVisibilityToggled) {
                    Icon(
                        imageVector = if (isPasswordVisible) {
                            Icons.Default.VisibilityOff
                        } else {
                            Icons.Default.Eye
                        },
                        contentDescription = if (isPasswordVisible) {
                            stringResource(R.string.login_hide_password)
                        } else {
                            stringResource(R.string.login_show_password)
                        },
                        tint = fire.tertiaryInk,
                    )
                }
            },
            shape = fieldShape,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = fire.surfaceSecondary,
                unfocusedContainerColor = fire.surfaceSecondary,
                focusedIndicatorColor = fire.divider,
                unfocusedIndicatorColor = fire.divider,
                focusedTextColor = fire.ink,
                unfocusedTextColor = fire.ink,
            ),
        )

        Spacer(modifier = Modifier.height(12.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.clickable { onRememberToggled() },
            ) {
                Icon(
                    imageVector = if (isRememberChecked) {
                        Icons.Default.CheckCircle
                    } else {
                        Icons.Default.RadioButtonUnchecked
                    },
                    contentDescription = null,
                    tint = if (isRememberChecked) fire.accent else fire.tertiaryInk,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(5.dp))
                Text(
                    text = stringResource(R.string.login_remember_password),
                    style = MaterialTheme.typography.bodySmall,
                    color = fire.subtleInk,
                )
            }

            TextButton(onClick = onForgotPassword) {
                Text(
                    text = stringResource(R.string.login_forgot_password),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Button(
            onClick = onLogin,
            enabled = isLoginEnabled && !isLoggingIn,
            modifier = Modifier
                .fillMaxWidth()
                .height(50.dp),
            shape = RoundedCornerShape(FireShapes.smallCornerRadius),
            colors = ButtonDefaults.buttonColors(
                containerColor = fire.accent,
                contentColor = Color.White,
                disabledContainerColor = fire.accent.copy(alpha = 0.4f),
                disabledContentColor = Color.White.copy(alpha = 0.6f),
            ),
        ) {
            if (isLoggingIn) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = Color.White,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.login_in_progress),
                    fontSize = 16.sp,
                )
            } else {
                Text(
                    text = stringResource(R.string.action_sync_login),
                    fontSize = 16.sp,
                )
            }
        }

        if (lastLoginHint != null) {
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = lastLoginHint,
                style = MaterialTheme.typography.labelSmall,
                color = fire.subtleInk,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

If compilation fails due to missing string resources (`login_hide_password`, `login_show_password`, `login_remember_password`, `login_forgot_password`, `login_in_progress`), add them to `src/main/res/values/strings.xml`:

```xml
<string name="login_hide_password">隐藏密码</string>
<string name="login_show_password">显示密码</string>
<string name="login_remember_password">记住密码</string>
<string name="login_forgot_password">忘记密码?</string>
<string name="login_in_progress">登录中…</string>
```

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/compose/CredentialForm.kt \
        native/android-app/src/main/res/values/strings.xml
git commit -m "feat: add CredentialForm composable for login credential inputs"
```

---

### Task 10: Create ExternalLoginRow Composable

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/auth/compose/ExternalLoginRow.kt`

**Context:** A row of 6 provider buttons (Google/GitHub/X/Discord/Apple/Passkey) shown below the credential form. Each button is a bordered chip with the provider's icon. The last-used provider gets an accent-colored border highlight. Aligned with iOS external login stack in `FireOnboardingCredentialFormView`.

**Interfaces:**
- Produces: `ExternalLoginRow(onProviderSelected: (FireExternalLoginMethod) -> Unit, highlightedProvider: FireExternalLoginMethod?)` composable.

- [ ] **Step 1: Create the ExternalLoginRow composable**

Create `native/android-app/src/main/java/com/fire/app/ui/auth/compose/ExternalLoginRow.kt`:

```kotlin
package com.fire.app.ui.auth.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.fire.app.R
import com.fire.app.core.theme.compose.FireShapes
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.ui.auth.FireExternalLoginMethod

@Composable
fun ExternalLoginRow(
    onProviderSelected: (FireExternalLoginMethod) -> Unit,
    highlightedProvider: FireExternalLoginMethod? = null,
    modifier: Modifier = Modifier,
) {
    val fire = MaterialTheme.fireExtended

    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = "- 其他方式 -",
            style = MaterialTheme.typography.bodySmall,
            color = fire.tertiaryInk,
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 14.dp),
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            FireExternalLoginMethod.entries.forEach { method ->
                val isHighlighted = method == highlightedProvider
                val borderColor = if (isHighlighted) fire.accent else fire.divider
                val borderWidth = if (isHighlighted) 1.5.dp else 1.dp

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp)
                        .clip(RoundedCornerShape(FireShapes.cornerRadius))
                        .background(fire.surfaceSecondary)
                        .border(width = borderWidth, color = borderColor, shape = RoundedCornerShape(FireShapes.cornerRadius))
                        .clickable { onProviderSelected(method) },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painter = painterResource(method.iconRes),
                        contentDescription = stringResource(R.string.app_name) + " " + method.displayName,
                        tint = androidx.compose.ui.graphics.Color.Unspecified,
                        modifier = Modifier.size(24.dp),
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 2: Add missing import**

Add `import androidx.compose.foundation.shape.RoundedCornerShape` and `import androidx.compose.ui.draw.clip` to the imports if not already present.

- [ ] **Step 3: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 4: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/compose/ExternalLoginRow.kt
git commit -m "feat: add ExternalLoginRow composable for OAuth provider buttons"
```

---

### Task 11: Create LoginChrome Composable

**Files:**
- Create: `native/android-app/src/main/java/com/fire/app/ui/auth/compose/LoginChrome.kt`

**Context:** The WebView chrome bar that sits above the WebView in `LoginWebViewFragment`. Shows close button, page title, page URL, and a sync/login button. Plus a progress bar. This replaces the XML `login_chrome` LinearLayout + ProgressBar from `fragment_login_webview.xml`.

**Interfaces:**
- Produces: `LoginChrome(title, url, progress, onClose, onSync, isSyncEnabled)` composable.

- [ ] **Step 1: Create the LoginChrome composable**

Create `native/android-app/src/main/java/com/fire/app/ui/auth/compose/LoginChrome.kt`:

```kotlin
package com.fire.app.ui.auth.compose

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.fire.app.R
import com.fire.app.core.theme.compose.fireExtended

@Composable
fun LoginChrome(
    title: String,
    url: String,
    progress: Float?,
    isSyncEnabled: Boolean,
    onClose: () -> Unit,
    onSync: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val fire = MaterialTheme.fireExtended

    Column(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onClose, modifier = Modifier.size(36.dp)) {
                Icon(
                    imageVector = Icons.Default.Close,
                    contentDescription = stringResource(R.string.action_close),
                    tint = fire.ink,
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleSmall,
                    color = fire.ink,
                    maxLines = 1,
                )
                Text(
                    text = url,
                    style = MaterialTheme.typography.bodySmall,
                    color = fire.subtleInk,
                    maxLines = 1,
                )
            }

            TextButton(onClick = onSync, enabled = isSyncEnabled) {
                Text(
                    text = stringResource(R.string.action_sync_login),
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }

        if (progress != null) {
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/compose/LoginChrome.kt
git commit -m "feat: add LoginChrome composable for WebView chrome bar"
```

---

### Task 12: Rewrite OnboardingFragment to Use ComposeView

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`

**Context:** The Fragment stays as-is in the Navigation graph. Only `onCreateView` changes: instead of inflating XML, it returns a `ComposeView` that hosts `FireTheme { OnboardingScreen(...) }`.

**Interfaces:**
- Consumes: `OnboardingScreen` composable from Task 8; `FireTheme` from Task 5.

- [ ] **Step 1: Rewrite OnboardingFragment**

Replace the entire content of `native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt`:

```kotlin
package com.fire.app.ui.auth

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.fragment.app.Fragment
import androidx.navigation.fragment.findNavController
import com.fire.app.R
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.ui.auth.compose.OnboardingScreen

class OnboardingFragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        return ComposeView(requireContext()).apply {
            setViewCompositionStrategy(
                ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed
            )
            setContent {
                FireTheme {
                    OnboardingScreen(
                        onLogin = {
                            findNavController().navigate(R.id.action_onboarding_to_loginWebView)
                        },
                    )
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build and run**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/OnboardingFragment.kt
git commit -m "refactor: OnboardingFragment uses ComposeView with OnboardingScreen"
```

---

### Task 13: Rewrite LoginWebViewFragment UI Layer to Compose

**Files:**
- Modify: `native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt`

**Context:** This is the most complex task. The `LoginWebViewFragment` (718 lines) has tightly coupled `findViewById` calls. The strategy:

1. Keep ALL business logic methods unchanged: `configureLoginWebView`, `replayCookiesAndLoadMinimalLogin`, `ensureCloudflareClearanceForLogin`, `runMinimalLogin`, `onHcaptchaPass`, `onHcaptchaError`, `onHcaptchaExpired`, `onLoginResult`, `parseLoginResult`, `showSecondFactorDialog`, `handleCloudflareRetry`, `startLoginSurfacePolling`, `maybeRecoverActiveCloudflareOrFinalizeExternalLogin`, `completeExternalLoginAndNavigate`, `completeMinimalLoginAndNavigate`, `navigateHome`, `loginCloudflareFailureMessage`, `evaluateJavascriptSuspend`, `FireLoginJsInterface`.

2. Replace `onCreateView` to return `ComposeView` hosting a `LoginScreenContent` composable that renders: `LoginChrome` + `CredentialForm` + `AndroidView { WebView }`.

3. Replace `findViewById` calls with state hoisting: the Fragment holds mutable state for identifier, password, isPasswordVisible, isRememberChecked, webView progress, chrome title/url. These are passed to the Composable and updated via callbacks.

4. The WebView is created once in the `AndroidView` factory block and configured by `configureLoginWebView`. The JS bridge and WebViewClient are set up the same way.

**Interfaces:**
- Consumes: `LoginChrome`, `CredentialForm` composables; `FireTheme`; existing session coordinator logic.

> **IMPORTANT:** This task requires careful refactoring. The implementer should read the entire current `LoginWebViewFragment.kt` (718 lines) before starting. All method bodies that reference `view?.findViewById<EditText>(R.id.login_identifier_input)` etc. must be changed to use the Fragment's state fields directly.

- [ ] **Step 1: Add state fields to the Fragment**

At the top of `LoginWebViewFragment`, add state fields that the Composable will read:

```kotlin
private var identifierText: String = ""
private var passwordText: String = ""
private var isPasswordVisible: Boolean = false
private var isRememberChecked: Boolean = false
private var chromeTitle: String = ""
private var chromeUrl: String = ""
private var webViewProgress: Float? = null
```

These replace all `findViewById<EditText>(R.id.login_identifier_input).text?.toString()` calls.

- [ ] **Step 2: Replace onCreateView with ComposeView**

Replace the `onCreateView` method:

```kotlin
override fun onCreateView(
    inflater: LayoutInflater,
    container: ViewGroup?,
    savedInstanceState: Bundle?,
): View {
    return ComposeView(requireContext()).apply {
        setViewCompositionStrategy(
            ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed
        )
        setContent {
            FireTheme {
                LoginScreenContent(
                    chromeTitle = chromeTitle,
                    chromeUrl = chromeUrl,
                    webViewProgress = webViewProgress,
                    isSyncEnabled = identifierText.trim().isNotEmpty() &&
                        passwordText.isNotEmpty() && !isCompletingLogin,
                    identifier = identifierText,
                    password = passwordText,
                    isPasswordVisible = isPasswordVisible,
                    isRememberChecked = isRememberChecked,
                    isLoggingIn = isCompletingLogin,
                    onClose = { findNavController().popBackStack() },
                    onSync = { onSyncClicked() },
                    onIdentifierChanged = { identifierText = it },
                    onPasswordChanged = { passwordText = it },
                    onPasswordVisibilityToggled = { isPasswordVisible = !isPasswordVisible },
                    onRememberToggled = { isRememberChecked = !isRememberChecked },
                    onForgotPassword = { openForgotPassword() },
                    onWebViewCreated = { webView -> setupWebView(webView) },
                )
            }
        }
    }
}
```

- [ ] **Step 3: Create the LoginScreenContent composable**

Add this composable inside the Fragment file (or as a private function in the same file):

```kotlin
@Composable
private fun LoginScreenContent(
    chromeTitle: String,
    chromeUrl: String,
    webViewProgress: Float?,
    isSyncEnabled: Boolean,
    identifier: String,
    password: String,
    isPasswordVisible: Boolean,
    isRememberChecked: Boolean,
    isLoggingIn: Boolean,
    onClose: () -> Unit,
    onSync: () -> Unit,
    onIdentifierChanged: (String) -> Unit,
    onPasswordChanged: (String) -> Unit,
    onPasswordVisibilityToggled: () -> Unit,
    onRememberToggled: () -> Unit,
    onForgotPassword: () -> Unit,
    onWebViewCreated: (WebView) -> Unit,
) {
    val fire = MaterialTheme.fireExtended

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(fire.canvasMid),
    ) {
        LoginChrome(
            title = chromeTitle,
            url = chromeUrl,
            progress = webViewProgress,
            isSyncEnabled = isSyncEnabled,
            onClose = onClose,
            onSync = onSync,
        )

        Column(modifier = Modifier.padding(horizontal = 16.dp)) {
            CredentialForm(
                identifier = identifier,
                password = password,
                isPasswordVisible = isPasswordVisible,
                isRememberChecked = isRememberChecked,
                isLoginEnabled = identifier.trim().isNotEmpty() && password.isNotEmpty(),
                isLoggingIn = isLoggingIn,
                onIdentifierChanged = onIdentifierChanged,
                onPasswordChanged = onPasswordChanged,
                onPasswordVisibilityToggled = onPasswordVisibilityToggled,
                onRememberToggled = onRememberToggled,
                onLogin = onSync,
                onForgotPassword = onForgotPassword,
            )
        }

        AndroidView(
            modifier = Modifier.fillMaxWidth().weight(1f),
            factory = { context ->
                WebView(context).also(onWebViewCreated)
            },
        )
    }
}
```

- [ ] **Step 4: Create the setupWebView method**

Extract the WebView configuration from the current `onViewCreated` into a new method:

```kotlin
private fun setupWebView(webView: WebView) {
    configureLoginWebView(webView)
    webView.addJavascriptInterface(FireLoginJsInterface(this@LoginWebViewFragment), "Android")

    webView.webViewClient = object : WebViewClientCompat() {
        override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
            super.onPageStarted(view, url, favicon)
            webViewProgress = 0f
            updateChromeState(view)
        }

        override fun onPageFinished(view: WebView?, url: String?) {
            super.onPageFinished(view, url)
            webViewProgress = null
            updateChromeState(view)
            maybeRecoverActiveCloudflareOrFinalizeExternalLogin(webView)
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceErrorCompat,
        ) {
            super.onReceivedError(view, request, error)
            if (request.isForMainFrame) {
                webViewProgress = null
                updateChromeState(view)
            }
        }

        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
            val scheme = request.url.scheme?.lowercase()
            if (scheme == "http" || scheme == "https") {
                return false
            }
            Toast.makeText(
                requireContext(),
                R.string.login_blocked_external_navigation,
                Toast.LENGTH_SHORT,
            ).show()
            return true
        }

        override fun onSafeBrowsingHit(
            view: WebView,
            request: WebResourceRequest,
            threatType: Int,
            callback: SafeBrowsingResponseCompat,
        ) {
            webViewProgress = null
            Toast.makeText(
                requireContext(),
                R.string.login_safe_browsing_blocked,
                Toast.LENGTH_LONG,
            ).show()
            if (WebViewFeature.isFeatureSupported(WebViewFeature.SAFE_BROWSING_RESPONSE_BACK_TO_SAFETY)) {
                callback.backToSafety(true)
            } else {
                callback.showInterstitial(true)
            }
        }
    }

    webView.webChromeClient = object : WebChromeClient() {
        override fun onReceivedTitle(view: WebView?, title: String?) {
            super.onReceivedTitle(view, title)
            updateChromeState(view)
        }

        override fun onProgressChanged(view: WebView?, newProgress: Int) {
            super.onProgressChanged(view, newProgress)
            webViewProgress = if (newProgress < 100) newProgress / 100f else null
            updateChromeState(view)
        }

        override fun onCreateWindow(
            view: WebView,
            isDialog: Boolean,
            isUserGesture: Boolean,
            resultMsg: Message,
        ): Boolean {
            return FireWebViewSupport.routePopupIntoParent(view, resultMsg)
        }
    }

    replayCookiesAndLoadMinimalLogin(webView)
    startLoginSurfacePolling(webView)
}
```

- [ ] **Step 5: Update helper methods to use state fields**

Replace the `updateChrome` method:

```kotlin
private fun updateChromeState(webView: WebView?) {
    chromeTitle = webView?.title ?: getString(R.string.login_title)
    chromeUrl = webView?.url ?: loginBaseUrl
    (view as? ComposeView)?.invalidate()
}
```

Update `runMinimalLogin` to use state fields instead of `findViewById`:

```kotlin
private fun runMinimalLogin(
    webView: WebView,
    hcaptchaToken: String?,
    secondFactorToken: String?,
    isCloudflareRetry: Boolean = false,
) {
    if (identifierText.isBlank() || passwordText.isBlank()) {
        Toast.makeText(requireContext(), R.string.login_credentials_required, Toast.LENGTH_SHORT).show()
        return
    }
    if (!isCloudflareRetry) {
        cfRetryUsed = false
    }
    lastLoginHcaptchaToken = hcaptchaToken
    lastLoginSecondFactorToken = secondFactorToken
    isCompletingLogin = true
    webView.evaluateJavascript(
        FireLoginScripts.fireLoginInvocation(
            identifier = identifierText.trim(),
            password = passwordText,
            hcaptchaToken = hcaptchaToken,
            secondFactorToken = secondFactorToken,
        ),
        null,
    )
}
```

Update `onHcaptchaPass` to use state fields:

```kotlin
fun onHcaptchaPass(token: String) {
    lastHcaptchaToken = token
    val webView = currentWebView ?: return
    runMinimalLogin(webView, token, null)
}
```

Add a helper to get the current WebView:

```kotlin
private val currentWebView: WebView?
    get() = (view as? ComposeView)?.let { composeView ->
        composeView.findViewById<WebView>(android.R.id.content)?.let { _ ->
            null
        }
    }
```

> **Note:** Since `AndroidView` creates the WebView internally, getting a reference to it is tricky. The simplest approach is to store the WebView reference in a Fragment field when `setupWebView` is called:

Add to Fragment fields:
```kotlin
private var retainedWebView: WebView? = null
```

In `setupWebView`, after `configureLoginWebView(webView)`:
```kotlin
retainedWebView = webView
```

Then `currentWebView` becomes:
```kotlin
private val currentWebView: WebView? get() = retainedWebView
```

Update `onDestroyView`:
```kotlin
override fun onDestroyView() {
    oauthPollJob?.cancel()
    oauthPollJob = null
    retainedWebView?.destroy()
    retainedWebView = null
    super.onDestroyView()
}
```

- [ ] **Step 6: Update all remaining findViewById references**

Search through the remaining methods (`onHcaptchaError`, `onHcaptchaExpired`, `onLoginResult`, `showSecondFactorDialog`, `handleCloudflareRetry`, `completeMinimalLoginAndNavigate`, `completeExternalLoginAndNavigate`) and replace ALL `view?.findViewById<EditText>(R.id.login_identifier_input)`, `view?.findViewById<EditText>(R.id.login_password_input)`, and `view?.findViewById<MaterialButton>(R.id.sync_button)` calls with direct state field references.

For sync button enable/disable, the Composable's `isSyncEnabled` parameter already handles this via recomposition — just update `isCompletingLogin` and trigger recomposition by calling `(view as? ComposeView)?.invalidate()` or using a mutableState for `isCompletingLogin`.

The simplest approach: change `isCompletingLogin` to use `mutableStateOf`:

```kotlin
private var isCompletingLogin by mutableStateOf(false)
```

This makes the Composable automatically recompose when it changes.

Similarly:
```kotlin
private var identifierText by mutableStateOf("")
private var passwordText by mutableStateOf("")
private var isPasswordVisible by mutableStateOf(false)
private var isRememberChecked by mutableStateOf(false)
private var chromeTitle by mutableStateOf("")
private var chromeUrl by mutableStateOf("")
private var webViewProgress by mutableStateOf<Float?>(null)
```

- [ ] **Step 7: Update onSyncClicked and openForgotPassword**

Add these methods:

```kotlin
private fun onSyncClicked() {
    val token = lastHcaptchaToken
    if (token.isNullOrBlank()) {
        Toast.makeText(requireContext(), R.string.login_hcaptcha_required, Toast.LENGTH_SHORT).show()
        return
    }
    val webView = retainedWebView ?: return
    runMinimalLogin(webView, token, null)
}

private fun openForgotPassword() {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse("$loginBaseUrl/password-reset"))
    if (intent.resolveActivity(requireContext().packageManager) != null) {
        startActivity(intent)
    } else {
        Toast.makeText(requireContext(), R.string.login_sync_error, Toast.LENGTH_SHORT).show()
    }
}
```

- [ ] **Step 8: Add missing imports**

Add these imports to the top of the file:

```kotlin
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.fire.app.core.theme.compose.FireTheme
import com.fire.app.core.theme.compose.fireExtended
import com.fire.app.ui.auth.compose.CredentialForm
import com.fire.app.ui.auth.compose.LoginChrome
```

- [ ] **Step 9: Verify build compiles**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 10: Manual test — verify login flow works end-to-end**

Build and install on device/emulator. Verify:
1. Onboarding screen shows flame icon, app name, login button
2. Tapping login navigates to login screen
3. Credential form renders with identifier/password fields
4. Typing credentials + tapping sync triggers hCaptcha
5. Login completes and navigates to home

- [ ] **Step 11: Commit**

```bash
git add native/android-app/src/main/java/com/fire/app/ui/auth/LoginWebViewFragment.kt
git commit -m "refactor: LoginWebViewFragment UI layer to Compose with ComposeView"
```

---

## Phase 4: App Icon Unification

### Task 14: Replace Android Launcher Icon with Flame

**Files:**
- Modify: `native/android-app/src/main/res/drawable/ic_launcher_foreground.xml`
- Modify: `native/android-app/src/main/res/values/colors.xml`

**Context:** The iOS app icon at `native/ios-app/App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` is a flame on a dark background. The Android launcher currently uses a placeholder three-bar vector. We replace it with a flame vector drawable.

Since we cannot read the iOS PNG image directly (it requires visual inspection), we use a flame icon that matches the iOS visual: a stylized flame shape on the existing dark brown background (`#FF3A2C1E`).

- [ ] **Step 1: Replace the launcher foreground drawable**

Replace the content of `native/android-app/src/main/res/drawable/ic_launcher_foreground.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="@color/launcher_foreground"
        android:pathData="M54,28 C54,28 50,36 50,42 C50,48 54,52 54,52 C54,52 58,48 58,42 C58,36 54,28 54,28 Z M54,32 C54,32 56,38 56,44 C56,48 54,50 54,50 C54,50 52,48 52,44 C52,38 54,32 54,32 Z M44,48 C42,54 40,60 40,66 C40,78 46,86 54,86 C62,86 68,78 68,66 C68,60 66,54 64,50 C62,54 60,56 58,56 C60,52 60,46 58,40 C56,46 52,48 50,44 C50,50 48,52 46,50 C46,50 45,49 44,48 Z" />
</vector>
```

> **Note:** The exact flame path data should be verified against the iOS icon by visual comparison. If the above doesn't match well, the implementer should trace the iOS flame from the 1024px source image using a vector conversion tool (e.g., Vector Asset in Android Studio, or an online PNG-to-SVG converter, then convert to Android vector drawable).

- [ ] **Step 2: Verify launcher_background matches iOS**

Check if `launcher_background` in `src/main/res/values/colors.xml` needs updating. The current value is `#FF3A2C1E` (dark brown). If the iOS icon background is different, update this value. For now, assume it matches.

- [ ] **Step 3: Build and verify icon**

Run: `cd native/android-app && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL

Install on device and verify the launcher icon shows a flame on dark background.

- [ ] **Step 4: Commit**

```bash
git add native/android-app/src/main/res/drawable/ic_launcher_foreground.xml \
        native/android-app/src/main/res/values/colors.xml
git commit -m "feat: replace placeholder launcher icon with flame aligned with iOS"
```

---

## Verification Checklist

After all tasks are complete, verify:

- [ ] `./gradlew assembleDebug` builds successfully
- [ ] `./gradlew test` passes all unit tests
- [ ] Onboarding screen shows: flame icon, "Fire" title, subtitle, login button
- [ ] Login screen shows: chrome bar (close/title/url/sync), credential form, WebView
- [ ] Credential form has: identifier field, password field with eye toggle, remember checkbox, forgot password link, sync button
- [ ] Dark mode (system or forced) renders correctly with dark canvas, light text, accent orange
- [ ] Light mode renders correctly with warm paper canvas, dark text
- [ ] Launcher icon shows flame on dark background
- [ ] Login flow works end-to-end (enter credentials → hCaptcha → session → home)
- [ ] OAuth polling still works (navigate to `/auth/google` in WebView → returns to home)
- [ ] No regressions in other pages (Home, TopicDetail, Notifications, Profile)
