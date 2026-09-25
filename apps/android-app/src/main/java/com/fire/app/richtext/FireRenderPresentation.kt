package com.fire.app.richtext

import uniffi.fire_uniffi_types.RenderDocumentHandle
import uniffi.fire_uniffi_types.RenderOneboxCardState
import uniffi.fire_uniffi_types.RenderRichNodeState
import uniffi.fire_uniffi_types.RenderUiSegmentState

/// Host mapping for Rust `RenderDocumentHandle`.
///
/// Production cells consume the precomputed UI plan. They do not parse
/// cooked HTML or rebuild a block tree.
object FireRenderPresentation {
    fun content(handle: RenderDocumentHandle): FireRichTextContent {
        return FireRichTextContent(
            nodes = richNodes(handle),
            plainText = handle.plainText(),
            imageAttachments = images(handle),
        )
    }

    fun blocks(handle: RenderDocumentHandle): List<FireRichTextBlock> {
        return (0u until handle.segmentCount()).mapNotNull { index ->
            when (val segment = handle.segment(index)) {
                is RenderUiSegmentState.Rich -> {
                    val nodes = segment.nodes.map(::mapNode)
                    if (nodes.isEmpty()) null else FireRichTextBlock.Text(nodes)
                }
                is RenderUiSegmentState.Image -> {
                    val url = segment.image.url.trim()
                    if (url.isEmpty()) {
                        null
                    } else {
                        FireRichTextBlock.Image(
                            FireCookedImage(
                                url = url,
                                altText = segment.image.altText,
                                width = segment.image.width?.toFloat(),
                                height = segment.image.height?.toFloat(),
                            ),
                        )
                    }
                }
                is RenderUiSegmentState.Onebox -> {
                    FireRichTextBlock.Text(listOf(mapOnebox(segment.card)))
                }
                null -> null
            }
        }
    }

    fun images(handle: RenderDocumentHandle): List<FireCookedImage> {
        return handle.imageAttachments().map { image ->
            FireCookedImage(
                url = image.url,
                altText = image.altText,
                width = image.width?.toFloat(),
                height = image.height?.toFloat(),
            )
        }
    }

    fun richNodes(handle: RenderDocumentHandle): List<FireRichTextNode> {
        return (0u until handle.segmentCount()).flatMap { index ->
            when (val segment = handle.segment(index)) {
                is RenderUiSegmentState.Rich -> segment.nodes.map(::mapNode)
                else -> emptyList()
            }
        }
    }

    fun mapNode(node: RenderRichNodeState): FireRichTextNode {
        return when (node) {
            is RenderRichNodeState.Text -> FireRichTextNode.Text(node.content)
            is RenderRichNodeState.Bold -> FireRichTextNode.Bold(node.children.map(::mapNode))
            is RenderRichNodeState.Italic -> FireRichTextNode.Italic(node.children.map(::mapNode))
            is RenderRichNodeState.Strikethrough -> FireRichTextNode.Strikethrough(node.children.map(::mapNode))
            is RenderRichNodeState.Code -> FireRichTextNode.Code(node.code)
            is RenderRichNodeState.CodeBlock -> FireRichTextNode.CodeBlock(node.language, node.code)
            is RenderRichNodeState.Link -> FireRichTextNode.Link(node.url, node.children.map(::mapNode))
            is RenderRichNodeState.Mention -> FireRichTextNode.Mention(node.username)
            is RenderRichNodeState.MentionGroup -> FireRichTextNode.MentionGroup(node.name, node.url)
            is RenderRichNodeState.Hashtag -> FireRichTextNode.Hashtag(node.text, node.url, node.kind)
            is RenderRichNodeState.Emoji -> FireRichTextNode.Emoji(node.url, node.fallbackText, node.onlyEmoji)
            is RenderRichNodeState.Heading -> FireRichTextNode.Heading(node.level.toInt(), node.children.map(::mapNode))
            is RenderRichNodeState.Blockquote -> FireRichTextNode.Blockquote(node.children.map(::mapNode))
            is RenderRichNodeState.Quote -> FireRichTextNode.Quote(
                author = node.author,
                postNumber = node.postNumber,
                topicId = node.topicId,
                children = node.children.map(::mapNode),
            )
            is RenderRichNodeState.ListNode -> FireRichTextNode.ListNode(
                ordered = node.ordered,
                items = node.items.map { item -> item.map(::mapNode) },
            )
            is RenderRichNodeState.ListItem -> FireRichTextNode.ListItem(node.children.map(::mapNode))
            is RenderRichNodeState.Spoiler -> FireRichTextNode.Spoiler(node.children.map(::mapNode))
            is RenderRichNodeState.Details -> FireRichTextNode.Details(
                summary = node.summary.map(::mapNode),
                children = node.children.map(::mapNode),
            )
            is RenderRichNodeState.Table -> FireRichTextNode.Table(node.text)
            is RenderRichNodeState.Video -> FireRichTextNode.Video(node.url, node.title)
            is RenderRichNodeState.Divider -> FireRichTextNode.Divider
            is RenderRichNodeState.LineBreak -> FireRichTextNode.LineBreak
            is RenderRichNodeState.Paragraph -> FireRichTextNode.Paragraph(node.children.map(::mapNode))
            is RenderRichNodeState.Image -> FireRichTextNode.Image(
                src = node.url,
                alt = node.alt,
                width = node.width?.toFloat(),
                height = node.height?.toFloat(),
            )
            is RenderRichNodeState.Onebox -> mapOnebox(node.card)
        }
    }

    private fun mapOnebox(card: RenderOneboxCardState): FireRichTextNode.Onebox {
        return FireRichTextNode.Onebox(
            url = card.url,
            title = card.title,
            description = card.description,
            sourceName = card.sourceName,
            iconUrl = card.iconUrl,
            thumbnailUrl = card.thumbnailUrl,
            thumbnailWidth = card.thumbnailWidth?.toFloat(),
            thumbnailHeight = card.thumbnailHeight?.toFloat(),
        )
    }
}
