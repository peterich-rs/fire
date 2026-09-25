import Foundation
enum FireTopicPresentation {
    static func isPrivateMessageArchetype(_ archetype: String?) -> Bool {
        let trimmed = archetype?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return false
        }
        return trimmed.caseInsensitiveCompare("private_message") == .orderedSame
    }
}
