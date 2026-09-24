import Foundation

func shouldRestorePrivateMessageDraft(
    explicitRecipients: [String],
    draftRecipients: [String]
) -> Bool {
    let normalizedExplicitRecipients = normalizedPrivateMessageRecipients(explicitRecipients)
    guard !normalizedExplicitRecipients.isEmpty else {
        return true
    }
    return normalizedPrivateMessageRecipients(draftRecipients) == normalizedExplicitRecipients
}

func normalizedPrivateMessageRecipients(_ recipients: [String]) -> [String] {
    var normalized: [String] = []

    for recipient in recipients {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        let stableRecipient = trimmed.lowercased()
        if normalized.contains(stableRecipient) {
            continue
        }
        normalized.append(stableRecipient)
    }

    return normalized.sorted()
}

func extractMarkdownImages(from text: String) -> [FireComposerMarkdownImage] {
    guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") else {
        return []
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges >= 3 else { return nil }
        let nsText = text as NSString
        let altText = match.range(at: 1).location != NSNotFound
            ? nsText.substring(with: match.range(at: 1)).split(separator: "|").first.map(String.init)
            : nil
        let urlString = nsText.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return nil }
        return FireComposerMarkdownImage(urlString: urlString, altText: altText)
    }
}
