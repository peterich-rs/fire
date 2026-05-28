package com.fire.app.core.image

import android.content.Context
import android.widget.ImageView
import coil.ImageLoader
import coil.request.ImageRequest

object FireImageLoader {

    private lateinit var loader: ImageLoader

    fun initialize(context: Context) {
        loader = ImageLoader.Builder(context)
            .crossfade(true)
            .allowHardware(false)
            .build()
    }

    fun load(url: String, into: ImageView) {
        val request = ImageRequest.Builder(into.context)
            .data(url)
            .target(into)
            .build()
        loader.enqueue(request)
    }

    fun loader(): ImageLoader = loader
}
