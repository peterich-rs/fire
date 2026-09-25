package com.fire.app.core.ext

import android.content.Context
import android.util.TypedValue
import androidx.annotation.AttrRes
import androidx.annotation.ColorInt
import androidx.core.content.ContextCompat

@ColorInt
fun Context.colorFromAttr(@AttrRes attr: Int): Int {
    val typedValue = TypedValue()
    theme.resolveAttribute(attr, typedValue, true)
    return ContextCompat.getColor(this, typedValue.resourceId)
}

fun Context.dp(value: Int): Int {
    return (value * resources.displayMetrics.density).toInt()
}

fun Context.sp(value: Int): Float {
    return value * resources.displayMetrics.scaledDensity
}
