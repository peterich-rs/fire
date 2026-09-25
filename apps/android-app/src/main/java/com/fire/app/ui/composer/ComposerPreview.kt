package com.fire.app.ui.composer

import android.content.Context
import android.graphics.Typeface
import android.text.TextUtils
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.text.HtmlCompat
import com.fire.app.R
import com.fire.app.core.image.FireImageLoader
import com.fire.app.session.FireSessionStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

data class ComposerPreviewContent(
    val title: String? = null,
    val recipients: List<String> = emptyList(),
    val categoryName: String? = null,
    val tags: List<String> = emptyList(),
    val body: String,
    val baseUrl: String,
)

class ComposerPreviewRenderer(
    private val container: LinearLayout,
    private val sessionStore: FireSessionStore,
    private val scope: CoroutineScope,
) {
    private val resolvedUploads = mutableMapOf<String, String>()
    private val failedUploadLookups = mutableSetOf<String>()
    private var resolveJob: Job? = null
    private var lastContent: ComposerPreviewContent? = null

    fun render(content: ComposerPreviewContent) {
        lastContent = content
        val context = container.context
        val images = extractMarkdownImages(content.body)
        resolveMissingUploads(images)

        container.removeAllViews()
        content.title?.let { title ->
            container.addView(previewText(context, title, bold = true, textSizeSp = 20f))
        }
        if (content.recipients.isNotEmpty()) {
            container.addView(
                previewMetaText(
                    context,
                    content.recipients.joinToString("  ") { "@$it" },
                ),
            )
        }
        content.categoryName?.takeIf { it.isNotBlank() }?.let { category ->
            container.addView(previewMetaText(context, category))
        }
        if (content.tags.isNotEmpty()) {
            container.addView(previewMetaText(context, content.tags.joinToString("  ") { "#$it" }))
        }

        val bodyWithoutImages = markdownImagePattern.replace(content.body, "").trim()
        val bodyText = if (bodyWithoutImages.isBlank()) {
            context.getString(R.string.composer_preview_empty)
        } else {
            bodyWithoutImages
        }
        container.addView(
            previewText(context, "", topMarginDp = 8).apply {
                text = if (bodyWithoutImages.isBlank()) {
                    bodyText
                } else {
                    markdownToPreviewSpanned(bodyText)
                }
                setTextColor(context.getColor(R.color.fire_text_primary))
            },
        )

        if (images.isNotEmpty()) {
            container.addView(
                previewText(
                    context,
                    context.getString(R.string.composer_preview_images),
                    bold = true,
                    topMarginDp = 14,
                ),
            )
            images.forEach { image ->
                val resolvedUrl = resolvedUrl(image.urlString, content.baseUrl)
                if (resolvedUrl == null) {
                    container.addView(
                        previewFallback(
                            context,
                            context.getString(
                                R.string.composer_preview_image_pending,
                                image.altText ?: image.urlString,
                            ),
                        ),
                    )
                } else {
                    val imageView = ImageView(context).apply {
                        adjustViewBounds = true
                        maxHeight = context.dp(360)
                        scaleType = ImageView.ScaleType.FIT_CENTER
                        setBackgroundColor(context.getColor(R.color.fire_code_background))
                    }
                    container.addView(
                        imageView,
                        LinearLayout.LayoutParams(
                            LinearLayout.LayoutParams.MATCH_PARENT,
                            LinearLayout.LayoutParams.WRAP_CONTENT,
                        ).apply {
                            topMargin = context.dp(10)
                        },
                    )
                    FireImageLoader.load(resolvedUrl, imageView)
                }
            }
        }
    }

    private fun resolveMissingUploads(images: List<ComposerMarkdownImage>) {
        val missing = images.map { it.urlString }
            .filter { it.startsWith("upload://") }
            .filterNot { resolvedUploads.containsKey(it) || failedUploadLookups.contains(it) }
            .distinct()
        if (missing.isEmpty() || resolveJob?.isActive == true) {
            return
        }
        resolveJob = scope.launch {
            runCatching { sessionStore.lookupUploadUrls(missing) }
                .onSuccess { resolved ->
                    resolved.forEach { item ->
                        val url = item.url?.takeIf { it.isNotBlank() }
                        if (url != null) {
                            resolvedUploads[item.shortUrl] = url
                        }
                    }
                    val unresolved = missing.filterNot { resolvedUploads.containsKey(it) }
                    failedUploadLookups.addAll(unresolved)
                    lastContent?.let(::render)
                }
                .onFailure {
                    failedUploadLookups.addAll(missing)
                    lastContent?.let(::render)
                }
        }
    }

    private fun resolvedUrl(rawValue: String, baseUrl: String): String? {
        val resolved = if (rawValue.startsWith("upload://")) {
            resolvedUploads[rawValue] ?: return null
        } else {
            rawValue
        }.trim()
        if (resolved.isBlank()) {
            return null
        }
        return if (resolved.startsWith("/")) {
            "${baseUrl.trimEnd('/')}$resolved"
        } else {
            resolved
        }
    }
}

private fun previewText(
    context: Context,
    textValue: CharSequence,
    bold: Boolean = false,
    textSizeSp: Float? = null,
    topMarginDp: Int = 0,
): TextView {
    return TextView(context).apply {
        text = textValue
        setTextColor(context.getColor(R.color.fire_text_primary))
        textSizeSp?.let { textSize = it }
        if (bold) {
            setTypeface(typeface, Typeface.BOLD)
        }
        layoutParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ).apply {
            topMargin = context.dp(topMarginDp)
        }
    }
}

private fun previewMetaText(context: Context, value: String): TextView {
    return previewText(context, value, bold = true, topMarginDp = 6).apply {
        setTextColor(context.getColor(R.color.fire_accent))
        textSize = 12f
    }
}

private fun previewFallback(context: Context, label: String): TextView {
    return previewText(context, label, topMarginDp = 10).apply {
        setPadding(context.dp(12), context.dp(12), context.dp(12), context.dp(12))
        setTextColor(context.getColor(R.color.fire_text_secondary))
        setBackgroundColor(context.getColor(R.color.fire_code_background))
    }
}

private fun markdownToPreviewSpanned(markdown: String) =
    HtmlCompat.fromHtml(
        markdown.lines().joinToString("<br/>") { line ->
            val raw = line.trimEnd()
            when {
                raw.isBlank() -> ""
                raw.startsWith("### ") -> "<b>${inlineMarkdown(raw.drop(4))}</b>"
                raw.startsWith("## ") -> "<h3>${inlineMarkdown(raw.drop(3))}</h3>"
                raw.startsWith("# ") -> "<h2>${inlineMarkdown(raw.drop(2))}</h2>"
                raw.startsWith(">") -> "<blockquote>${inlineMarkdown(raw.drop(1).trimStart())}</blockquote>"
                raw.startsWith("- ") || raw.startsWith("* ") -> "&bull; ${inlineMarkdown(raw.drop(2))}"
                raw.matches(Regex("^\\d+\\.\\s+.*")) -> inlineMarkdown(raw)
                else -> inlineMarkdown(raw)
            }
        },
        HtmlCompat.FROM_HTML_MODE_LEGACY,
    )

private fun inlineMarkdown(raw: String): String {
    var value = TextUtils.htmlEncode(raw)
    value = value.replace(Regex("`([^`]+)`"), "<code>$1</code>")
    value = value.replace(Regex("\\*\\*([^*]+)\\*\\*"), "<b>$1</b>")
    value = value.replace(Regex("__([^_]+)__"), "<b>$1</b>")
    value = value.replace(Regex("(?<!\\*)\\*([^*\\n]+)\\*(?!\\*)"), "<i>$1</i>")
    return value
}

private fun extractMarkdownImages(text: String): List<ComposerMarkdownImage> {
    return markdownImagePattern.findAll(text).mapNotNull { match ->
        val altText = match.groupValues.getOrNull(1)
            ?.split("|")
            ?.firstOrNull()
            ?.trim()
            ?.takeIf { it.isNotBlank() }
        val urlString = match.groupValues.getOrNull(2)
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: return@mapNotNull null
        ComposerMarkdownImage(urlString = urlString, altText = altText)
    }.toList()
}

private val markdownImagePattern = Regex("!\\[([^\\]]*)\\]\\(([^)]+)\\)")

private data class ComposerMarkdownImage(
    val urlString: String,
    val altText: String?,
)

private fun Context.dp(value: Int): Int =
    (value * resources.displayMetrics.density).toInt()
