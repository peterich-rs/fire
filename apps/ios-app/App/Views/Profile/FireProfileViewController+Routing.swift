import Combine
import SnapKit
import SwiftUI
import UIKit

@MainActor
extension FireProfileViewController {
    func openSettings() {
        FireMotionHaptics.selection()
        pushFullScreen(FireSettingsViewController(viewModel: appViewModel, canLogout: canLogout))
    }

    func openSocial(_ row: SocialRow) {
        FireMotionHaptics.selection()
        let kind: FireFollowListViewModel.Kind = row == .following ? .following : .followers
        appViewModel.topicRouteLogger()?.info(
            "profile tab open follow list kind=\(kind.title) username_length=\(displayUsername.count)"
        )
        // UIKit follow list owns profile + topic drill-down. Do not host SwiftUI
        // NavigationLink for this path — environment presenters were no-ops after
        // follow list → public profile → 最近动态.
        let controller = FireFollowListViewController(
            viewModel: appViewModel,
            topicDetailStore: topicDetailStore,
            username: displayUsername,
            kind: kind,
            topicRoutePresenter: topicRoutePresenter
        )
        pushFullScreen(controller)
    }

    func openContent(_ row: ContentRow) {
        FireMotionHaptics.selection()
        switch row {
        case .activity:
            pushHosting(
                FireProfileActivityTimelineView(
                    viewModel: appViewModel,
                    profileViewModel: profileViewModel,
                    topicDetailStore: topicDetailStore
                ),
                title: "我的动态"
            )
        case .bookmarks:
            pushFullScreen(
                FireBookmarksViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    username: displayUsername,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .history:
            pushFullScreen(
                FireReadHistoryViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .drafts:
            pushFullScreen(FireDraftsViewController(viewModel: appViewModel))
        case .messages:
            pushFullScreen(
                FirePrivateMessagesViewController(
                    viewModel: appViewModel,
                    topicDetailStore: topicDetailStore,
                    topicRoutePresenter: topicRoutePresenter
                )
            )
        case .badges:
            pushHosting(FireMyBadgesView(badges: profileViewModel.summary?.badges ?? []), title: "我的勋章")
        }
    }

    func openAccount(_ row: AccountRow) {
        FireMotionHaptics.selection()
        switch row {
        case .feedback:
            FireFeedbackPresenter.present(
                from: self,
                appViewModel: appViewModel,
                source: "profile"
            )
        case .invites:
            pushHosting(FireInviteLinksView(viewModel: appViewModel, username: displayUsername), title: "邀请链接")
        case .ldc:
            pushHosting(FireLDCView(viewModel: appViewModel), title: "LDC 信用")
        case .cdk:
            pushHosting(FireCDKView(viewModel: appViewModel), title: "CDK 连接")
        case .settings:
            openSettings()
        }
    }

    func pushFullScreen(_ controller: UIViewController) {
        controller.view.backgroundColor = controller.view.backgroundColor ?? FireTheme.uiCanvas
        FireRootCoordinator.presentSecondary(controller)
    }

    func pushHosting<Content: View>(_ root: Content, title: String? = nil) {
        let host = FireHosting.controller(
            rootView: root
                .environmentObject(navigationState)
                .environmentObject(topicDetailStore)
                .fireTopicRoutePresenter(topicRoutePresenter)
                .navigationBarTitleDisplayMode(.inline),
            title: title
        )
        pushFullScreen(host)
    }
}
