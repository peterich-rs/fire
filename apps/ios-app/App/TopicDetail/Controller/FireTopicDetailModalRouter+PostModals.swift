import SwiftUI
import UIKit

@MainActor
extension FireTopicDetailModalRouter {
    func presentFlagSheet(
        topicID: UInt64,
        context: FirePostManagementContext,
        onSubmitted: @escaping @MainActor (String) -> Void
    ) {
        let rootView = FireTopicDetailFlagSheetHost(
            store: topicDetailStore,
            topicID: topicID,
            context: context,
            onSubmitted: onSubmitted
        )
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentTopicVoters(_ voters: [VotedUserState], isLoading: Bool) {
        let rootView = NavigationStack {
            FireTopicVotersSheet(voters: voters, isLoading: isLoading)
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentReactionPicker(
        post: TopicPostState,
        options: [FireReactionOption],
        onSelectReaction: @escaping @MainActor (String) -> Void,
        onShowUsers: @escaping @MainActor (String) -> Void
    ) {
        let rootView = NavigationStack {
            FirePostReactionPickerSheet(
                post: post,
                options: options,
                onSelectReaction: { [weak self] reactionID in
                    self?.viewController?.dismiss(animated: true) {
                        Task { @MainActor in
                            onSelectReaction(reactionID)
                        }
                    }
                },
                onShowUsers: { [weak self] reactionID in
                    self?.viewController?.dismiss(animated: true) {
                        Task { @MainActor in
                            onShowUsers(reactionID)
                        }
                    }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentReactionUsers(
        groups: [ReactionUsersGroupState],
        reactionID: String?
    ) {
        let rootView = NavigationStack {
            FireReactionUsersSheet(groups: groups, reactionID: reactionID)
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentPostReplies(
        topicID: UInt64,
        context: FirePostReplyContext,
        baseURLString: String,
        onJumpToPost: @escaping (UInt32) -> Void
    ) {
        let rootView = NavigationStack {
            FireTopicDetailPostRepliesHost(
                store: topicDetailStore,
                topicID: topicID,
                context: context,
                baseURLString: baseURLString,
                onJumpToPost: { [weak self] postNumber in
                    self?.viewController?.dismiss(animated: true) {
                        onJumpToPost(postNumber)
                    }
                }
            )
        }
        presentSheetController(UIHostingController(rootView: rootView))
    }

    func presentSheetController(_ controller: UIViewController) {
        if controller.view.backgroundColor == nil || controller.view.backgroundColor == .systemBackground {
            controller.view.backgroundColor = FireTheme.uiCanvas
        }
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        viewController?.present(controller, animated: true)
    }
}
