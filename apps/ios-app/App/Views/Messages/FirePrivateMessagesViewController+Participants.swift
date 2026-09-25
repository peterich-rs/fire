import Combine
import SwiftUI
import UIKit

@MainActor
extension FirePrivateMessagesViewController {
    var currentUsername: String? {
        appViewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var usersByID: [UInt64: TopicUserState] {
        mailboxViewModel.displayedUsers.reduce(into: [:]) { partialResult, user in
            partialResult[user.id] = user
        }
    }

    func resolvedParticipants(for topic: TopicSummaryState) -> [TopicParticipantState] {
        var merged: [TopicParticipantState] = []
        for participant in topic.participants {
            let resolvedUser = usersByID[participant.userId]
            let resolved = TopicParticipantState(
                userId: participant.userId,
                username: participant.username ?? resolvedUser?.username,
                name: participant.name,
                avatarTemplate: participant.avatarTemplate ?? resolvedUser?.avatarTemplate
            )
            let stableName = resolved.username?.lowercased() ?? "id:\(resolved.userId)"
            if merged.contains(where: {
                ($0.username?.lowercased() ?? "id:\($0.userId)") == stableName
            }) {
                continue
            }
            if let currentUsername, resolved.username?.caseInsensitiveCompare(currentUsername) == .orderedSame {
                continue
            }
            merged.append(resolved)
        }
        return merged
    }
}
