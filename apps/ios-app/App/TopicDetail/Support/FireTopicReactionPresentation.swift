import Foundation

struct FireReactionOption: Identifiable, Hashable, Sendable {
    let id: String
    let symbol: String
    let label: String
}
extension FireTopicPresentation {
    static func enabledReactionOptions(from reactionIDs: [String]) -> [FireReactionOption] {
        reactionOptions(from: reactionIDs, currentReactionID: nil)
    }
    static let quickReactionPreferenceIDs = [
        "heart", "+1", "laughing", "open_mouth", "cry", "clap", "tada", "confused",
    ]
    static func quickReactionOptions(from reactionIDs: [String]) -> [FireReactionOption] {
        let enabled = reactionIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        // Prefer site-enabled reactions first (preserve server order), then fill with commons.
        var ordered: [String] = []
        for id in enabled {
            if !ordered.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                ordered.append(id)
            }
        }
        for id in quickReactionPreferenceIDs {
            if !ordered.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) {
                ordered.append(id)
            }
        }
        if ordered.isEmpty {
            ordered = quickReactionPreferenceIDs
        }
        return Array(ordered.prefix(8)).map(reactionOption(for:))
    }
    static func reactionOptions(
        from reactionIDs: [String],
        currentReactionID: String?
    ) -> [FireReactionOption] {
        var ids = reactionIDs.isEmpty ? ["heart"] : reactionIDs
        if let currentReactionID = currentReactionID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentReactionID.isEmpty {
            ids.append(currentReactionID)
        }
        return ids.reduce(into: [FireReactionOption]()) { result, reactionID in
            let trimmedReactionID = reactionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedReactionID.isEmpty,
                  !result.contains(where: { $0.id.caseInsensitiveCompare(trimmedReactionID) == .orderedSame }) else {
                return
            }
            result.append(reactionOption(for: trimmedReactionID))
        }
    }
    static func filterReactionOptions(
        _ options: [FireReactionOption],
        query: String
    ) -> [FireReactionOption] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return options }
        return options.filter { option in
            option.id.lowercased().contains(needle)
                || option.label.lowercased().contains(needle)
                || option.symbol.contains(needle)
        }
    }
    static func reactionOption(for reactionID: String) -> FireReactionOption {
        let normalized = reactionID.lowercased()
        let mapping: [String: (String, String)] = [
            "heart": ("❤️", "点赞"),
            "+1": ("👍", "赞同"),
            "-1": ("👎", "反对"),
            "thumbsup": ("👍", "赞同"),
            "laughing": ("😆", "笑哭"),
            "open_mouth": ("😮", "惊讶"),
            "cry": ("😢", "难过"),
            "angry": ("😡", "生气"),
            "confused": ("😕", "困惑"),
            "clap": ("👏", "鼓掌"),
            "tada": ("🎉", "庆祝"),
        ]
        let fallbackLabel = normalized.replacingOccurrences(of: "_", with: " ")
        let (symbol, label) = mapping[normalized] ?? ("🙂", fallbackLabel)
        return FireReactionOption(id: reactionID, symbol: symbol, label: label)
    }
}
