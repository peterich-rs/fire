package com.fire.app.richtext

sealed class FireRichTextNode {
    data class Text(val value: String) : FireRichTextNode()
    data class Bold(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Italic(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Strikethrough(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Code(val value: String) : FireRichTextNode()
    data class CodeBlock(val language: String?, val code: String) : FireRichTextNode()
    data class Link(val url: String, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Mention(val username: String) : FireRichTextNode()
    data class MentionGroup(val name: String, val url: String) : FireRichTextNode()
    data class Hashtag(val text: String, val url: String, val kind: String?) : FireRichTextNode()
    data class Emoji(val url: String, val fallbackText: String, val onlyEmoji: Boolean) : FireRichTextNode()
    data class Heading(val level: Int, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Blockquote(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Quote(
        val author: String?,
        val postNumber: UInt?,
        val topicId: ULong?,
        val children: List<FireRichTextNode>,
    ) : FireRichTextNode()
    data class Onebox(val url: String?, val title: String?, val description: String?) : FireRichTextNode()
    data class ListNode(val ordered: Boolean, val items: kotlin.collections.List<kotlin.collections.List<FireRichTextNode>>) : FireRichTextNode()
    data class ListItem(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Spoiler(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Details(val summary: List<FireRichTextNode>, val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Table(val text: String) : FireRichTextNode()
    data class Video(val url: String, val title: String?) : FireRichTextNode()
    data object Divider : FireRichTextNode()
    data object LineBreak : FireRichTextNode()
    data class Paragraph(val children: List<FireRichTextNode>) : FireRichTextNode()
    data class Image(val src: String, val alt: String?, val width: Float?, val height: Float?) : FireRichTextNode()
}
