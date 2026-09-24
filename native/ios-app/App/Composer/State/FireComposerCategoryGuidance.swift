import Foundation

enum FireComposerCategoryGuidance {
    static func categorySheetSummary(for category: FireTopicCategoryPresentation) -> String? {
        var parts: [String] = []

        let minimumRequiredTags = Int(category.minimumRequiredTags)
        if minimumRequiredTags > 0 {
            parts.append("至少 \(minimumRequiredTags) 个标签")
        }

        for group in category.requiredTagGroups.prefix(2) {
            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                parts.append("标签组至少 \(group.minCount) 个")
            } else {
                parts.append("\(trimmedName) 至少 \(group.minCount) 个")
            }
        }

        let template = category.topicTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !template.isEmpty {
            parts.append("自带模板")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func suggestedTags(
        category: FireTopicCategoryPresentation?,
        topTags: [String],
        selectedTags: [String],
        limit: Int = 8
    ) -> [String] {
        let selected = Set(
            selectedTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let source = (category?.allowedTags.isEmpty == false)
            ? category?.allowedTags ?? []
            : topTags

        var suggestions: [String] = []
        var seen: Set<String> = []

        for candidate in source {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty else { continue }
            guard !selected.contains(normalized) else { continue }
            guard !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            suggestions.append(trimmed)

            if suggestions.count >= limit {
                break
            }
        }

        return suggestions
    }
}
