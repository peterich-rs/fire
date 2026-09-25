package com.fire.app.ui.composer

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import com.fire.app.R
import com.fire.app.session.FireSessionStore
import uniffi.fire_uniffi_topics.UploadImageRequestState
import uniffi.fire_uniffi_topics.UploadResultState

suspend fun uploadImageMarkdown(
    context: Context,
    sessionStore: FireSessionStore,
    uri: Uri,
): String {
    val resolver = context.contentResolver
    val bytes = resolver.openInputStream(uri)?.use { it.readBytes() }
        ?: error(context.getString(R.string.composer_upload_error))
    val mimeType = resolver.getType(uri)
    val fileName = displayName(context, uri) ?: "image-${System.currentTimeMillis()}"
    val result = sessionStore.uploadImage(
        UploadImageRequestState(
            fileName = fileName,
            mimeType = mimeType,
            bytes = bytes,
        ),
    )
    return markdownForUpload(result)
}

private fun markdownForUpload(result: UploadResultState): String {
    val alt = result.originalFilename?.takeIf { it.isNotBlank() } ?: "image"
    val width = result.thumbnailWidth ?: result.width
    val height = result.thumbnailHeight ?: result.height
    return if (width != null && height != null) {
        "![$alt|${width}x$height](${result.shortUrl})"
    } else {
        "![$alt](${result.shortUrl})"
    }
}

private fun displayName(context: Context, uri: Uri): String? {
    return context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) cursor.getString(index) else null
        }
}
