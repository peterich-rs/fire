import Foundation

enum FireQuoteMarkdown {
    static func build(
        username: String,
        postNumber: UInt32,
        topicID: UInt64,
        plainText: String
    ) -> String? {
        let body = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return nil
        }

        let author = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "'")
            .ifEmpty("unknown")
        return "[quote=\"\(author), post:\(postNumber), topic:\(topicID)\"]\n" +
            body +
            "\n[/quote]\n\n"
    }
}
