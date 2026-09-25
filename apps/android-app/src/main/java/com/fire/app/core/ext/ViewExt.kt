package com.fire.app.core.ext

import android.view.View
import android.view.ViewGroup
import androidx.core.view.updatePadding

fun View.visible() {
    visibility = View.VISIBLE
}

fun View.invisible() {
    visibility = View.INVISIBLE
}

fun View.gone() {
    visibility = View.GONE
}

fun View.setVisible(isVisible: Boolean) {
    visibility = if (isVisible) View.VISIBLE else View.GONE
}

inline fun View.onClick(crossinline block: () -> Unit) {
    setOnClickListener { block() }
}

fun View.updatePadding(
    left: Int = paddingLeft,
    top: Int = paddingTop,
    right: Int = paddingRight,
    bottom: Int = paddingBottom,
) {
    updatePadding(left = left, top = top, right = right, bottom = bottom)
}
