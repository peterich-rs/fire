package com.fire.app.core.image

object FireAvatarUrls {
    const val CANONICAL_SIZE_PX = 384
    private const val DEFAULT_BASE_URL = "https://linux.do"

    fun build(
        template: String?,
        baseUrl: String = DEFAULT_BASE_URL,
        requestedSizePx: Int = CANONICAL_SIZE_PX,
    ): String? {
        val trimmed = template?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val pixelSize = maxOf(requestedSizePx, CANONICAL_SIZE_PX)
        val path = trimmed.replace("{size}", pixelSize.toString())
        return when {
            path.startsWith("http://") || path.startsWith("https://") -> path
            path.startsWith("//") -> {
                val scheme = baseUrl.substringBefore("://", DEFAULT_BASE_URL.substringBefore("://"))
                "$scheme:$path"
            }
            else -> "${baseUrl.trimEnd('/')}/${path.trimStart('/')}"
        }
    }
}
