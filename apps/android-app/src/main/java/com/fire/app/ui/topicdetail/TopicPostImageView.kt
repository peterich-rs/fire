package com.fire.app.ui.topicdetail

import android.content.Context
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import coil.request.ImageRequest
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireImageLoader
import com.fire.app.core.image.FireImageUrls
import com.fire.app.richtext.FireCookedImage

class TopicPostImageView(context: Context) : FrameLayout(context) {

    private val imageView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        adjustViewBounds = false
        setBackgroundColor(context.getColor(R.color.fire_background_surface))
    }
    private val progress = ProgressBar(context).apply {
        isIndeterminate = true
    }
    private val statusText = TextView(context).apply {
        gravity = Gravity.CENTER
        textAlignment = TEXT_ALIGNMENT_CENTER
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        setTextColor(context.getColor(R.color.fire_text_secondary))
        setPadding(context.dp(12), context.dp(8), context.dp(12), context.dp(8))
        visibility = View.GONE
    }
    private val retryButton = TextView(context).apply {
        gravity = Gravity.CENTER
        textAlignment = TEXT_ALIGNMENT_CENTER
        setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Caption)
        setTextColor(context.getColor(R.color.fire_accent))
        setPadding(context.dp(16), context.dp(8), context.dp(16), context.dp(8))
        visibility = View.GONE
    }

    private var image: FireCookedImage? = null
    private var onImageClick: ((FireCookedImage) -> Unit)? = null
    private var loaded = false

    init {
        clipToOutline = true
        setBackgroundColor(context.getColor(R.color.fire_background_surface))
        addView(
            imageView,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT),
        )
        addView(
            progress,
            LayoutParams(context.dp(32), context.dp(32), Gravity.CENTER),
        )
        addView(
            statusText,
            LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER),
        )
        addView(
            retryButton,
            LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER or Gravity.BOTTOM).apply {
                bottomMargin = context.dp(12)
            },
        )
        retryButton.setOnClickListener { loadImage() }
        setOnClickListener {
            val boundImage = image ?: return@setOnClickListener
            onImageClick?.invoke(boundImage)
        }
    }

    fun bind(
        image: FireCookedImage,
        onImageClick: (FireCookedImage) -> Unit,
    ) {
        this.image = image.normalizedUrl()
        this.onImageClick = onImageClick
        contentDescription = image.altText ?: context.getString(R.string.topic_detail_image_attachment)
        imageView.contentDescription = contentDescription
        retryButton.text = context.getString(R.string.topic_detail_image_retry)
        loadImage()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val desiredHeight = desiredImageHeight(width)
        val exactHeightSpec = MeasureSpec.makeMeasureSpec(desiredHeight, MeasureSpec.EXACTLY)
        super.onMeasure(widthMeasureSpec, exactHeightSpec)
    }

    private fun loadImage() {
        val boundImage = image ?: return
        loaded = false
        showLoading()
        FireImageLoader.load(boundImage.url, imageView) {
            listener(
                onStart = { showLoading() },
                onSuccess = { _: ImageRequest, _ ->
                    loaded = true
                    showLoaded()
                },
                onError = { _: ImageRequest, _ ->
                    loaded = false
                    showError()
                },
            )
        }
    }

    private fun showLoading() {
        progress.visibility = View.VISIBLE
        statusText.visibility = View.VISIBLE
        statusText.text = context.getString(R.string.topic_detail_image_loading)
        retryButton.visibility = View.GONE
        imageView.alpha = 0.32f
    }

    private fun showLoaded() {
        progress.visibility = View.GONE
        statusText.visibility = View.GONE
        retryButton.visibility = View.GONE
        imageView.alpha = 1f
    }

    private fun showError() {
        progress.visibility = View.GONE
        statusText.visibility = View.VISIBLE
        statusText.text = context.getString(R.string.topic_detail_image_error)
        retryButton.visibility = View.VISIBLE
        imageView.alpha = 0.16f
    }

    private fun desiredImageHeight(widthPx: Int): Int {
        val density = resources.displayMetrics.density
        val minHeight = (96 * density).toInt()
        val maxHeight = (420 * density).toInt()
        val placeholderHeight = (132 * density).toInt()
        if (widthPx <= 0) return placeholderHeight

        val imageWidth = image?.width ?: 0f
        val imageHeight = image?.height ?: 0f
        if (imageWidth <= 0f || imageHeight <= 0f) return placeholderHeight

        return (widthPx * imageHeight / imageWidth)
            .toInt()
            .coerceIn(minHeight, maxHeight)
    }

    private fun FireCookedImage.normalizedUrl(): FireCookedImage {
        return FireImageUrls.build(url)?.let { copy(url = it) } ?: this
    }
}
