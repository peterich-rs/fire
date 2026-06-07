package com.fire.app.core.image

import android.content.Context
import android.widget.ImageView
import coil.load
import coil.disk.DiskCache
import coil.ImageLoader
import coil.memory.MemoryCache
import coil.request.CachePolicy
import coil.request.ImageRequest

object FireImageLoader {

    private lateinit var loader: ImageLoader

    fun initialize(context: Context) {
        loader = ImageLoader.Builder(context)
            .crossfade(true)
            .memoryCache {
                MemoryCache.Builder(context)
                    .maxSizePercent(0.24)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(context.cacheDir.resolve("image_cache"))
                    .maxSizePercent(0.04)
                    .build()
            }
            .allowHardware(false)
            .build()
    }

    fun load(
        url: String,
        into: ImageView,
        builder: ImageRequest.Builder.() -> Unit = {},
    ) {
        into.load(url, loader) {
            allowHardware(false)
            diskCacheKey(url)
            memoryCachePolicy(CachePolicy.ENABLED)
            diskCachePolicy(CachePolicy.ENABLED)
            networkCachePolicy(CachePolicy.ENABLED)
            builder()
        }
    }

    fun loader(): ImageLoader = loader
}
