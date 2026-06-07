package com.fire.app.ui.topicdetail

import android.app.Dialog
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.fragment.app.DialogFragment
import coil.load
import coil.request.CachePolicy
import coil.request.ImageRequest
import coil.size.Size
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.core.image.FireImageLoader
import com.fire.app.richtext.FireCookedImage
import com.github.panpf.zoomimage.CoilZoomImageView
import com.github.panpf.zoomimage.view.zoom.OnViewTapListener

class TopicImagePreviewDialogFragment : DialogFragment() {

    private lateinit var imageView: CoilZoomImageView
    private lateinit var progress: ProgressBar
    private lateinit var statusText: TextView
    private lateinit var retryButton: TextView

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        return Dialog(requireContext(), android.R.style.Theme_Black_NoTitleBar_Fullscreen)
    }

    override fun onCreateView(
        inflater: android.view.LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        val context = requireContext()
        val url = requireArguments().getString(ARG_URL).orEmpty()
        val altText = requireArguments().getString(ARG_ALT)

        imageView = CoilZoomImageView(context).apply {
            contentDescription = altText ?: getString(R.string.topic_detail_image_attachment)
            setBackgroundColor(Color.BLACK)
            scaleType = android.widget.ImageView.ScaleType.FIT_CENTER
            onViewTapListener = OnViewTapListener { _, _ -> dismissAllowingStateLoss() }
        }
        progress = ProgressBar(context).apply {
            isIndeterminate = true
        }
        statusText = TextView(context).apply {
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(Color.WHITE)
            setPadding(context.dp(24), context.dp(12), context.dp(24), context.dp(12))
            visibility = View.GONE
        }
        retryButton = TextView(context).apply {
            text = getString(R.string.topic_detail_image_retry)
            gravity = Gravity.CENTER
            textAlignment = View.TEXT_ALIGNMENT_CENTER
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(Color.WHITE)
            setPadding(context.dp(24), context.dp(12), context.dp(24), context.dp(12))
            visibility = View.GONE
            setOnClickListener { loadPreview(url) }
        }

        val closeButton = TextView(context).apply {
            text = getString(R.string.action_close)
            setTextAppearance(androidx.appcompat.R.style.TextAppearance_AppCompat_Body1)
            setTextColor(Color.WHITE)
            setPadding(context.dp(20), context.dp(20), context.dp(20), context.dp(20))
            setOnClickListener { dismissAllowingStateLoss() }
        }

        return FrameLayout(context).apply {
            setBackgroundColor(Color.BLACK)
            addView(
                imageView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            addView(
                progress,
                FrameLayout.LayoutParams(context.dp(44), context.dp(44), Gravity.CENTER),
            )
            addView(
                statusText,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
            addView(
                retryButton,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER or Gravity.BOTTOM,
                ).apply {
                    bottomMargin = context.dp(72)
                },
            )
            addView(
                closeButton,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.TOP or Gravity.END,
                ),
            )
        }
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        loadPreview(requireArguments().getString(ARG_URL).orEmpty())
    }

    override fun onStart() {
        super.onStart()
        dialog?.window?.let { window ->
            window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            window.setBackgroundDrawable(ColorDrawable(Color.BLACK))
        }
    }

    private fun loadPreview(url: String) {
        if (url.isBlank()) {
            showError()
            return
        }
        showLoading()
        imageView.load(url, FireImageLoader.loader()) {
            allowHardware(false)
            crossfade(false)
            diskCacheKey(url)
            memoryCachePolicy(CachePolicy.ENABLED)
            diskCachePolicy(CachePolicy.ENABLED)
            networkCachePolicy(CachePolicy.ENABLED)
            size(Size.ORIGINAL)
            listener(
                onStart = { showLoading() },
                onSuccess = { _: ImageRequest, _ -> showLoaded() },
                onError = { _: ImageRequest, _ -> showError() },
            )
        }
    }

    private fun showLoading() {
        progress.visibility = View.VISIBLE
        statusText.visibility = View.VISIBLE
        statusText.text = getString(R.string.topic_detail_image_loading)
        retryButton.visibility = View.GONE
        imageView.alpha = 0.42f
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
        statusText.text = getString(R.string.topic_detail_image_error)
        retryButton.visibility = View.VISIBLE
        imageView.alpha = 0.28f
    }

    companion object {
        private const val ARG_URL = "url"
        private const val ARG_ALT = "alt"

        fun newInstance(image: FireCookedImage): TopicImagePreviewDialogFragment {
            return TopicImagePreviewDialogFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_URL, image.url)
                    putString(ARG_ALT, image.altText)
                }
            }
        }
    }
}
