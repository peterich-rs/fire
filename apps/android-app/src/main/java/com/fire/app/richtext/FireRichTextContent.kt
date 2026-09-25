package com.fire.app.richtext

data class FireRichTextContent(
    val nodes: List<FireRichTextNode>,
    val plainText: String,
    val imageAttachments: List<FireCookedImage>,
)

data class FireCookedImage(
    val url: String,
    val altText: String?,
    val width: Float?,
    val height: Float?,
)