package com.fire.app.core.theme

import android.content.Context
import android.graphics.Color
import android.os.Build
import androidx.annotation.AttrRes
import androidx.annotation.ColorInt
import androidx.annotation.ColorRes
import androidx.core.content.ContextCompat
import com.fire.app.FireApplication
import com.google.android.material.color.MaterialColors

object FireColors {
    private var dynamicColorsEnabled = false
    private var oledMode = false

    fun setDynamicColorsEnabled(enabled: Boolean) {
        dynamicColorsEnabled = enabled
    }

    fun loadOledMode(context: Context): Boolean {
        return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_OLED_MODE, false)
    }

    fun setOledMode(enabled: Boolean) {
        oledMode = enabled
    }

    fun setOledMode(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_OLED_MODE, enabled)
            .apply()
        oledMode = enabled
    }

    fun isOledMode(): Boolean = oledMode

    @ColorInt fun accent() = resolveDynamicColor(com.google.android.material.R.attr.colorPrimary, com.fire.app.R.color.fire_accent)
    @ColorInt fun accentSoft() = resolveDynamicColor(com.google.android.material.R.attr.colorSecondaryContainer, com.fire.app.R.color.fire_accent_soft)
    @ColorInt fun textPrimary() = resolveColor(com.fire.app.R.color.fire_text_primary)
    @ColorInt fun textSecondary() = resolveColor(com.fire.app.R.color.fire_text_secondary)
    @ColorInt fun textTertiary() = resolveColor(com.fire.app.R.color.fire_text_tertiary)
    @ColorInt fun backgroundCanvas() = if (oledMode) Color.BLACK else resolveColor(com.fire.app.R.color.fire_background_canvas)
    @ColorInt fun backgroundSurface() = if (oledMode) Color.rgb(10, 10, 11) else resolveColor(com.fire.app.R.color.fire_background_surface)
    @ColorInt fun backgroundElevated() = if (oledMode) Color.rgb(17, 17, 19) else resolveColor(com.fire.app.R.color.fire_background_elevated)
    @ColorInt fun codeBackground() = resolveColor(com.fire.app.R.color.fire_code_background)
    @ColorInt fun quoteStripe() = resolveColor(com.fire.app.R.color.fire_quote_stripe)
    @ColorInt fun divider() = resolveColor(com.fire.app.R.color.fire_divider)
    @ColorInt fun success() = resolveColor(com.fire.app.R.color.fire_success)
    @ColorInt fun warning() = resolveColor(com.fire.app.R.color.fire_warning)
    @ColorInt fun error() = resolveColor(com.fire.app.R.color.fire_error)

    @ColorInt
    private fun resolveColor(@ColorRes resId: Int): Int {
        return ContextCompat.getColor(FireApplication.getInstance(), resId)
    }

    @ColorInt
    private fun resolveDynamicColor(@AttrRes attr: Int, @ColorRes fallbackResId: Int): Int {
        val context = FireApplication.themedContext()
        val fallback = ContextCompat.getColor(context, fallbackResId)
        if (!dynamicColorsEnabled || Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return fallback
        }
        return MaterialColors.getColor(context, attr, fallback)
    }

    private const val PREFS_NAME = "fire.appearance"
    private const val KEY_OLED_MODE = "oled_mode"
}
