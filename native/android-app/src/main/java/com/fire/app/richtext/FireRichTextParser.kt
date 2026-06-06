package com.fire.app.richtext

import uniffi.fire_uniffi.renderCookedHtml
import uniffi.fire_uniffi_topics.TopicPostState
import uniffi.fire_uniffi_types.RenderDocumentState

object FireRichTextParser {

    fun parse(html: String, baseURLString: String): FireRichTextContent {
        if (html.isBlank()) {
            return FireRichTextContent(nodes = emptyList(), plainText = "", imageAttachments = emptyList())
        }
        return parse(renderCookedHtml(rawHtml = html, baseUrl = baseURLString))
    }

    fun parse(post: TopicPostState, baseURLString: String): FireRichTextContent {
        val document = post.renderDocument ?: renderCookedHtml(rawHtml = post.cooked, baseUrl = baseURLString)
        return parse(document)
    }

    fun parse(document: RenderDocumentState?): FireRichTextContent =
        FireRenderBlockBuilder.build(document)
}
