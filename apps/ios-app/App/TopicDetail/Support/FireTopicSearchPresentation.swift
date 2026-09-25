import Foundation

struct FireTopicSearchMatch: Equatable, Sendable {
    let postID: UInt64
    let postNumber: UInt32
}
extension FireTopicPresentation {
    static func topicSearchMatches(
        query: String,
        posts: [TopicPostState]
    ) -> [FireTopicSearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            return []
        }

        var seenPostIDs = Set<UInt64>()
        return posts
            .filter { seenPostIDs.insert($0.id).inserted }
            .filter { post in
                let plainText = post.presentation?.plainText() ?? ""
                return plainText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            .sorted { lhs, rhs in
                if lhs.postNumber == rhs.postNumber {
                    return lhs.id < rhs.id
                }
                return lhs.postNumber < rhs.postNumber
            }
            .map { FireTopicSearchMatch(postID: $0.id, postNumber: $0.postNumber) }
    }
}
