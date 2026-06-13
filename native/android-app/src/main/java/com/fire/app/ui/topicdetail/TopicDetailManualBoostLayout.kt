package com.fire.app.ui.topicdetail

internal data class TopicDetailManualBoostPlacement(
    val rowIndex: Int,
    val x: Int,
)

internal data class TopicDetailManualBoostLayoutResult(
    val placements: List<TopicDetailManualBoostPlacement>,
    val contentWidth: Int,
    val usedRowCount: Int,
)

internal object TopicDetailManualBoostLayout {
    fun placements(
        chipWidths: List<Int>,
        pageWidth: Int,
        rowCount: Int = 2,
        chipSpacing: Int,
    ): TopicDetailManualBoostLayoutResult {
        val resolvedPageWidth = pageWidth.coerceAtLeast(1)
        val resolvedRowCount = rowCount.coerceAtLeast(1)
        var pageStartX = 0
        var currentRowIndex = 0
        var cursorXByRow = MutableList(resolvedRowCount) { 0 }
        val placements = ArrayList<TopicDetailManualBoostPlacement>(chipWidths.size)

        chipWidths.forEach { rawChipWidth ->
            val chipWidth = rawChipWidth.coerceIn(1, resolvedPageWidth)
            var x = nextX(cursorXByRow[currentRowIndex], chipSpacing)
            if (x + chipWidth > resolvedPageWidth) {
                if (currentRowIndex + 1 < resolvedRowCount) {
                    currentRowIndex += 1
                    x = 0
                } else {
                    pageStartX += maxOf(cursorXByRow.maxOrNull() ?: 0, resolvedPageWidth) + chipSpacing
                    cursorXByRow = MutableList(resolvedRowCount) { 0 }
                    currentRowIndex = 0
                    x = 0
                }
            }

            placements += TopicDetailManualBoostPlacement(rowIndex = currentRowIndex, x = pageStartX + x)
            cursorXByRow[currentRowIndex] = x + chipWidth
        }

        val contentWidth = maxOf(pageStartX + (cursorXByRow.maxOrNull() ?: 0), resolvedPageWidth)
        val usedRowCount = placements.maxOfOrNull { it.rowIndex + 1 } ?: 0
        return TopicDetailManualBoostLayoutResult(
            placements = placements,
            contentWidth = contentWidth,
            usedRowCount = usedRowCount,
        )
    }

    private fun nextX(cursorX: Int, chipSpacing: Int): Int {
        return if (cursorX <= 0) 0 else cursorX + chipSpacing
    }
}
