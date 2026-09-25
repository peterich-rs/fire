import Foundation

extension FireTopicPresentation {
    static func replyTargetPostNumber(
        for post: TopicPostState,
        preferredPostNumber: UInt32?
    ) -> UInt32? {
        preferredPostNumber ?? post.replyToPostNumber
    }
    static func replyContextLabel(
        for post: TopicPostState,
        preferredPostNumber: UInt32?
    ) -> String? {
        let targetPostNumber = replyTargetPostNumber(
            for: post,
            preferredPostNumber: preferredPostNumber
        )
        guard let targetPostNumber, targetPostNumber > 0 else {
            return nil
        }

        let canUseReplyUser = preferredPostNumber == nil
            || preferredPostNumber == post.replyToPostNumber
        if canUseReplyUser {
            let username = post.replyToUser?.username
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !username.isEmpty {
                return "回复 @\(username)"
            }
        }

        return "回复 #\(targetPostNumber)"
    }
    static func minimumReplyLength(from minPostLength: UInt32) -> Int {
        max(Int(minPostLength), 1)
    }
}
