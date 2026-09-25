package com.fire.app.core.ui

import android.view.View
import androidx.annotation.StringRes
import com.fire.app.R
import com.google.android.material.snackbar.Snackbar

object FireToast {
    enum class Style {
        SUCCESS,
        ERROR,
        INFO,
        WARNING,
    }

    fun show(anchor: View, message: String, style: Style = Style.INFO) {
        Snackbar.make(anchor, message, Snackbar.LENGTH_SHORT)
            .setBackgroundTint(anchor.context.getColor(backgroundColor(style)))
            .setTextColor(anchor.context.getColor(android.R.color.white))
            .show()
    }

    fun show(anchor: View, @StringRes messageRes: Int, style: Style = Style.INFO) {
        show(anchor, anchor.context.getString(messageRes), style)
    }

    private fun backgroundColor(style: Style): Int {
        return when (style) {
            Style.SUCCESS -> R.color.fire_success
            Style.ERROR -> R.color.fire_error
            Style.INFO -> R.color.fire_accent
            Style.WARNING -> R.color.fire_warning
        }
    }
}
