package com.fire.app.richtext

sealed class FireRichTextBlock {
    data class Text(val nodes: List<FireRichTextNode>) : FireRichTextBlock()
    data class Image(val image: FireCookedImage) : FireRichTextBlock()
}

object FireRichTextBlockBuilder {

    fun build(content: FireRichTextContent): List<FireRichTextBlock> {
        return build(content.nodes, content.imageAttachments)
    }

    fun build(nodes: List<FireRichTextNode>): List<FireRichTextBlock> {
        return build(nodes, emptyList())
    }

    fun build(
        nodes: List<FireRichTextNode>,
        imageAttachments: List<FireCookedImage>,
    ): List<FireRichTextBlock> {
        val blocks = mutableListOf<FireRichTextBlock>()
        val pendingText = mutableListOf<FireRichTextNode>()
        var imageAttachmentIndex = 0

        fun flushText() {
            if (pendingText.isNotEmpty()) {
                blocks += FireRichTextBlock.Text(pendingText.toList())
                pendingText.clear()
            }
        }

        for (piece in splitNodes(nodes)) {
            when (piece) {
                is Piece.Text -> pendingText += piece.nodes
                is Piece.Image -> {
                    flushText()
                    val image = imageAttachments.getOrNull(imageAttachmentIndex) ?: piece.image
                    blocks += FireRichTextBlock.Image(image)
                    imageAttachmentIndex += 1
                }
            }
        }
        flushText()
        val emittedImageUrls = blocks
            .asSequence()
            .filterIsInstance<FireRichTextBlock.Image>()
            .map { it.image.url.trim() }
            .filter { it.isNotEmpty() }
            .toMutableSet()
        for (image in imageAttachments) {
            val url = image.url.trim()
            if (url.isNotEmpty() && emittedImageUrls.add(url)) {
                flushText()
                blocks += FireRichTextBlock.Image(image.copy(url = url))
            }
        }
        return blocks
    }

    private fun splitNodes(nodes: List<FireRichTextNode>): List<Piece> {
        return nodes.flatMap(::splitNode).mergeAdjacentText()
    }

    private fun splitNode(node: FireRichTextNode): List<Piece> {
        if (node is FireRichTextNode.Image) {
            return listOf(
                Piece.Image(
                    FireCookedImage(
                        url = node.src,
                        altText = node.alt,
                        width = node.width,
                        height = node.height,
                    ),
                ),
            )
        }

        if (node is FireRichTextNode.Details) {
            return splitDetailsNode(node)
        }

        val children = node.childrenOrNull() ?: return listOf(Piece.Text(listOf(node)))
        val childPieces = splitNodes(children)
        if (childPieces.none { it is Piece.Image }) {
            return listOfNotNull(node.withChildren(children)?.let { Piece.Text(listOf(it)) })
        }

        return childPieces.mapNotNull { piece ->
            when (piece) {
                is Piece.Image -> piece
                is Piece.Text -> node.withChildren(piece.nodes)?.let { Piece.Text(listOf(it)) }
            }
        }.mergeAdjacentText()
    }

    private fun splitDetailsNode(node: FireRichTextNode.Details): List<Piece> {
        val summaryPieces = splitNodes(node.summary)
        val bodyPieces = splitNodes(node.children)
        if ((summaryPieces + bodyPieces).none { it is Piece.Image }) {
            return listOf(Piece.Text(listOf(node)))
        }

        val summaryTextNodes = summaryPieces
            .filterIsInstance<Piece.Text>()
            .flatMap { it.nodes }
        val summaryHasImages = summaryPieces.any { it is Piece.Image }
        val pieces = mutableListOf<Piece>()

        if (summaryHasImages) {
            for (piece in summaryPieces) {
                when (piece) {
                    is Piece.Image -> pieces += piece
                    is Piece.Text -> {
                        if (piece.nodes.isNotEmpty()) {
                            pieces += Piece.Text(
                                listOf(FireRichTextNode.Details(summary = piece.nodes, children = emptyList())),
                            )
                        }
                    }
                }
            }
        }

        var emittedDetailsText = false
        for (piece in bodyPieces) {
            when (piece) {
                is Piece.Image -> {
                    if (!summaryHasImages && !emittedDetailsText) {
                        pieces += Piece.Text(
                            listOf(FireRichTextNode.Details(summary = summaryTextNodes, children = emptyList())),
                        )
                        emittedDetailsText = true
                    }
                    pieces += piece
                }
                is Piece.Text -> {
                    if (piece.nodes.isNotEmpty()) {
                        pieces += Piece.Text(
                            listOf(
                                FireRichTextNode.Details(
                                    summary = summaryTextNodes,
                                    children = piece.nodes,
                                ),
                            ),
                        )
                        emittedDetailsText = true
                    }
                }
            }
        }

        return pieces.mergeAdjacentText()
    }

    private fun List<Piece>.mergeAdjacentText(): List<Piece> {
        if (isEmpty()) return this
        val merged = mutableListOf<Piece>()
        val pending = mutableListOf<FireRichTextNode>()

        fun flush() {
            if (pending.isNotEmpty()) {
                merged += Piece.Text(pending.toList())
                pending.clear()
            }
        }

        for (piece in this) {
            when (piece) {
                is Piece.Text -> pending += piece.nodes
                is Piece.Image -> {
                    flush()
                    merged += piece
                }
            }
        }
        flush()
        return merged
    }

    private fun FireRichTextNode.childrenOrNull(): List<FireRichTextNode>? {
        return when (this) {
            is FireRichTextNode.Bold -> children
            is FireRichTextNode.Italic -> children
            is FireRichTextNode.Strikethrough -> children
            is FireRichTextNode.Link -> children
            is FireRichTextNode.Heading -> children
            is FireRichTextNode.Blockquote -> children
            is FireRichTextNode.Quote -> children
            is FireRichTextNode.Spoiler -> children
            is FireRichTextNode.ListItem -> children
            is FireRichTextNode.Paragraph -> children
            else -> null
        }
    }

    private fun FireRichTextNode.withChildren(children: List<FireRichTextNode>): FireRichTextNode? {
        if (children.isEmpty()) return null
        return when (this) {
            is FireRichTextNode.Bold -> copy(children = children)
            is FireRichTextNode.Italic -> copy(children = children)
            is FireRichTextNode.Strikethrough -> copy(children = children)
            is FireRichTextNode.Link -> copy(children = children)
            is FireRichTextNode.Heading -> copy(children = children)
            is FireRichTextNode.Blockquote -> copy(children = children)
            is FireRichTextNode.Quote -> copy(children = children)
            is FireRichTextNode.Spoiler -> copy(children = children)
            is FireRichTextNode.ListItem -> copy(children = children)
            is FireRichTextNode.Paragraph -> copy(children = children)
            else -> this
        }
    }

    private sealed class Piece {
        data class Text(val nodes: List<FireRichTextNode>) : Piece()
        data class Image(val image: FireCookedImage) : Piece()
    }
}
