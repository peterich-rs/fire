package com.fire.app.core.theme

import androidx.annotation.ColorInt
import androidx.annotation.ColorRes
import androidx.core.content.ContextCompat
import com.fire.app.FireApplication

object FireColors {
    @ColorInt fun accent() = resolveColor(com.fire.app.R.color.fire_accent)
    @ColorInt fun accentSoft() = resolveColor(com.fire.app.R.color.fire_accent_soft)
    @ColorInt fun textPrimary() = resolveColor(com.fire.app.R.color.fire_text_primary)
    @ColorInt fun textSecondary() = resolveColor(com.fire.app.R.color.fire_text_secondary)
    @ColorInt fun textTertiary() = resolveColor(com.fire.app.R.color.fire_text_tertiary)
    @ColorInt fun backgroundCanvas() = resolveColor(com.fire.app.R.color.fire_background_canvas)
    @ColorInt fun backgroundSurface() = resolveColor(com.fire.app.R.color.fire_background_surface)
    @ColorInt fun backgroundElevated() = resolveColor(com.fire.app.R.color.fire_background_elevated)
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
}
