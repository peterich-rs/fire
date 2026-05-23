package com.fire.app

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.TextPaint
import android.text.method.LinkMovementMethod
import android.text.style.ClickableSpan
import android.text.style.StyleSpan
import android.text.style.UnderlineSpan
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import uniffi.fire_uniffi.CookedHtmlDocumentState
import uniffi.fire_uniffi.CookedHtmlNodeKindState
import uniffi.fire_uniffi.CookedHtmlNodeState
import uniffi.fire_uniffi.parseCookedHtml

object FireCookedHtmlRenderer {
    fun render(
        context: Context,
        rawHtml: String,
        baseUrl: String = "https://linux.do",
    ): LinearLayout {
        val document = parseCookedHtml(rawHtml = rawHtml)
        val tree = CookedTree(document.nodes)
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(context, 8), 0, 0)
            val root = tree.root ?: return@apply
            val blockChildren = tree.childrenOf(root)
            if (blockChildren.isEmpty()) {
                addFallbackText(context, document)
            } else {
                blockChildren.forEach { node ->
                    renderBlock(
                        context = context,
                        target = this,
                        node = node,
                        tree = tree,
                        baseUrl = baseUrl,
                    )
                }
                if (childCount == 0) {
                    addFallbackText(context, document)
                }
            }
        }
    }

    private fun LinearLayout.addFallbackText(context: Context, document: CookedHtmlDocumentState) {
        val text = document.plainText.trim()
        if (text.isEmpty()) {
            return
        }
        addView(
            textView(context, text).apply {
                textSize = 15f
                setTextColor(Color.parseColor("#FF1F2937"))
            },
        )
    }

    private fun renderBlock(
        context: Context,
        target: LinearLayout,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
    ) {
        when (node.kind) {
            CookedHtmlNodeKindState.PARAGRAPH -> target.addView(
                paragraphView(context, inlineText(context, tree.childrenOf(node), tree, baseUrl)),
            )

            CookedHtmlNodeKindState.HEADING -> target.addView(
                headingView(context, inlineText(context, tree.childrenOf(node), tree, baseUrl), node.level),
            )

            CookedHtmlNodeKindState.BLOCKQUOTE,
            CookedHtmlNodeKindState.DISCOURSE_QUOTE -> target.addView(
                quoteView(context, node, tree, baseUrl),
            )

            CookedHtmlNodeKindState.LIST -> target.addView(
                listView(context, node, tree, baseUrl),
            )

            CookedHtmlNodeKindState.LIST_ITEM -> target.addView(
                paragraphView(context, inlineText(context, tree.childrenOf(node), tree, baseUrl)),
            )

            CookedHtmlNodeKindState.CODE_BLOCK -> target.addView(
                codeBlockView(context, subtreeText(node, tree)),
            )

            CookedHtmlNodeKindState.DETAILS -> target.addView(
                detailsView(context, node, tree, baseUrl),
            )

            CookedHtmlNodeKindState.TABLE -> target.addView(
                tableView(context, node, tree),
            )

            CookedHtmlNodeKindState.IMAGE,
            CookedHtmlNodeKindState.EMOJI -> target.addView(
                mediaLinkView(context, node, baseUrl, compact = node.kind == CookedHtmlNodeKindState.EMOJI),
            )

            CookedHtmlNodeKindState.ONEBOX,
            CookedHtmlNodeKindState.IFRAME,
            CookedHtmlNodeKindState.ATTACHMENT -> target.addView(
                linkCardView(context, node, tree, baseUrl),
            )

            CookedHtmlNodeKindState.TEXT,
            CookedHtmlNodeKindState.STRONG,
            CookedHtmlNodeKindState.EMPHASIS,
            CookedHtmlNodeKindState.STRIKETHROUGH,
            CookedHtmlNodeKindState.LINK,
            CookedHtmlNodeKindState.MENTION,
            CookedHtmlNodeKindState.HASHTAG,
            CookedHtmlNodeKindState.CODE,
            CookedHtmlNodeKindState.SPOILER,
            CookedHtmlNodeKindState.UNKNOWN -> {
                val text = inlineText(context, listOf(node), tree, baseUrl)
                if (text.isNotBlank()) {
                    target.addView(paragraphView(context, text))
                }
            }

            CookedHtmlNodeKindState.LINE_BREAK,
            CookedHtmlNodeKindState.TABLE_ROW,
            CookedHtmlNodeKindState.TABLE_CELL,
            CookedHtmlNodeKindState.DOCUMENT -> {
                tree.childrenOf(node).forEach { child ->
                    renderBlock(context, target, child, tree, baseUrl)
                }
            }
        }
    }

    private fun inlineText(
        context: Context,
        nodes: List<CookedHtmlNodeState>,
        tree: CookedTree,
        baseUrl: String,
    ): SpannableStringBuilder {
        val builder = SpannableStringBuilder()
        nodes.forEach { appendInline(context, builder, it, tree, baseUrl, InlineStyle()) }
        return builder.trimmed()
    }

    private fun appendInline(
        context: Context,
        builder: SpannableStringBuilder,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
        style: InlineStyle,
    ) {
        when (node.kind) {
            CookedHtmlNodeKindState.TEXT -> appendStyledText(builder, node.text.orEmpty(), style)
            CookedHtmlNodeKindState.LINE_BREAK -> builder.append('\n')
            CookedHtmlNodeKindState.STRONG -> appendChildren(context, builder, node, tree, baseUrl, style.copy(bold = true))
            CookedHtmlNodeKindState.EMPHASIS -> appendChildren(context, builder, node, tree, baseUrl, style.copy(italic = true))
            CookedHtmlNodeKindState.STRIKETHROUGH -> appendChildren(context, builder, node, tree, baseUrl, style.copy(strike = true))
            CookedHtmlNodeKindState.CODE -> appendStyledText(builder, subtreeText(node, tree), style.copy(code = true))
            CookedHtmlNodeKindState.LINK,
            CookedHtmlNodeKindState.MENTION,
            CookedHtmlNodeKindState.HASHTAG,
            CookedHtmlNodeKindState.ATTACHMENT -> {
                val url = node.url?.takeIf { it.isNotBlank() }
                val text = subtreeText(node, tree).ifBlank { url.orEmpty() }
                appendStyledText(builder, text, style.copy(linkUrl = resolveUrl(url, baseUrl)))
            }
            CookedHtmlNodeKindState.IMAGE,
            CookedHtmlNodeKindState.EMOJI -> {
                val label = node.alt?.takeIf { it.isNotBlank() }
                    ?: node.title?.takeIf { it.isNotBlank() }
                    ?: node.url?.takeIf { it.isNotBlank() }
                    ?: return
                appendStyledText(builder, label, style.copy(linkUrl = resolveUrl(node.url, baseUrl)))
            }
            CookedHtmlNodeKindState.SPOILER -> {
                val text = subtreeText(node, tree).ifBlank { "Spoiler" }
                appendStyledText(builder, text, style.copy(spoiler = true))
            }
            else -> appendChildren(context, builder, node, tree, baseUrl, style)
        }
    }

    private fun appendChildren(
        context: Context,
        builder: SpannableStringBuilder,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
        style: InlineStyle,
    ) {
        tree.childrenOf(node).forEach { child ->
            appendInline(context, builder, child, tree, baseUrl, style)
        }
    }

    private fun appendStyledText(
        builder: SpannableStringBuilder,
        rawText: String,
        style: InlineStyle,
    ) {
        val text = rawText.replace("\u00a0", " ").trim()
        if (text.isEmpty()) {
            return
        }
        if (shouldInsertInlineSeparator(builder, text)) {
            builder.append(' ')
        }
        val start = builder.length
        builder.append(text)
        val end = builder.length
        if (style.bold && style.italic) {
            builder.setSpan(StyleSpan(Typeface.BOLD_ITALIC), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        } else if (style.bold) {
            builder.setSpan(StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        } else if (style.italic) {
            builder.setSpan(StyleSpan(Typeface.ITALIC), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        if (style.strike || style.spoiler) {
            builder.setSpan(android.text.style.StrikethroughSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        if (style.code || style.spoiler) {
            builder.setSpan(android.text.style.TypefaceSpan("monospace"), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(android.text.style.BackgroundColorSpan(Color.parseColor("#FFEFF3F8")), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        style.linkUrl?.let { url ->
            builder.setSpan(FireLinkSpan(url), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            builder.setSpan(UnderlineSpan(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun shouldInsertInlineSeparator(builder: SpannableStringBuilder, nextText: String): Boolean {
        val previous = builder.lastOrNull() ?: return false
        if (previous.isWhitespace()) {
            return false
        }
        val next = nextText.firstOrNull() ?: return false
        if (next.isWhitespace() || isClosingPunctuation(next)) {
            return false
        }
        if (isCjk(previous) && isCjk(next)) {
            return false
        }
        return isWordBoundary(previous) && isWordBoundary(next)
    }

    private fun isWordBoundary(character: Char): Boolean =
        character.isLetterOrDigit() ||
            character == '@' ||
            character == '#' ||
            character == '_' ||
            character == ')' ||
            character == ']' ||
            character == '}'

    private fun isClosingPunctuation(character: Char): Boolean =
        character in setOf('.', ',', '!', '?', ':', ';', ')', ']', '}', '%', '。', '，', '！', '？', '：', '；', '、')

    private fun isCjk(character: Char): Boolean =
        Character.UnicodeBlock.of(character) in setOf(
            Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS,
            Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS_EXTENSION_A,
            Character.UnicodeBlock.CJK_UNIFIED_IDEOGRAPHS_EXTENSION_B,
            Character.UnicodeBlock.CJK_COMPATIBILITY_IDEOGRAPHS,
            Character.UnicodeBlock.HIRAGANA,
            Character.UnicodeBlock.KATAKANA,
            Character.UnicodeBlock.HANGUL_SYLLABLES,
        )

    private fun paragraphView(context: Context, text: CharSequence): TextView =
        textView(context, text).apply {
            textSize = 15f
            setTextColor(Color.parseColor("#FF1F2937"))
            setLineSpacing(dp(context, 2).toFloat(), 1.05f)
        }

    private fun headingView(context: Context, text: CharSequence, level: UInt?): TextView =
        textView(context, text).apply {
            textSize = if ((level ?: 2u) <= 2u) 18f else 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#FF111827"))
        }

    private fun quoteView(
        context: Context,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
    ): View {
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(context, 12), dp(context, 10), dp(context, 12), dp(context, 10))
            background = roundedBackground(context, Color.parseColor("#FFF6F8FA"), Color.parseColor("#336B7280"), 12)
            node.title?.takeIf { it.isNotBlank() }?.let { title ->
                addView(
                    textView(context, title).apply {
                        textSize = 12f
                        setTypeface(typeface, Typeface.BOLD)
                        setTextColor(Color.parseColor("#FF4B5563"))
                    },
                )
            }
            tree.childrenOf(node).forEach { child ->
                renderBlock(context, this, child, tree, baseUrl)
            }
            if (childCount == 0) {
                addView(paragraphView(context, subtreeText(node, tree)))
            }
        }
        return blockContainer(context, body)
    }

    private fun listView(
        context: Context,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
    ): View {
        val ordered = node.ordered == true
        return LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(context, 4), 0, dp(context, 4))
            tree.childrenOf(node)
                .filter { it.kind == CookedHtmlNodeKindState.LIST_ITEM }
                .forEachIndexed { index, item ->
                    addView(
                        LinearLayout(context).apply {
                            orientation = LinearLayout.HORIZONTAL
                            setPadding(0, dp(context, 3), 0, dp(context, 3))
                            addView(
                                textView(context, if (ordered) "${index + 1}." else "•").apply {
                                    textSize = 15f
                                    setTextColor(Color.parseColor("#FF6B7280"))
                                    layoutParams = LinearLayout.LayoutParams(dp(context, 28), ViewGroup.LayoutParams.WRAP_CONTENT)
                                },
                            )
                            addView(
                                paragraphView(context, inlineText(context, tree.childrenOf(item), tree, baseUrl)).apply {
                                    layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
                                },
                            )
                        },
                    )
                }
        }
    }

    private fun codeBlockView(context: Context, text: String): View {
        val code = textView(context, text.trim()).apply {
            textSize = 13f
            typeface = Typeface.MONOSPACE
            setTextColor(Color.parseColor("#FF111827"))
            setPadding(dp(context, 12), dp(context, 10), dp(context, 12), dp(context, 10))
            background = roundedBackground(context, Color.parseColor("#FFEFF3F8"), Color.parseColor("#1F6B7280"), 10)
        }
        return HorizontalScrollView(context).apply {
            addView(code)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(context, 6)
                bottomMargin = dp(context, 6)
            }
        }
    }

    private fun detailsView(
        context: Context,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
    ): View {
        val body = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(context, 12), dp(context, 10), dp(context, 12), dp(context, 10))
            background = roundedBackground(context, Color.parseColor("#FFFFFBEB"), Color.parseColor("#66F59E0B"), 12)
            addView(
                textView(context, node.title?.takeIf { it.isNotBlank() } ?: "Details").apply {
                    textSize = 13f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF92400E"))
                },
            )
            tree.childrenOf(node).forEach { child ->
                renderBlock(context, this, child, tree, baseUrl)
            }
        }
        return blockContainer(context, body)
    }

    private fun tableView(context: Context, node: CookedHtmlNodeState, tree: CookedTree): View {
        val text = tree.childrenOf(node)
            .flatMap { row ->
                tree.childrenOf(row).ifEmpty { listOf(row) }
            }
            .joinToString("\n") { cell ->
                subtreeText(cell, tree)
            }
            .trim()
        return codeBlockView(context, text)
    }

    private fun mediaLinkView(
        context: Context,
        node: CookedHtmlNodeState,
        baseUrl: String,
        compact: Boolean,
    ): View {
        val url = resolveUrl(node.url, baseUrl)
        val label = node.alt?.takeIf { it.isNotBlank() }
            ?: node.title?.takeIf { it.isNotBlank() }
            ?: url
            ?: "Image"
        return linkCard(context, label, url, if (compact) "Emoji" else "Image")
    }

    private fun linkCardView(
        context: Context,
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseUrl: String,
    ): View {
        val url = resolveUrl(node.url, baseUrl)
        val label = node.title?.takeIf { it.isNotBlank() }
            ?: subtreeText(node, tree).lineSequence().firstOrNull { it.isNotBlank() }
            ?: url
            ?: "Link"
        val kind = when (node.kind) {
            CookedHtmlNodeKindState.IFRAME -> "Embedded media"
            CookedHtmlNodeKindState.ATTACHMENT -> "Attachment"
            else -> "Onebox"
        }
        return linkCard(context, label, url, kind)
    }

    private fun linkCard(context: Context, label: String, url: String?, kind: String): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(context, 12), dp(context, 10), dp(context, 12), dp(context, 10))
            background = roundedBackground(context, Color.parseColor("#FFF0F9FF"), Color.parseColor("#6638BDF8"), 12)
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(context, 6)
                bottomMargin = dp(context, 6)
            }
            addView(
                textView(context, kind).apply {
                    textSize = 11f
                    setTypeface(typeface, Typeface.BOLD)
                    setTextColor(Color.parseColor("#FF0369A1"))
                },
            )
            addView(
                textView(context, label).apply {
                    textSize = 14f
                    setTextColor(Color.parseColor("#FF0F172A"))
                    setPadding(0, dp(context, 4), 0, 0)
                },
            )
            url?.let { resolvedUrl ->
                setOnClickListener { openUrl(context, resolvedUrl) }
                isClickable = true
            }
        }

    private fun blockContainer(context: Context, view: View): View =
        LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(context, 6)
                bottomMargin = dp(context, 6)
            }
            addView(view)
        }

    private fun textView(context: Context, value: CharSequence): TextView =
        TextView(context).apply {
            text = value
            movementMethod = LinkMovementMethod.getInstance()
            linksClickable = true
        }

    private fun subtreeText(node: CookedHtmlNodeState, tree: CookedTree): String =
        buildString {
            appendNodeText(node, tree)
        }.trim()

    private fun StringBuilder.appendNodeText(node: CookedHtmlNodeState, tree: CookedTree) {
        when (node.kind) {
            CookedHtmlNodeKindState.TEXT -> append(node.text.orEmpty())
            CookedHtmlNodeKindState.LINE_BREAK -> append('\n')
            CookedHtmlNodeKindState.IMAGE,
            CookedHtmlNodeKindState.EMOJI -> append(node.alt ?: node.title ?: "")
            else -> tree.childrenOf(node).forEach { appendNodeText(it, tree) }
        }
        if (
            node.kind in setOf(
                CookedHtmlNodeKindState.PARAGRAPH,
                CookedHtmlNodeKindState.HEADING,
                CookedHtmlNodeKindState.LIST_ITEM,
                CookedHtmlNodeKindState.TABLE_ROW,
            ) &&
            isNotEmpty() &&
            !endsWith('\n')
        ) {
            append('\n')
        }
    }

    private fun SpannableStringBuilder.trimmed(): SpannableStringBuilder {
        while (isNotEmpty() && first().isWhitespace()) {
            delete(0, 1)
        }
        while (isNotEmpty() && last().isWhitespace()) {
            delete(length - 1, length)
        }
        return this
    }

    private fun resolveUrl(url: String?, baseUrl: String): String? {
        val trimmed = url?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return try {
            java.net.URI(baseUrl).resolve(trimmed).toString()
        } catch (_: Exception) {
            trimmed
        }
    }

    private fun openUrl(context: Context, url: String) {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: ActivityNotFoundException) {
            Toast.makeText(context, url, Toast.LENGTH_SHORT).show()
        }
    }

    private fun roundedBackground(context: Context, fillColor: Int, strokeColor: Int, cornerRadiusDp: Int): GradientDrawable =
        GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(context, cornerRadiusDp).toFloat()
            setColor(fillColor)
            if (strokeColor != Color.TRANSPARENT) {
                setStroke(dp(context, 1), strokeColor)
            }
        }

    private fun dp(context: Context, value: Int): Int =
        (value * context.resources.displayMetrics.density).toInt()

    private data class InlineStyle(
        val bold: Boolean = false,
        val italic: Boolean = false,
        val strike: Boolean = false,
        val code: Boolean = false,
        val spoiler: Boolean = false,
        val linkUrl: String? = null,
    )

    private class FireLinkSpan(private val url: String) : ClickableSpan() {
        override fun onClick(widget: View) {
            openUrl(widget.context, url)
        }

        override fun updateDrawState(ds: TextPaint) {
            super.updateDrawState(ds)
            ds.color = Color.parseColor("#FF2563EB")
            ds.isUnderlineText = false
        }
    }

    private class CookedTree(nodes: List<CookedHtmlNodeState>) {
        private val childrenByParentId = nodes.groupBy { it.parentId }
        val root: CookedHtmlNodeState? = nodes.firstOrNull { it.kind == CookedHtmlNodeKindState.DOCUMENT }
            ?: nodes.firstOrNull { it.parentId == null }

        fun childrenOf(node: CookedHtmlNodeState): List<CookedHtmlNodeState> =
            childrenByParentId[node.id].orEmpty()
    }
}
