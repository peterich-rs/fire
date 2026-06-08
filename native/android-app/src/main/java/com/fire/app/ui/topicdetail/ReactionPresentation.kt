package com.fire.app.ui.topicdetail

data class ReactionOption(
    val id: String,
    val symbol: String,
    val label: String,
)

object ReactionPresentation {
    const val HEART_ID = "heart"

    fun enabledOptions(reactionIds: List<String>): List<ReactionOption> {
        val ids = reactionIds.ifEmpty { listOf(HEART_ID) }
        val seen = LinkedHashSet<String>()
        return ids.mapNotNull { rawId ->
            val id = rawId.trim()
            if (id.isBlank() || !seen.add(id)) {
                null
            } else {
                optionFor(id)
            }
        }
    }

    fun customOptions(
        reactionIds: List<String>,
        currentReactionId: String?,
    ): List<ReactionOption> {
        val options = fullOptions(
            reactionIds = reactionIds,
            currentReactionId = currentReactionId,
        )
            .filterNot { it.id.equals(HEART_ID, ignoreCase = true) }
        return options
    }

    fun fullOptions(
        reactionIds: List<String>,
        currentReactionId: String?,
    ): List<ReactionOption> {
        val options = enabledOptions(reactionIds).toMutableList()
        val currentCustomId = currentReactionId
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (currentCustomId != null && options.none { it.id.equals(currentCustomId, ignoreCase = true) }) {
            options.add(optionFor(currentCustomId))
        }
        return options
    }

    fun filteredOptions(options: List<ReactionOption>, query: String): List<ReactionOption> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return options
        return options.filter { option ->
            option.id.lowercase().contains(needle) ||
                option.label.lowercase().contains(needle) ||
                option.symbol.contains(needle)
        }
    }

    fun optionFor(reactionId: String): ReactionOption {
        val normalized = reactionId.lowercase()
        val (symbol, label) = when (normalized) {
            HEART_ID -> "❤️" to "点赞"
            "+1", "thumbsup" -> "👍" to "赞同"
            "-1" -> "👎" to "反对"
            "laughing" -> "😆" to "笑哭"
            "open_mouth" -> "😮" to "惊讶"
            "cry" -> "😢" to "难过"
            "angry" -> "😡" to "生气"
            "confused" -> "😕" to "困惑"
            "clap" -> "👏" to "鼓掌"
            "tada" -> "🎉" to "庆祝"
            else -> "🙂" to normalized.replace("_", " ")
        }
        return ReactionOption(id = reactionId, symbol = symbol, label = label)
    }
}
