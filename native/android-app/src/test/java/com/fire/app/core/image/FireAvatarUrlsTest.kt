package com.fire.app.core.image

import org.junit.Assert.assertEquals
import org.junit.Test

class FireAvatarUrlsTest {
    @Test
    fun build_usesCanonicalSizeAcrossCommonAvatarSurfaces() {
        val template = "/user_avatar/linux.do/alice/{size}/1_2.png"

        assertEquals(
            FireAvatarUrls.build(template, requestedSizePx = 36),
            FireAvatarUrls.build(template, requestedSizePx = 128),
        )
        assertEquals(
            "https://linux.do/user_avatar/linux.do/alice/384/1_2.png",
            FireAvatarUrls.build(template, requestedSizePx = 36),
        )
    }

    @Test
    fun build_preservesAbsoluteAndProtocolRelativeUrls() {
        assertEquals(
            "https://cdn.linux.do/user_avatar/linux.do/alice/384/1_2.png",
            FireAvatarUrls.build("https://cdn.linux.do/user_avatar/linux.do/alice/{size}/1_2.png"),
        )
        assertEquals(
            "https://cdn.linux.do/user_avatar/linux.do/alice/384/1_2.png",
            FireAvatarUrls.build("//cdn.linux.do/user_avatar/linux.do/alice/{size}/1_2.png"),
        )
    }
}
