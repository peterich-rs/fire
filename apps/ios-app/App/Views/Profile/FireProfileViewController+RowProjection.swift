import Combine
import SnapKit
import SwiftUI
import UIKit

@MainActor
extension FireProfileViewController {
    var displayUsername: String {
        profileViewModel.currentUsername ?? appViewModel.session.profileDisplayName
    }

    var displayName: String {
        let trimmed = profileViewModel.profile?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? displayUsername : trimmed
    }

    var canLogout: Bool {
        appViewModel.session.hasLoginSession || appViewModel.session.readiness.canReadAuthenticatedApi
    }

    func value(for social: SocialRow) -> String {
        switch social {
        case .following:
            return FireProfileFormat.number(profileViewModel.profile?.totalFollowing ?? 0)
        case .followers:
            return FireProfileFormat.number(profileViewModel.profile?.totalFollowers ?? 0)
        }
    }

    func value(for content: ContentRow) -> String? {
        switch content {
        case .bookmarks:
            let count = profileViewModel.summary?.stats.bookmarkCount ?? 0
            return "\(FireProfileFormat.number(count))条"
        case .badges:
            let count = UInt32(profileViewModel.summary?.badges.count ?? 0)
            return "\(FireProfileFormat.number(count))枚"
        case .activity, .history, .drafts, .messages:
            return nil
        }
    }
}
