package com.fire.app.core.ext

import androidx.recyclerview.widget.RecyclerView
import androidx.recyclerview.widget.SimpleItemAnimator

fun RecyclerView.optimizeForPaging() {
    setItemViewCacheSize(20)
    (itemAnimator as? SimpleItemAnimator)?.supportsChangeAnimations = false
}
