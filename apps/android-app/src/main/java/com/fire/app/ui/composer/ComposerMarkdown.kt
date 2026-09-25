package com.fire.app.ui.composer

import android.widget.EditText

fun insertMarkdownAtCursor(input: EditText, markdown: String) {
    val start = input.selectionStart.coerceAtLeast(0)
    val end = input.selectionEnd.coerceAtLeast(start)
    val prefix = if (start == 0 || input.text.getOrNull(start - 1) == '\n') "" else "\n"
    val suffix = if (end >= input.text.length || input.text.getOrNull(end) == '\n') "\n" else "\n\n"
    input.text.replace(start, end, "$prefix$markdown$suffix")
    input.setSelection((start + prefix.length + markdown.length + suffix.length).coerceAtMost(input.text.length))
}

fun applyMarkdownFormat(input: EditText, action: MarkdownFormatAction) {
    val result = MarkdownInsertion.apply(
        action = action,
        text = input.text.toString(),
        selectionStart = input.selectionStart,
        selectionEnd = input.selectionEnd,
    )
    input.text.replace(0, input.text.length, result.text)
    input.setSelection(
        result.selectionStart.coerceIn(0, input.text.length),
        result.selectionEnd.coerceIn(0, input.text.length),
    )
    input.requestFocus()
}

enum class MarkdownFormatAction {
    BOLD,
    ITALIC,
    STRIKETHROUGH,
    INLINE_CODE,
    CODE_BLOCK,
    QUOTE,
    UNORDERED_LIST,
    ORDERED_LIST,
    LINK,
    IMAGE,
}

data class MarkdownInsertionResult(
    val text: String,
    val selectionStart: Int,
    val selectionEnd: Int = selectionStart,
)

object QuoteMarkdown {
    fun build(
        username: String,
        postNumber: UInt,
        topicId: ULong,
        plainText: String,
    ): String? {
        val trimmedText = plainText.trim()
        if (trimmedText.isEmpty()) return null

        val author = username
            .trim()
            .replace(Regex("\\s+"), " ")
            .replace('"', '\'')
            .ifBlank { "unknown" }
        return "[quote=\"$author, post:$postNumber, topic:$topicId\"]\n" +
            trimmedText +
            "\n[/quote]\n\n"
    }
}

object ComposerInitialBody {
    fun merge(
        initialBody: String,
        currentBody: String,
        preferredSelectionStart: Int = initialBody.length,
    ): MarkdownInsertionResult {
        if (initialBody.isBlank()) {
            return MarkdownInsertionResult(
                text = currentBody,
                selectionStart = currentBody.length,
            )
        }

        val trimmedInitial = initialBody.trim()
        val exactExistingIndex = currentBody.indexOf(initialBody)
        val trimmedExistingIndex = currentBody.indexOf(trimmedInitial)
        if (exactExistingIndex >= 0 || trimmedExistingIndex >= 0) {
            val index = if (exactExistingIndex >= 0) exactExistingIndex else trimmedExistingIndex
            val selectionOffset = if (exactExistingIndex >= 0) {
                preferredSelectionStart.coerceIn(0, initialBody.length)
            } else {
                preferredSelectionStart.coerceIn(0, trimmedInitial.length)
            }
            return MarkdownInsertionResult(
                text = currentBody,
                selectionStart = index + selectionOffset,
            )
        }

        if (currentBody.isBlank()) {
            return MarkdownInsertionResult(
                text = initialBody,
                selectionStart = preferredSelectionStart.coerceIn(0, initialBody.length),
            )
        }

        val separator = if (initialBody.endsWith("\n\n") || currentBody.startsWith("\n")) {
            ""
        } else {
            "\n\n"
        }
        val nextText = initialBody + separator + currentBody
        return MarkdownInsertionResult(
            text = nextText,
            selectionStart = preferredSelectionStart.coerceIn(0, initialBody.length),
        )
    }
}

object MarkdownInsertion {
    fun apply(
        action: MarkdownFormatAction,
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
    ): MarkdownInsertionResult {
        return when (action) {
            MarkdownFormatAction.BOLD -> wrap(text, selectionStart, selectionEnd, "**", "**")
            MarkdownFormatAction.ITALIC -> wrap(text, selectionStart, selectionEnd, "*", "*")
            MarkdownFormatAction.STRIKETHROUGH -> wrap(text, selectionStart, selectionEnd, "~~", "~~")
            MarkdownFormatAction.INLINE_CODE -> wrap(text, selectionStart, selectionEnd, "`", "`")
            MarkdownFormatAction.CODE_BLOCK -> codeBlock(text, selectionStart, selectionEnd)
            MarkdownFormatAction.QUOTE -> prefixLines(text, selectionStart, selectionEnd) { "> " }
            MarkdownFormatAction.UNORDERED_LIST -> prefixLines(text, selectionStart, selectionEnd) { "- " }
            MarkdownFormatAction.ORDERED_LIST -> prefixLines(text, selectionStart, selectionEnd) { index ->
                "${index + 1}. "
            }
            MarkdownFormatAction.LINK -> wrap(text, selectionStart, selectionEnd, "[", "](url)", "text")
            MarkdownFormatAction.IMAGE -> wrap(text, selectionStart, selectionEnd, "![", "](url)", "alt")
        }
    }

    private fun wrap(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        prefix: String,
        suffix: String,
        placeholder: String = "",
    ): MarkdownInsertionResult {
        val range = normalizedRange(text, selectionStart, selectionEnd)
        val selected = if (range.start < range.end) {
            text.substring(range.start, range.end)
        } else {
            placeholder
        }
        val replacement = "$prefix$selected$suffix"
        val nextText = text.replaceRange(range.start, range.end, replacement)
        val selectedLength = if (range.start < range.end) {
            range.end - range.start
        } else {
            placeholder.length
        }
        val nextSelectionStart = range.start + prefix.length
        return MarkdownInsertionResult(
            text = nextText,
            selectionStart = nextSelectionStart,
            selectionEnd = nextSelectionStart + selectedLength,
        )
    }

    private fun codeBlock(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
    ): MarkdownInsertionResult {
        val range = normalizedRange(text, selectionStart, selectionEnd)
        val selected = text.substring(range.start, range.end)
        val startsLine = range.start == 0 || text.getOrNull(range.start - 1) == '\n'
        val endsLine = range.end >= text.length || text.getOrNull(range.end) == '\n'
        val leadingBreak = if (startsLine) "" else "\n"
        val trailingBreak = if (endsLine) "" else "\n"
        val replacement = "${leadingBreak}```\n$selected\n```$trailingBreak"
        val nextText = text.replaceRange(range.start, range.end, replacement)
        val nextSelectionStart = range.start + leadingBreak.length + "```\n".length
        return MarkdownInsertionResult(
            text = nextText,
            selectionStart = nextSelectionStart,
            selectionEnd = nextSelectionStart + selected.length,
        )
    }

    private fun prefixLines(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
        prefix: (Int) -> String,
    ): MarkdownInsertionResult {
        val range = normalizedRange(text, selectionStart, selectionEnd)
        if (range.start == range.end) {
            val lineStart = lineStart(text, range.start)
            val linePrefix = prefix(0)
            val nextText = text.replaceRange(lineStart, lineStart, linePrefix)
            val nextSelection = range.start + linePrefix.length
            return MarkdownInsertionResult(nextText, nextSelection)
        }

        val lineStart = lineStart(text, range.start)
        val lineEnd = if (range.end >= text.length) {
            text.length
        } else {
            text.indexOf('\n', range.end)
                .let { if (it < 0) text.length else it }
        }
        val selectedLines = text.substring(lineStart, lineEnd)
        val replacement = selectedLines
            .split('\n')
            .mapIndexed { index, line -> "${prefix(index)}$line" }
            .joinToString("\n")
        val nextText = text.replaceRange(lineStart, lineEnd, replacement)
        return MarkdownInsertionResult(
            text = nextText,
            selectionStart = lineStart,
            selectionEnd = lineStart + replacement.length,
        )
    }

    private fun normalizedRange(
        text: String,
        selectionStart: Int,
        selectionEnd: Int,
    ): MarkdownTextRange {
        val start = selectionStart.coerceIn(0, text.length)
        val end = selectionEnd.coerceIn(0, text.length)
        return MarkdownTextRange(
            start = minOf(start, end),
            end = maxOf(start, end),
        )
    }

    private fun lineStart(text: String, offset: Int): Int {
        if (offset <= 0) return 0
        val previousNewline = text.lastIndexOf('\n', offset - 1)
        return if (previousNewline < 0) 0 else previousNewline + 1
    }

    private data class MarkdownTextRange(
        val start: Int,
        val end: Int,
    )
}
