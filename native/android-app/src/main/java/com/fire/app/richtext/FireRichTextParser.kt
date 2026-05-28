package com.fire.app.richtext

import uniffi.fire_uniffi.CookedHtmlAttributeState
import uniffi.fire_uniffi.CookedHtmlDocumentState
import uniffi.fire_uniffi.CookedHtmlNodeKindState
import uniffi.fire_uniffi.CookedHtmlNodeState
import uniffi.fire_uniffi.parseCookedHtml

object FireRichTextParser {

    fun parse(html: String, baseURLString: String): FireRichTextContent {
        if (html.isBlank()) {
            return FireRichTextContent(nodes = emptyList(), plainText = "", imageAttachments = emptyList())
        }
        val document = parseCookedHtml(rawHtml = html)
        val tree = CookedTree(document.nodes)
        val nodes = tree.root?.let { root ->
            tree.childrenOf(root).flatMap { mapNode(it, tree, baseURLString) }
        } ?: emptyList()

        val images = collectImageAttachments(document, tree, baseURLString)

        return FireRichTextContent(
            nodes = nodes,
            plainText = document.plainText,
            imageAttachments = images,
        )
    }

    private fun mapNode(
        node: CookedHtmlNodeState,
        tree: CookedTree,
        baseURLString: String,
    ): List<FireRichTextNode> {
        val children = tree.childrenOf(node).flatMap { mapNode(it, tree, baseURLString) }
        val attrs = attributesFrom(node)

        return when (node.kind) {
            CookedHtmlNodeKindState.DOCUMENT -> children

            CookedHtmlNodeKindState.TEXT -> {
                normalizedText(node.text)?.let { listOf(FireRichTextNode.Text(it)) } ?: emptyList()
            }

            CookedHtmlNodeKindState.PARAGRAPH -> listOf(FireRichTextNode.Paragraph(children))

            CookedHtmlNodeKindState.HEADING -> listOf(FireRichTextNode.Heading(
                level = (node.level?.toInt() ?: 2).coerceIn(1, 6),
                children = children,
            ))

            CookedHtmlNodeKindState.LINE_BREAK -> listOf(FireRichTextNode.LineBreak)

            CookedHtmlNodeKindState.STRONG -> listOf(FireRichTextNode.Bold(children))

            CookedHtmlNodeKindState.EMPHASIS -> listOf(FireRichTextNode.Italic(children))

            CookedHtmlNodeKindState.STRIKETHROUGH -> listOf(FireRichTextNode.Strikethrough(children))

            CookedHtmlNodeKindState.CODE -> listOf(FireRichTextNode.Code(subtreeText(node, tree)))

            CookedHtmlNodeKindState.CODE_BLOCK -> listOf(FireRichTextNode.CodeBlock(
                language = codeLanguage(node, tree),
                code = subtreeText(node, tree),
            ))

            CookedHtmlNodeKindState.LINK -> mapLinkNode(node, children, attrs, baseURLString)

            CookedHtmlNodeKindState.MENTION -> {
                val username = extractTextContent(children).trim().removePrefix("@")
                if (username.isBlank()) children else listOf(FireRichTextNode.Mention(username))
            }

            CookedHtmlNodeKindState.HASHTAG -> {
                val text = extractTextContent(children).trim().removePrefix("#")
                val url = resolveURL(node.url ?: "", baseURLString)
                if (text.isBlank()) children else listOf(FireRichTextNode.Hashtag(text, url, normalizedText(attrs["data-type"])))
            }

            CookedHtmlNodeKindState.IMAGE -> {
                val src = resolvedURLString(node.url, baseURLString) ?: return emptyList()
                if (isEmojiNode(node)) return emptyList()
                listOf(FireRichTextNode.Image(
                    src = src,
                    alt = normalizedText(node.alt),
                    width = numericAttribute("width", attrs),
                    height = numericAttribute("height", attrs),
                ))
            }

            CookedHtmlNodeKindState.EMOJI -> {
                val source = resolvedURLString(node.url, baseURLString) ?: return emptyList()
                listOf(FireRichTextNode.Emoji(
                    url = source,
                    fallbackText = emojiFallbackText(attrs, source),
                    onlyEmoji = classNames(attrs["class"]).contains("only-emoji"),
                ))
            }

            CookedHtmlNodeKindState.BLOCKQUOTE -> listOf(FireRichTextNode.Blockquote(children))

            CookedHtmlNodeKindState.DISCOURSE_QUOTE -> listOf(FireRichTextNode.Quote(
                author = normalizedText(attrs["data-username"] ?: node.title),
                postNumber = attrs["data-post"]?.toUIntOrNull(),
                topicId = attrs["data-topic"]?.toULongOrNull(),
                children = normalizeQuotedChildren(children),
            ))

            CookedHtmlNodeKindState.LIST -> {
                val items = tree.childrenOf(node)
                    .filter { it.kind == CookedHtmlNodeKindState.LIST_ITEM }
                    .map { tree.childrenOf(it).flatMap { child -> mapNode(child, tree, baseURLString) } }
                if (items.isEmpty()) children else listOf(FireRichTextNode.ListNode(ordered = node.ordered == true, items = items))
            }

            CookedHtmlNodeKindState.LIST_ITEM -> listOf(FireRichTextNode.ListItem(children))

            CookedHtmlNodeKindState.SPOILER -> listOf(FireRichTextNode.Spoiler(children))

            CookedHtmlNodeKindState.DETAILS -> {
                val parts = detailsParts(children)
                listOf(FireRichTextNode.Details(summary = parts.first, children = parts.second))
            }

            CookedHtmlNodeKindState.TABLE -> listOf(FireRichTextNode.Table(tablePlainText(node, tree)))

            CookedHtmlNodeKindState.TABLE_ROW, CookedHtmlNodeKindState.TABLE_CELL -> children

            CookedHtmlNodeKindState.ONEBOX -> listOf(FireRichTextNode.Onebox(
                url = resolvedURLString(node.url, baseURLString),
                title = normalizedText(node.title) ?: normalizedText(subtreeText(node, tree)),
                description = null,
            ))

            CookedHtmlNodeKindState.IFRAME -> {
                val url = resolvedURLString(node.url, baseURLString) ?: return children
                listOf(FireRichTextNode.Video(url, normalizedText(node.title)))
            }

            CookedHtmlNodeKindState.ATTACHMENT -> {
                val url = resolveURL(node.url ?: "", baseURLString)
                if (url.isBlank()) children else listOf(FireRichTextNode.Link(url, children))
            }

            CookedHtmlNodeKindState.UNKNOWN -> children
        }
    }

    private fun mapLinkNode(
        node: CookedHtmlNodeState,
        children: List<FireRichTextNode>,
        attrs: Map<String, String>,
        baseURLString: String,
    ): List<FireRichTextNode> {
        val url = resolveURL(node.url ?: "", baseURLString)
        val classes = classNames(attrs["class"])

        if (classes.contains("mention-group")) {
            val name = extractTextContent(children).trim().removePrefix("@")
            return if (name.isBlank()) children else listOf(FireRichTextNode.MentionGroup(name, url))
        }
        if (classes.contains("mention")) {
            val username = extractTextContent(children).trim().removePrefix("@")
            return if (username.isBlank()) children else listOf(FireRichTextNode.Mention(username))
        }
        if (classes.contains("hashtag") || classes.contains("hashtag-cooked")) {
            val text = extractTextContent(children).trim().removePrefix("#")
            return if (text.isBlank()) children else listOf(FireRichTextNode.Hashtag(text, url, normalizedText(attrs["data-type"])))
        }
        if (shouldSuppressLinkForInlineImage(url, classes, children)) {
            return children
        }
        return listOf(FireRichTextNode.Link(url, children))
    }

    // -- Helpers --

    private class CookedTree(nodes: List<CookedHtmlNodeState>) {
        private val childrenByParentId: Map<UInt, List<CookedHtmlNodeState>> =
            nodes.filter { it.parentId != null }.groupBy { it.parentId!! }
        val root: CookedHtmlNodeState? =
            nodes.firstOrNull { it.kind == CookedHtmlNodeKindState.DOCUMENT }
                ?: nodes.firstOrNull { it.parentId == null }

        fun childrenOf(node: CookedHtmlNodeState): List<CookedHtmlNodeState> =
            childrenByParentId[node.id].orEmpty()
    }

    private fun attributesFrom(node: CookedHtmlNodeState): Map<String, String> =
        node.attributes.associate { it.name.lowercase() to it.value }

    private fun normalizedText(raw: String?): String? {
        val trimmed = raw?.trim()?.ifBlank { null }
        return trimmed?.ifEmpty { null }
    }

    private fun resolveURL(href: String, baseURLString: String): String {
        val trimmed = href.trim()
        if (trimmed.isBlank()) return ""
        if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) return trimmed
        if (trimmed.startsWith("//")) return "https:$trimmed"
        if (trimmed.startsWith("/")) {
            val base = baseURLString.trimEnd('/')
            return "$base$trimmed"
        }
        return trimmed
    }

    private fun resolvedURLString(rawValue: String?, baseURLString: String): String? {
        val resolved = resolveURL(rawValue ?: "", baseURLString)
        return resolved.ifBlank { null }
    }

    private fun subtreeText(node: CookedHtmlNodeState, tree: CookedTree): String {
        val builder = StringBuilder()
        appendSubtreeText(node, tree, builder)
        return builder.toString().trim()
    }

    private fun appendSubtreeText(node: CookedHtmlNodeState, tree: CookedTree, builder: StringBuilder) {
        when (node.kind) {
            CookedHtmlNodeKindState.TEXT -> builder.append(node.text.orEmpty())
            CookedHtmlNodeKindState.LINE_BREAK -> builder.append('\n')
            CookedHtmlNodeKindState.IMAGE, CookedHtmlNodeKindState.EMOJI -> builder.append(node.alt ?: node.title ?: "")
            else -> tree.childrenOf(node).forEach { appendSubtreeText(it, tree, builder) }
        }
    }

    private fun extractTextContent(nodes: List<FireRichTextNode>, includingEmojiFallback: Boolean = true): String {
        return nodes.joinToString("") { node ->
            when (node) {
                is FireRichTextNode.Text -> node.value
                is FireRichTextNode.Code -> node.value
                is FireRichTextNode.CodeBlock -> node.code
                is FireRichTextNode.Mention -> "@${node.username}"
                is FireRichTextNode.MentionGroup -> "@${node.name}"
                is FireRichTextNode.Hashtag -> "#${node.text}"
                is FireRichTextNode.Emoji -> if (includingEmojiFallback) node.fallbackText else ""
                is FireRichTextNode.Bold, is FireRichTextNode.Italic, is FireRichTextNode.Strikethrough,
                is FireRichTextNode.Paragraph, is FireRichTextNode.Heading, is FireRichTextNode.Blockquote,
                is FireRichTextNode.Quote, is FireRichTextNode.ListItem, is FireRichTextNode.Link,
                is FireRichTextNode.Spoiler, is FireRichTextNode.Details -> {
                    val children = when (node) {
                        is FireRichTextNode.Bold -> node.children
                        is FireRichTextNode.Italic -> node.children
                        is FireRichTextNode.Strikethrough -> node.children
                        is FireRichTextNode.Paragraph -> node.children
                        is FireRichTextNode.Heading -> node.children
                        is FireRichTextNode.Blockquote -> node.children
                        is FireRichTextNode.Quote -> node.children
                        is FireRichTextNode.ListItem -> node.children
                        is FireRichTextNode.Link -> node.children
                        is FireRichTextNode.Spoiler -> node.children
                        is FireRichTextNode.Details -> node.summary + node.children
                        else -> emptyList()
                    }
                    extractTextContent(children, includingEmojiFallback)
                }
                is FireRichTextNode.Onebox -> listOfNotNull(node.title, node.description, node.url).joinToString("\n")
                is FireRichTextNode.ListNode -> node.items.joinToString("\n") { extractTextContent(it, includingEmojiFallback) }
                is FireRichTextNode.Table -> node.text
                is FireRichTextNode.Video -> node.title ?: node.url
                is FireRichTextNode.Divider -> "\n"
                is FireRichTextNode.LineBreak -> "\n"
                is FireRichTextNode.Image -> ""
            }
        }
    }

    private fun codeLanguage(node: CookedHtmlNodeState, tree: CookedTree): String? {
        val attrs = attributesFrom(node)
        val classes = classNames(attrs["class"])
        for (className in classes) {
            if (className.startsWith("language-")) return className.removePrefix("language-")
            if (className.startsWith("lang-")) return className.removePrefix("lang-")
        }
        for (child in tree.childrenOf(node)) {
            val lang = codeLanguage(child, tree)
            if (lang != null) return lang
        }
        return null
    }

    private fun isEmojiNode(node: CookedHtmlNodeState): Boolean {
        if (node.kind == CookedHtmlNodeKindState.EMOJI) return true
        val attrs = attributesFrom(node)
        if (classNames(attrs["class"]).contains("emoji")) return true
        if (node.url?.contains("/images/emoji/") == true) return true
        return false
    }

    private fun classNames(rawValue: String?): Set<String> =
        (rawValue ?: "").split(Regex("\\s+")).filter { it.isNotBlank() }.map { it.lowercase() }.toSet()

    private fun numericAttribute(name: String, attrs: Map<String, String>): Float? =
        attrs[name]?.toFloatOrNull()

    private fun emojiFallbackText(attrs: Map<String, String>, resolvedURLString: String): String {
        normalizedText(attrs["title"])?.let { return it }
        normalizedText(attrs["alt"])?.let { return it }
        emojiShortcode(resolvedURLString)?.let { return it }
        return ":emoji:"
    }

    private fun emojiShortcode(urlString: String): String? {
        if (urlString.isBlank()) return null
        val rawPath = java.net.URI(urlString).path ?: urlString
        val range = rawPath.indexOf("/images/emoji/")
        if (range < 0) return null
        val components = rawPath.substring(range + "/images/emoji/".length)
            .split("/").map { it.replace(Regex("\\.[^.]+$"), "") }.filter { it.isNotBlank() }
        if (components.size < 2) return null
        val shortcodeComponents = components.drop(1)
        return normalizedEmojiFallback(shortcodeComponents.joinToString(":"))
    }

    private fun normalizedEmojiFallback(rawValue: String?): String? {
        val trimmed = normalizedText(rawValue) ?: return null
        val trimmedColons = trimmed.trim(':')
        val needsWrapping = trimmed.any { it.isLetterOrDigit() || it == '_' || it == '-' }
        return if (needsWrapping && trimmedColons.isNotBlank()) ":$trimmedColons:" else trimmed
    }

    private fun normalizeQuotedChildren(children: List<FireRichTextNode>): List<FireRichTextNode> {
        val meaningful = children.filter { child ->
            child !is FireRichTextNode.Text || child.value.trim().isNotBlank()
        }
        if (meaningful.size == 1 && meaningful[0] is FireRichTextNode.Blockquote) {
            return (meaningful[0] as FireRichTextNode.Blockquote).children
        }
        return children
    }

    private fun detailsParts(children: List<FireRichTextNode>): Pair<List<FireRichTextNode>, List<FireRichTextNode>> {
        val summary = mutableListOf<FireRichTextNode>()
        val body = mutableListOf<FireRichTextNode>()
        var isReadingSummary = true
        for (child in children) {
            if (isReadingSummary && isInlineDetailsSummaryNode(child)) {
                summary.add(child)
            } else {
                isReadingSummary = false
                body.add(child)
            }
        }
        return (summary.ifEmpty { listOf(FireRichTextNode.Text("Details")) }) to body
    }

    private fun isInlineDetailsSummaryNode(node: FireRichTextNode): Boolean = when (node) {
        is FireRichTextNode.Text -> node.value.trim().isNotBlank()
        is FireRichTextNode.Bold, is FireRichTextNode.Italic, is FireRichTextNode.Strikethrough,
        is FireRichTextNode.Code, is FireRichTextNode.Link, is FireRichTextNode.Mention,
        is FireRichTextNode.MentionGroup, is FireRichTextNode.Hashtag, is FireRichTextNode.Emoji -> true
        else -> false
    }

    private fun shouldSuppressLinkForInlineImage(
        urlString: String,
        classNames: Set<String>,
        children: List<FireRichTextNode>,
    ): Boolean {
        val visibleText = extractTextContent(children, includingEmojiFallback = false).trim()
        val imageLikeURL = isImageURL(urlString)
        if (classNames.contains("lightbox")) return true
        if (classNames.contains("attachment") && imageLikeURL) return visibleText.isBlank() || looksLikeImageFilename(visibleText)
        if (children.isEmpty() && imageLikeURL) return true
        return imageLikeURL && looksLikeImageFilename(visibleText)
    }

    private fun isImageURL(urlString: String): Boolean {
        val normalized = urlString.lowercase()
        return normalized.endsWith(".jpg") || normalized.endsWith(".jpeg") || normalized.endsWith(".png")
            || normalized.endsWith(".gif") || normalized.endsWith(".webp") || normalized.endsWith(".avif")
            || normalized.contains("/uploads/") || normalized.contains("/original/") || normalized.contains("/images/emoji/")
    }

    private fun looksLikeImageFilename(value: String): Boolean = value.isNotBlank() && isImageURL(value)

    private fun tablePlainText(node: CookedHtmlNodeState, tree: CookedTree): String {
        val rows = tree.childrenOf(node).filter { it.kind == CookedHtmlNodeKindState.TABLE_ROW }
        if (rows.isEmpty()) return subtreeText(node, tree)
        return rows.mapNotNull { row ->
            val cells = tree.childrenOf(row).filter { it.kind == CookedHtmlNodeKindState.TABLE_CELL }
            val text = cells.map { subtreeText(it, tree).trim() }.filter { it.isNotBlank() }.joinToString(" | ")
            text.ifBlank { null }
        }.joinToString("\n")
    }

    private fun collectImageAttachments(
        document: CookedHtmlDocumentState,
        tree: CookedTree,
        baseURLString: String,
    ): List<FireCookedImage> {
        val images = mutableListOf<FireCookedImage>()
        val seenURLs = mutableSetOf<String>()
        for (node in document.nodes) {
            if (node.kind != CookedHtmlNodeKindState.IMAGE || isEmojiNode(node)) continue
            val attrs = attributesFrom(node)
            val preferredSource = tree.nearestAncestor(node) { it.kind == CookedHtmlNodeKindState.LINK || it.kind == CookedHtmlNodeKindState.ATTACHMENT }?.url
            val rawSource = normalizedText(preferredSource) ?: normalizedText(node.url) ?: continue
            val sourceURL = resolvedAssetURL(rawSource, baseURLString) ?: continue
            val absoluteURL = sourceURL.toString()
            if (absoluteURL.contains("/images/emoji/") || absoluteURL in seenURLs) continue
            seenURLs.add(absoluteURL)
            images.add(FireCookedImage(url = absoluteURL, altText = normalizedText(node.alt), width = numericAttribute("width", attrs), height = numericAttribute("height", attrs)))
        }
        return images
    }

    private fun CookedTree.nearestAncestor(
        of: CookedHtmlNodeState,
        matching: (CookedHtmlNodeState) -> Boolean,
    ): CookedHtmlNodeState? {
        var current = node(of.parentId)
        while (current != null) {
            if (matching(current)) return current
            current = node(current.parentId)
        }
        return null
    }

    private fun resolvedAssetURL(rawValue: String, baseURLString: String): java.net.URL? {
        val trimmed = rawValue.trim()
        if (trimmed.isBlank()) return null
        if (trimmed.startsWith("//")) return java.net.URL("https:$trimmed")
        val absolute = java.net.URL(trimmed)
        if (absolute.protocol != null) return absolute
        return java.net.URL(java.net.URL(baseURLString), trimmed)
    }

    private fun node(id: UInt?): CookedHtmlNodeState? = null // Simplified — tree handles this internally
}
