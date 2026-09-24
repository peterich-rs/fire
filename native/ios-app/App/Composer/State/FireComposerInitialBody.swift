import Foundation

enum FireComposerInitialBody {
    static func merge(
        initialBody: String,
        currentBody: String,
        preferredSelectionLocation: Int? = nil
    ) -> FireMarkdownInsertionResult {
        let initialLength = (initialBody as NSString).length
        let preferredSelection = min(max(preferredSelectionLocation ?? initialLength, 0), initialLength)
        guard !initialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: (currentBody as NSString).length, length: 0)
            )
        }

        let currentSource = currentBody as NSString
        let exactRange = currentSource.range(of: initialBody)
        if exactRange.location != NSNotFound {
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: exactRange.location + preferredSelection, length: 0)
            )
        }

        let trimmedInitial = initialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = currentSource.range(of: trimmedInitial)
        if trimmedRange.location != NSNotFound {
            let trimmedSelection = min(preferredSelection, (trimmedInitial as NSString).length)
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: trimmedRange.location + trimmedSelection, length: 0)
            )
        }

        guard !currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FireMarkdownInsertionResult(
                text: initialBody,
                selectedRange: NSRange(location: preferredSelection, length: 0)
            )
        }

        let separator = initialBody.hasSuffix("\n\n") || currentBody.hasPrefix("\n") ? "" : "\n\n"
        return FireMarkdownInsertionResult(
            text: initialBody + separator + currentBody,
            selectedRange: NSRange(location: preferredSelection, length: 0)
        )
    }
}
