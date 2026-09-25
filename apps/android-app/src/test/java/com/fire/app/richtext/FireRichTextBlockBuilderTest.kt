package com.fire.app.richtext

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import uniffi.fire_uniffi_types.RenderBlockKindState
import uniffi.fire_uniffi_types.RenderBlockState
import uniffi.fire_uniffi_types.RenderDocumentState
import uniffi.fire_uniffi_types.RenderImageAttachmentState

class FireRichTextBlockBuilderTest {

    @Test
    fun build_keepsImageAtOriginalParagraphPosition() {
        val blocks = FireRichTextBlockBuilder.build(
            listOf(
                FireRichTextNode.Paragraph(
                    listOf(
                        FireRichTextNode.Text("before"),
                        FireRichTextNode.Image(
                            src = "https://linux.do/uploads/image.png",
                            alt = "image",
                            width = 1080f,
                            height = 1920f,
                        ),
                        FireRichTextNode.Text("after"),
                    ),
                ),
            ),
        )

        assertEquals(3, blocks.size)
        assertTrue(blocks[0] is FireRichTextBlock.Text)
        assertTrue(blocks[1] is FireRichTextBlock.Image)
        assertTrue(blocks[2] is FireRichTextBlock.Text)
        assertEquals("https://linux.do/uploads/image.png", (blocks[1] as FireRichTextBlock.Image).image.url)
    }

    @Test
    fun build_emitsImageOnlyParagraphAsImageBlock() {
        val blocks = FireRichTextBlockBuilder.build(
            listOf(
                FireRichTextNode.Paragraph(
                    listOf(
                        FireRichTextNode.Image(
                            src = "https://linux.do/uploads/only.png",
                            alt = null,
                            width = 800f,
                            height = 600f,
                        ),
                    ),
                ),
            ),
        )

        assertEquals(1, blocks.size)
        assertEquals("https://linux.do/uploads/only.png", (blocks.single() as FireRichTextBlock.Image).image.url)
    }

    @Test
    fun build_preservesTopLevelTextImageTextOrder() {
        val blocks = FireRichTextBlockBuilder.build(
            listOf(
                FireRichTextNode.Heading(2, listOf(FireRichTextNode.Text("title"))),
                FireRichTextNode.Image(
                    src = "https://linux.do/uploads/photo.jpg",
                    alt = "photo",
                    width = 1080f,
                    height = 1920f,
                ),
                FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("caption"))),
            ),
        )

        assertTrue(blocks[0] is FireRichTextBlock.Text)
        assertEquals("https://linux.do/uploads/photo.jpg", (blocks[1] as FireRichTextBlock.Image).image.url)
        assertTrue(blocks[2] is FireRichTextBlock.Text)
    }

    @Test
    fun build_prefersSharedOriginalImageAttachmentUrl() {
        val content = FireRichTextContent(
            nodes = listOf(
                FireRichTextNode.Paragraph(
                    listOf(
                        FireRichTextNode.Text("before"),
                        FireRichTextNode.Image(
                            src = "https://linux.do/uploads/default/optimized/1X/fire_690x388.png",
                            alt = "fire",
                            width = 690f,
                            height = 388f,
                        ),
                        FireRichTextNode.Text("after"),
                    ),
                ),
            ),
            plainText = "before fire after",
            imageAttachments = listOf(
                FireCookedImage(
                    url = "https://linux.do/uploads/default/original/1X/fire-full.png",
                    altText = "fire",
                    width = 690f,
                    height = 388f,
                ),
            ),
        )

        val blocks = FireRichTextBlockBuilder.build(content)

        assertEquals("https://linux.do/uploads/default/original/1X/fire-full.png", (blocks[1] as FireRichTextBlock.Image).image.url)
    }

    @Test
    fun build_emitsImageAttachmentsWhenRenderTreeHasNoImageBlock() {
        val content = FireRichTextContent(
            nodes = listOf(
                FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("caption"))),
            ),
            plainText = "caption",
            imageAttachments = listOf(
                FireCookedImage(
                    url = "https://linux.do/uploads/default/original/1X/attached.png",
                    altText = "attached",
                    width = 640f,
                    height = 480f,
                ),
            ),
        )

        val blocks = FireRichTextBlockBuilder.build(content)

        assertEquals(2, blocks.size)
        assertTrue(blocks[0] is FireRichTextBlock.Text)
        assertEquals("https://linux.do/uploads/default/original/1X/attached.png", (blocks[1] as FireRichTextBlock.Image).image.url)
    }

    @Test
    fun build_adaptsSharedRenderDocumentWithoutCookedHtmlFallback() {
        val document = RenderDocumentState(
            blocks = listOf(
                RenderBlockState(0u, null, 0u, RenderBlockKindState.Document),
                RenderBlockState(1u, 0u, 1u, RenderBlockKindState.Paragraph),
                RenderBlockState(2u, 1u, 2u, RenderBlockKindState.Text("caption")),
                RenderBlockState(
                    3u,
                    0u,
                    1u,
                    RenderBlockKindState.Image(
                        url = "https://linux.do/uploads/default/original/1X/fire.png",
                        alt = "fire",
                        width = 1080u,
                        height = 1920u,
                    ),
                ),
            ),
            plainText = "caption\n\nfire",
            imageAttachments = listOf(
                RenderImageAttachmentState(
                    url = "https://linux.do/uploads/default/original/1X/fire.png",
                    altText = "fire",
                    width = 1080u,
                    height = 1920u,
                ),
            ),
        )

        val content = FireRenderBlockBuilder.build(document)
        val blocks = FireRichTextBlockBuilder.build(content)

        assertEquals("caption\n\nfire", content.plainText)
        assertEquals(2, blocks.size)
        assertTrue(blocks[0] is FireRichTextBlock.Text)
        assertEquals("https://linux.do/uploads/default/original/1X/fire.png", (blocks[1] as FireRichTextBlock.Image).image.url)
    }

    @Test
    fun build_preservesDetailsBodyWhenSplittingAroundImage() {
        val blocks = FireRichTextBlockBuilder.build(
            listOf(
                FireRichTextNode.Details(
                    summary = listOf(FireRichTextNode.Text("Summary")),
                    children = listOf(
                        FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("before"))),
                        FireRichTextNode.Image(
                            src = "https://linux.do/uploads/details.png",
                            alt = null,
                            width = 1080f,
                            height = 1920f,
                        ),
                        FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("after"))),
                    ),
                ),
            ),
        )

        assertEquals(3, blocks.size)
        val beforeDetails = ((blocks[0] as FireRichTextBlock.Text).nodes.single() as FireRichTextNode.Details)
        val afterDetails = ((blocks[2] as FireRichTextBlock.Text).nodes.single() as FireRichTextNode.Details)

        assertEquals(listOf(FireRichTextNode.Text("Summary")), beforeDetails.summary)
        assertEquals(listOf(FireRichTextNode.Text("Summary")), afterDetails.summary)
        assertEquals(listOf(FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("before")))), beforeDetails.children)
        assertEquals(listOf(FireRichTextNode.Paragraph(listOf(FireRichTextNode.Text("after")))), afterDetails.children)
        assertEquals("https://linux.do/uploads/details.png", (blocks[1] as FireRichTextBlock.Image).image.url)
    }
}
