package com.fire.app.richtext

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.*
import android.util.LruCache
import com.fire.app.R
import com.fire.app.core.ext.dp
import com.fire.app.richtext.span.FireCodeBlockSpan
import com.fire.app.richtext.span.FireLinkSpan
import com.fire.app.richtext.span.FireQuoteSpan
import com.fire.app.richtext.span.FireSpoilerSpan

object FireSpannableBuilder {

    private val heightCache = LruCache<String, Int>(128)

    data class RenderContext(
        val baseTextSize: Float = 15f,
        val textColor: Int = Color.BLACK,
        val accentColor: Int = Color.BLUE,
        val codeBackgroundColor: Int = Color.LTGRAY,
        val quoteStripeColor: Int = Color.GRAY,
        val quoteBackgroundColor: Int = 0xFFF6F8FA.toInt(),
        val linkColor: Int = Color.BLUE,
        val isBold: Boolean = false,
        val isItalic: Boolean = false,
        val isStrikethrough: Boolean = false,
        val indentLevel: Int = 0,
    ) {
        fun withBold() = copy(isBold = true)
        fun withItalic() = copy(isItalic = true)
        fun withStrikethrough() = copy(isStrikethrough = true)
        fun indented() = copy(indentLevel = indentLevel + 1)

        val currentTypeface: Int
            get() = when {
                isBold && isItalic -> Typeface.BOLD_ITALIC
                isBold -> Typeface.BOLD
                isItalic -> Typeface.ITALIC
                else -> Typeface.NORMAL
            }
    }

    fun build(
        nodes: List<FireRichTextNode>,
        context: Context,
        onLinkClicked: ((String) -> Unit)? = null,
    ): SpannableStringBuilder {
        val accent = context.getColor(R.color.fire_accent)
        val textPrimary = context.getColor(R.color.fire_text_primary)
        val codeBg = context.getColor(R.color.fire_code_background)
        val quoteStripe = context.getColor(R.color.fire_quote_stripe)
        val linkColor = context.getColor(R.color.fire_link)

        val renderContext = RenderContext(
            textColor = textPrimary,
            accentColor = accent,
            codeBackgroundColor = codeBg,
            quoteStripeColor = quoteStripe,
            quoteBackgroundColor = codeBg,
            linkColor = linkColor,
        )

        val builder = SpannableStringBuilder()
        appendNodes(nodes, builder, renderContext, context, onLinkClicked)
        return builder
    }

    private fun appendNodes(
        nodes: List<FireRichTextNode>,
        builder: SpannableStringBuilder,
        context: RenderContext,
        ctx: Context,
        onLinkClicked: ((String) -> Unit)?,
    ) {
        for (node in nodes) {
            when (node) {
                is FireRichTextNode.Text -> appendStyledText(builder, node.value, context)

                is FireRichTextNode.Bold -> appendNodes(node.children, builder, context.withBold(), ctx, onLinkClicked)

                is FireRichTextNode.Italic -> appendNodes(node.children, builder, context.withItalic(), ctx, onLinkClicked)

                is FireRichTextNode.Strikethrough -> appendNodes(node.children, builder, context.withStrikethrough(), ctx, onLinkClicked)

                is FireRichTextNode.Code -> {
                    val start = builder.length
                    builder.append(node.value)
                    val end = builder.length
                    builder.setSpan(TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(BackgroundColorSpan(context.codeBackgroundColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.CodeBlock -> {
                    ensureBlockBoundary(builder)
                    val start = builder.length
                    builder.append(node.code.trim('\n'))
                    val end = builder.length
                    builder.setSpan(TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(BackgroundColorSpan(context.codeBackgroundColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(LeadingMarginSpan.Standard(12), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    ensureBlockBoundary(builder)
                }

                is FireRichTextNode.Link -> {
                    val linkBuilder = SpannableStringBuilder()
                    appendNodes(node.children, linkBuilder, context, ctx, onLinkClicked)
                    val start = builder.length
                    builder.append(linkBuilder)
                    val end = builder.length
                    builder.setSpan(FireLinkSpan(node.url, onLinkClicked), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(ForegroundColorSpan(context.linkColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Mention -> {
                    val start = builder.length
                    builder.append("@${node.username}")
                    val end = builder.length
                    builder.setSpan(FireLinkSpan("fire://profile/${node.username}", onLinkClicked), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(ForegroundColorSpan(context.accentColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.MentionGroup -> {
                    val start = builder.length
                    builder.append("@${node.name}")
                    val end = builder.length
                    builder.setSpan(FireLinkSpan(node.url, onLinkClicked), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(ForegroundColorSpan(context.accentColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Hashtag -> {
                    val start = builder.length
                    builder.append("#${node.text}")
                    val end = builder.length
                    builder.setSpan(FireLinkSpan(node.url, onLinkClicked), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(ForegroundColorSpan(context.accentColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Emoji -> {
                    // Emoji handled by FireEmojiImageSpan in FireRichTextView
                    val start = builder.length
                    builder.append("￼") // object replacement character
                    val end = builder.length
                    builder.setSpan(FireEmojiPlaceholderSpan(node.url, node.fallbackText, node.onlyEmoji), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Heading -> {
                    ensureBlockBoundary(builder)
                    val sizeMultiplier = when {
                        node.level <= 1 -> 1.4f
                        node.level == 2 -> 1.27f
                        node.level == 3 -> 1.13f
                        else -> 1.07f
                    }
                    val start = builder.length
                    appendNodes(node.children, builder, context.withBold(), ctx, onLinkClicked)
                    val end = builder.length
                    builder.setSpan(RelativeSizeSpan(sizeMultiplier), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    ensureBlockBoundary(builder)
                }

                is FireRichTextNode.Blockquote -> appendQuoteBlock(builder, null, null, null, node.children, context, ctx, onLinkClicked)

                is FireRichTextNode.Quote -> appendQuoteBlock(builder, node.author, node.postNumber, node.topicId, node.children, context, ctx, onLinkClicked)

                is FireRichTextNode.Onebox -> {
                    ensureBlockBoundary(builder)
                    appendOnebox(builder, node, context, ctx, onLinkClicked)
                    ensureBlockBoundary(builder)
                }

                is FireRichTextNode.ListNode -> {
                    ensureBlockBoundary(builder)
                    for ((index, item) in node.items.withIndex()) {
                        if (index > 0) builder.append('\n')
                        val prefix = if (node.ordered) "${index + 1}. " else "  • "
                        builder.append(prefix)
                        appendNodes(item, builder, context, ctx, onLinkClicked)
                    }
                    ensureBlockBoundary(builder)
                }

                is FireRichTextNode.ListItem -> {
                    builder.append(" • ")
                    appendNodes(node.children, builder, context, ctx, onLinkClicked)
                }

                is FireRichTextNode.Spoiler -> {
                    val start = builder.length
                    appendNodes(node.children, builder, context, ctx, onLinkClicked)
                    val end = builder.length
                    builder.setSpan(FireSpoilerSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Details -> {
                    ensureBlockBoundary(builder)
                    builder.append("▾ ")
                    appendNodes(node.summary, builder, context.withBold(), ctx, onLinkClicked)
                    if (node.children.isNotEmpty()) {
                        builder.append('\n')
                        appendNodes(node.children, builder, context.indented(), ctx, onLinkClicked)
                    }
                    ensureBlockBoundary(builder)
                }

                is FireRichTextNode.Table -> {
                    ensureBlockBoundary(builder)
                    val start = builder.length
                    builder.append(node.text)
                    val end = builder.length
                    builder.setSpan(TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(BackgroundColorSpan(context.codeBackgroundColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.append('\n')
                }

                is FireRichTextNode.Video -> {
                    val display = node.title?.ifBlank { null } ?: node.url
                    val start = builder.length
                    builder.append(display)
                    val end = builder.length
                    builder.setSpan(FireLinkSpan(node.url, onLinkClicked), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.setSpan(ForegroundColorSpan(context.linkColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }

                is FireRichTextNode.Divider -> {
                    ensureBlockBoundary(builder)
                    val start = builder.length
                    builder.append("──────────")
                    val end = builder.length
                    builder.setSpan(ForegroundColorSpan(0xFF6B7280.toInt()), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    builder.append('\n')
                }

                is FireRichTextNode.LineBreak -> builder.append('\n')

                is FireRichTextNode.Paragraph -> {
                    ensureBlockBoundary(builder)
                    appendNodes(node.children, builder, context, ctx, onLinkClicked)
                }

                is FireRichTextNode.Image -> { /* Handled by the topic-detail block renderer. */ }
            }
        }
    }

    private fun appendStyledText(
        builder: SpannableStringBuilder,
        text: String,
        context: RenderContext,
    ) {
        val normalized = text.replace(" ", " ").trim()
        if (normalized.isBlank()) return

        if (shouldInsertInlineSeparator(builder, normalized)) {
            builder.append(' ')
        }

        val start = builder.length
        builder.append(normalized)
        val end = builder.length

        if (context.isBold) builder.setSpan(StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (context.isItalic) builder.setSpan(StyleSpan(Typeface.ITALIC), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        if (context.isStrikethrough) builder.setSpan(StrikethroughSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(ForegroundColorSpan(context.textColor), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
    }

    private fun appendQuoteBlock(
        builder: SpannableStringBuilder,
        author: String?,
        postNumber: UInt?,
        topicId: ULong?,
        children: List<FireRichTextNode>,
        context: RenderContext,
        ctx: Context,
        onLinkClicked: ((String) -> Unit)?,
    ) {
        ensureBlockBoundary(builder)
        val quoteStart = builder.length
        val trimmedAuthor = author?.trim()?.ifBlank { null }
        if (trimmedAuthor != null || postNumber != null) {
            val headerStart = builder.length
            val labelStart = builder.length
            builder.append("引用") // 引用
            val labelEnd = builder.length
            builder.setSpan(ForegroundColorSpan(0xFF6B7280.toInt()), labelStart, labelEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (trimmedAuthor != null) {
                val separatorStart = builder.length
                builder.append(' ')
                builder.setSpan(ForegroundColorSpan(0xFF6B7280.toInt()), separatorStart, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val authorStart = builder.length
                builder.append("@$trimmedAuthor")
                val authorEnd = builder.length
                builder.setSpan(FireLinkSpan(profileUrl(trimmedAuthor), onLinkClicked), authorStart, authorEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                builder.setSpan(ForegroundColorSpan(context.accentColor), authorStart, authorEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            if (postNumber != null) {
                val separatorStart = builder.length
                builder.append(" · ")
                builder.setSpan(ForegroundColorSpan(0xFF6B7280.toInt()), separatorStart, builder.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val postStart = builder.length
                builder.append("#$postNumber")
                val postEnd = builder.length
                if (topicId != null) {
                    builder.setSpan(FireLinkSpan(topicUrl(topicId, postNumber), onLinkClicked), postStart, postEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                builder.setSpan(ForegroundColorSpan(context.accentColor), postStart, postEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            val headerEnd = builder.length
            builder.setSpan(RelativeSizeSpan(0.8f), headerStart, headerEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.append('\n')
        }
        val bodyBuilder = SpannableStringBuilder()
        appendNodes(children, bodyBuilder, context.indented().copy(textColor = 0xFF6B7280.toInt()), ctx, onLinkClicked)
        builder.append(compactQuoteText(bodyBuilder))
        val quoteEnd = builder.length
        if (quoteStart < quoteEnd) {
            builder.setSpan(
                FireQuoteSpan(
                    dp(ctx, 10),
                    context.quoteBackgroundColor,
                    context.quoteStripeColor,
                ),
                quoteStart,
                quoteEnd,
                Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
            )
        }
        ensureBlockBoundary(builder)
    }

    private fun compactQuoteText(value: Spanned): SpannableStringBuilder {
        val ranges = nonBlankLineRanges(value)
        val compact = SpannableStringBuilder()
        val selectedRanges = if (ranges.isNotEmpty()) {
            ranges.take(QUOTE_PREVIEW_LINE_LIMIT)
        } else {
            listOfNotNull(trimmedRange(value))
        }

        selectedRanges.forEachIndexed { index, range ->
            if (index > 0) compact.append('\n')
            compact.append(value, range.start, range.end)
        }

        return truncateQuoteText(compact)
    }

    private fun nonBlankLineRanges(value: CharSequence): List<TextRange> {
        val ranges = mutableListOf<TextRange>()
        var lineStart = 0
        while (lineStart <= value.length) {
            val lineEnd = value.indexOf('\n', lineStart).let { index ->
                if (index >= 0) index else value.length
            }
            trimmedRange(value, lineStart, lineEnd)?.let { ranges += it }
            if (lineEnd >= value.length) break
            lineStart = lineEnd + 1
        }
        return ranges
    }

    private fun trimmedRange(value: CharSequence): TextRange? =
        trimmedRange(value, 0, value.length)

    private fun trimmedRange(value: CharSequence, start: Int, end: Int): TextRange? {
        var trimmedStart = start
        var trimmedEnd = end
        while (trimmedStart < trimmedEnd && value[trimmedStart].isWhitespace()) {
            trimmedStart += 1
        }
        while (trimmedEnd > trimmedStart && value[trimmedEnd - 1].isWhitespace()) {
            trimmedEnd -= 1
        }
        return if (trimmedStart < trimmedEnd) TextRange(trimmedStart, trimmedEnd) else null
    }

    private fun truncateQuoteText(value: SpannableStringBuilder): SpannableStringBuilder {
        if (value.length <= MAX_QUOTE_PREVIEW_LENGTH) return value
        val truncated = SpannableStringBuilder(
            value.subSequence(0, MAX_QUOTE_PREVIEW_LENGTH - QUOTE_ELLIPSIS.length),
        )
        while (truncated.isNotEmpty() && truncated[truncated.length - 1].isWhitespace()) {
            truncated.delete(truncated.length - 1, truncated.length)
        }
        truncated.append(QUOTE_ELLIPSIS)
        return truncated
    }

    private fun appendOnebox(
        builder: SpannableStringBuilder,
        node: FireRichTextNode.Onebox,
        context: RenderContext,
        ctx: Context,
        onLinkClicked: ((String) -> Unit)?,
    ) {
        val captionStart = builder.length
        builder.append("链接预览") // 链接预览
        val captionEnd = builder.length
        builder.setSpan(ForegroundColorSpan(0xFF0369A1.toInt()), captionStart, captionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(RelativeSizeSpan(0.73f), captionStart, captionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        builder.setSpan(StyleSpan(Typeface.BOLD), captionStart, captionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)

        val title = node.title?.trim()?.ifBlank { null }
        val description = node.description?.trim()?.ifBlank { null }
        val url = node.url
        if (title != null) {
            builder.append('\n')
            val titleStart = builder.length
            builder.append(title)
            val titleEnd = builder.length
            builder.setSpan(ForegroundColorSpan(context.accentColor), titleStart, titleEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(StyleSpan(Typeface.BOLD), titleStart, titleEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            if (url != null) {
                builder.setSpan(FireLinkSpan(url, onLinkClicked), titleStart, titleEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }
        if (description != null) {
            builder.append('\n')
            val descriptionStart = builder.length
            builder.append(description)
            val descriptionEnd = builder.length
            builder.setSpan(ForegroundColorSpan(0xFF6B7280.toInt()), descriptionStart, descriptionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(RelativeSizeSpan(0.9f), descriptionStart, descriptionEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        } else if (url != null && title == null) {
            builder.append('\n')
            val linkStart = builder.length
            builder.append(url)
            val linkEnd = builder.length
            builder.setSpan(FireLinkSpan(url, onLinkClicked), linkStart, linkEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(ForegroundColorSpan(context.accentColor), linkStart, linkEnd, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun ensureBlockBoundary(builder: SpannableStringBuilder) {
        trimTrailingSpaces(builder)
        if (builder.isEmpty()) return
        val trailingNewlines = builder.reversed().takeWhile { it == '\n' }.count()
        for (i in trailingNewlines until 2) {
            builder.append('\n')
        }
    }

    private fun trimTrailingSpaces(builder: SpannableStringBuilder) {
        while (builder.isNotEmpty() && (builder.last() == ' ' || builder.last() == '\t')) {
            builder.delete(builder.length - 1, builder.length)
        }
    }

    private fun shouldInsertInlineSeparator(builder: SpannableStringBuilder, nextText: String): Boolean {
        val previous = builder.lastOrNull() ?: return false
        if (previous.isWhitespace()) return false
        val next = nextText.firstOrNull() ?: return false
        if (next.isWhitespace() || isClosingPunctuation(next)) return false
        if (isCJK(previous) && isCJK(next)) return false
        return isWordBoundary(previous) && isWordBoundary(next)
    }

    private fun isWordBoundary(c: Char): Boolean =
        c.isLetterOrDigit() || c in "@#_)]}"

    private fun isClosingPunctuation(c: Char): Boolean =
        c in ".,!?:;)]}%。，！？：；、"

    private fun isCJK(c: Char): Boolean {
        val block = Character.UnicodeBlock.of(c)
        return block == Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS
            || block == Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A
            || block == Character.UnicodeBlock.HIRAGANA
            || block == Character.UnicodeBlock.KATAKANA
            || block == Character.UnicodeBlock.HANGUL_SYLLABLES
    }

    private fun dp(context: Context, value: Int): Int = context.dp(value)

    private fun profileUrl(username: String): String = "fire://profile/${Uri.encode(username)}"

    private fun topicUrl(topicId: ULong, postNumber: UInt): String = "fire://topic/$topicId/$postNumber"

    private data class TextRange(val start: Int, val end: Int)

    private const val QUOTE_PREVIEW_LINE_LIMIT = 2
    private const val MAX_QUOTE_PREVIEW_LENGTH = 120
    private const val QUOTE_ELLIPSIS = "..."

    // Emoji placeholder span — replaced with ImageSpan by FireRichTextView
    class FireEmojiPlaceholderSpan(
        val url: String,
        val fallbackText: String,
        val onlyEmoji: Boolean,
    ) : ReplacementSpan() {
        override fun getSize(paint: android.graphics.Paint, text: CharSequence, start: Int, end: Int, fm: android.graphics.Paint.FontMetricsInt?): Int {
            val size = if (onlyEmoji) (paint.textSize * 1.9f).toInt() else (paint.textSize * 1.15f).toInt()
            fm?.let {
                it.ascent = -size
                it.descent = 0
                it.top = it.ascent
                it.bottom = it.descent
            }
            return size
        }

        override fun draw(canvas: android.graphics.Canvas, text: CharSequence, start: Int, end: Int, x: Float, top: Int, baseline: Int, bottom: Int, paint: android.graphics.Paint) {
            // Placeholder — no draw; FireRichTextView will replace with actual image
        }
    }
}
