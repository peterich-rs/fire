package com.fire.app.core.ext

import androidx.recyclerview.widget.RecyclerView

fun RecyclerView.optimizeForPaging() {
    setItemViewCacheSize(20)
    (itemAnimator as? RecyclerView.SimpleItemAnimator)?.supportsChangeAnimations = false
}
