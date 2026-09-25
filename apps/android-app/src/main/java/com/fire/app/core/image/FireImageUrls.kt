package com.fire.app.core.image

object FireImageUrls {
    private const val DEFAULT_BASE_URL = "https://linux.do"

    fun build(
        url: String?,
        baseUrl: String = DEFAULT_BASE_URL,
    ): String? {
        val trimmed = url?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        return when {
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            trimmed.startsWith("//") -> {
                val scheme = baseUrl.substringBefore("://", DEFAULT_BASE_URL.substringBefore("://"))
                "$scheme:$trimmed"
            }
            else -> "${baseUrl.trimEnd('/')}/${trimmed.trimStart('/')}"
        }
    }
}
