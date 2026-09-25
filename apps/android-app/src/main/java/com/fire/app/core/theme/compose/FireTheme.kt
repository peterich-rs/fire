package com.fire.app.core.theme.compose

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.graphics.Color

@Composable
fun FireTheme(
    preference: FireAppearancePreference = FireAppearancePreference.System,
    content: @Composable () -> Unit,
) {
    val systemDark = isSystemInDarkTheme()
    val isDark = when (preference) {
        FireAppearancePreference.System -> systemDark
        FireAppearancePreference.Light -> false
        FireAppearancePreference.Dark -> true
    }

    val extended = if (isDark) darkFireExtendedColors else lightFireExtendedColors
    val t = FireColorTokens

    val colorScheme = if (isDark) {
        darkColorScheme(
            primary = t.darkAccent,
            onPrimary = Color.White,
            primaryContainer = t.darkAccentSoft,
            onPrimaryContainer = Color.White,
            secondary = t.darkAccentSoft,
            onSecondary = Color.White,
            secondaryContainer = t.darkSurfaceSecondary,
            onSecondaryContainer = t.darkInk,
            tertiary = t.darkAccentGlow,
            onTertiary = Color.White,
            background = t.darkCanvasMid,
            onBackground = t.darkInk,
            surface = t.darkSurface,
            onSurface = t.darkInk,
            surfaceVariant = t.darkSurfaceSecondary,
            onSurfaceVariant = t.darkSubtleInk,
            surfaceTint = t.darkAccent,
            inverseSurface = t.darkInverseInk,
            inverseOnSurface = t.darkInverseSubtleInk,
            error = t.darkError,
            onError = Color.White,
            errorContainer = t.darkError,
            onErrorContainer = Color.White,
            outline = t.darkTertiaryInk,
            outlineVariant = t.darkDivider,
            scrim = Color.Black,
        )
    } else {
        lightColorScheme(
            primary = t.lightAccent,
            onPrimary = Color.White,
            primaryContainer = t.lightAccentSoft,
            onPrimaryContainer = Color.White,
            secondary = t.lightAccentSoft,
            onSecondary = Color.White,
            secondaryContainer = t.lightSurfaceSecondary,
            onSecondaryContainer = t.lightInk,
            tertiary = t.lightAccentGlow,
            onTertiary = Color.White,
            background = t.lightCanvasMid,
            onBackground = t.lightInk,
            surface = t.lightSurface,
            onSurface = t.lightInk,
            surfaceVariant = t.lightSurfaceSecondary,
            onSurfaceVariant = t.lightSubtleInk,
            surfaceTint = t.lightAccent,
            inverseSurface = t.lightInverseInk,
            inverseOnSurface = t.lightInverseSubtleInk,
            error = t.lightError,
            onError = Color.White,
            errorContainer = t.lightError,
            onErrorContainer = Color.White,
            outline = t.lightTertiaryInk,
            outlineVariant = t.lightDivider,
            scrim = Color.Black,
        )
    }

    CompositionLocalProvider(LocalFireExtendedColors provides extended) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = FireTypography,
            content = content,
        )
    }
}

val MaterialTheme.fireExtended: FireExtendedColors
    @Composable
    @ReadOnlyComposable
    get() = LocalFireExtendedColors.current
