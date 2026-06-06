package com.fire.app.richtext

import uniffi.fire_uniffi_types.RenderBlockKindState
import uniffi.fire_uniffi_types.RenderBlockState
import uniffi.fire_uniffi_types.RenderDocumentState

object FireRenderBlockBuilder {

    fun build(document: RenderDocumentState?): FireRichTextContent {
        if (document == null || document.blocks.isEmpty()) {
            return FireRichTextContent(
                nodes = emptyList(),
                plainText = document?.plainText.orEmpty(),
                imageAttachments = emptyList(),
            )
        }

        val tree = RenderBlockTree(document.blocks)
        val nodes = tree.root?.let { root ->
            tree.childrenOf(root).flatMap { mapBlock(it, tree) }
        } ?: emptyList()

        return FireRichTextContent(
            nodes = nodes,
            plainText = document.plainText,
            imageAttachments = document.imageAttachments.map { image ->
                FireCookedImage(
                    url = image.url,
                    altText = image.altText,
                    width = image.width?.toFloat(),
                    height = image.height?.toFloat(),
                )
            },
        )
    }

    private fun mapBlock(
        block: RenderBlockState,
        tree: RenderBlockTree,
    ): List<FireRichTextNode> {
        val children = tree.childrenOf(block).flatMap { mapBlock(it, tree) }

        return when (val kind = block.kind) {
            RenderBlockKindState.Document -> children
            is RenderBlockKindState.Text -> listOf(FireRichTextNode.Text(kind.content))
            RenderBlockKindState.Paragraph -> listOf(FireRichTextNode.Paragraph(children))
            is RenderBlockKindState.Heading -> listOf(FireRichTextNode.Heading(kind.level.toInt(), children))
            RenderBlockKindState.LineBreak -> listOf(FireRichTextNode.LineBreak)
            RenderBlockKindState.Bold -> listOf(FireRichTextNode.Bold(children))
            RenderBlockKindState.Italic -> listOf(FireRichTextNode.Italic(children))
            RenderBlockKindState.Strikethrough -> listOf(FireRichTextNode.Strikethrough(children))
            is RenderBlockKindState.InlineCode -> listOf(FireRichTextNode.Code(kind.code))
            is RenderBlockKindState.CodeBlock -> listOf(FireRichTextNode.CodeBlock(kind.language, kind.code))
            is RenderBlockKindState.Link -> listOf(FireRichTextNode.Link(kind.url, children))
            is RenderBlockKindState.Mention -> listOf(FireRichTextNode.Mention(kind.username))
            is RenderBlockKindState.MentionGroup -> listOf(FireRichTextNode.MentionGroup(kind.name, kind.url))
            is RenderBlockKindState.Hashtag -> listOf(FireRichTextNode.Hashtag(kind.text, kind.url, kind.kind))
            is RenderBlockKindState.Emoji -> listOf(
                FireRichTextNode.Emoji(
                    url = kind.url,
                    fallbackText = kind.fallbackText,
                    onlyEmoji = kind.onlyEmoji,
                ),
            )
            is RenderBlockKindState.Image -> listOf(
                FireRichTextNode.Image(
                    src = kind.url,
                    alt = kind.alt,
                    width = kind.width?.toFloat(),
                    height = kind.height?.toFloat(),
                ),
            )
            RenderBlockKindState.Blockquote -> listOf(FireRichTextNode.Blockquote(children))
            is RenderBlockKindState.Quote -> listOf(
                FireRichTextNode.Quote(
                    author = kind.author,
                    postNumber = kind.postNumber?.toUInt(),
                    topicId = kind.topicId?.toULong(),
                    children = children,
                ),
            )
            is RenderBlockKindState.List -> {
                val items = tree.childrenOf(block)
                    .filter { it.kind == RenderBlockKindState.ListItem }
                    .map { child ->
                        (mapBlock(child, tree).firstOrNull() as? FireRichTextNode.ListItem)?.children.orEmpty()
                    }
                if (items.isEmpty()) children else listOf(FireRichTextNode.ListNode(kind.ordered, items))
            }
            RenderBlockKindState.ListItem -> listOf(FireRichTextNode.ListItem(children))
            RenderBlockKindState.Spoiler -> listOf(FireRichTextNode.Spoiler(children))
            RenderBlockKindState.Details -> {
                val summary = tree.childrenOf(block)
                    .firstOrNull { it.kind == RenderBlockKindState.DetailsSummary }
                    ?.let { summaryBlock ->
                        tree.childrenOf(summaryBlock).flatMap { child -> mapBlock(child, tree) }
                    }
                    .orEmpty()
                val body = tree.childrenOf(block)
                    .filterNot { it.kind == RenderBlockKindState.DetailsSummary }
                    .flatMap { child -> mapBlock(child, tree) }
                listOf(FireRichTextNode.Details(summary = summary, children = body))
            }
            RenderBlockKindState.DetailsSummary -> children
            is RenderBlockKindState.Table -> listOf(FireRichTextNode.Table(kind.text))
            is RenderBlockKindState.Onebox -> listOf(
                FireRichTextNode.Onebox(
                    url = kind.url,
                    title = kind.title,
                    description = kind.description,
                ),
            )
            is RenderBlockKindState.Video -> listOf(FireRichTextNode.Video(kind.url, kind.title))
            RenderBlockKindState.Divider -> listOf(FireRichTextNode.Divider)
            RenderBlockKindState.Unknown -> children
        }
    }

    private class RenderBlockTree(blocks: List<RenderBlockState>) {
        private val childrenByParentId: Map<UInt, List<RenderBlockState>> =
            blocks.filter { it.parentId != null }.groupBy { it.parentId!! }
        val root: RenderBlockState? =
            blocks.firstOrNull { it.parentId == null && it.kind == RenderBlockKindState.Document }
                ?: blocks.firstOrNull { it.parentId == null }

        fun childrenOf(block: RenderBlockState): List<RenderBlockState> =
            childrenByParentId[block.id].orEmpty()
    }
}
