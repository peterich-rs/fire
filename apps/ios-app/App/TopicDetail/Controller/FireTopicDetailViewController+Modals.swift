import UIKit

@MainActor
extension FireTopicDetailViewController {
    var topicBookmarkContext: FireBookmarkEditorContext {
        FireBookmarkEditorContext(
            bookmarkID: detailSnapshot?.chrome.bookmarkId,
            bookmarkableID: topic.id,
            bookmarkableType: "Topic",
            topicID: topic.id,
            postNumber: nil,
            title: displayedTopicTitle,
            initialName: detailSnapshot?.chrome.bookmarkName,
            initialReminderAt: detailSnapshot?.chrome.bookmarkReminderAt,
            allowsDelete: detailSnapshot?.chrome.bookmarkId != nil
        )
    }

    func postBookmarkContext(for post: TopicPostState) -> FireBookmarkEditorContext {
        let username = post.username.trimmingCharacters(in: .whitespacesAndNewlines)
        return FireBookmarkEditorContext(
            bookmarkID: post.bookmarkId,
            bookmarkableID: post.id,
            bookmarkableType: "Post",
            topicID: topic.id,
            postNumber: post.postNumber,
            title: username.isEmpty ? "#\(post.postNumber)" : "#\(post.postNumber) · \(username)",
            initialName: post.bookmarkName,
            initialReminderAt: post.bookmarkReminderAt,
            allowsDelete: post.bookmarkId != nil
        )
    }

    func presentTopicBookmarkEditor() {
        modalRouter.presentBookmarkEditor(
            context: topicBookmarkContext,
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { }
        )
    }

    func presentPostBookmarkEditor(_ post: TopicPostState) {
        modalRouter.presentBookmarkEditor(
            context: postBookmarkContext(for: post),
            recoveryOriginURL: topicCloudflareRecoveryURL,
            onReload: { }
        )
    }

    func presentPostEditor(_ post: TopicPostState) {
        modalRouter.presentPostEditor(
            topicID: topic.id,
            context: FirePostEditorContext(postID: post.id, postNumber: post.postNumber),
            onSaved: { [weak self] in
                guard let self else { return }
                _ = try? await self.topicDetailStore.prepareEdit(topicId: self.topic.id, postId: post.id)
            }
        )
    }

    func presentTopicEditor() {
        modalRouter.presentTopicEditor(
            topicID: topic.id,
            initialTitle: detailSnapshot?.chrome.title ?? topic.title,
            initialCategoryID: detailSnapshot?.chrome.categoryId ?? topic.categoryId,
            initialTags: detailSnapshot?.chrome.tags ?? row.tagNames,
            onSaved: { }
        )
    }

    func presentFlagSheet(_ post: TopicPostState) {
        modalRouter.presentFlagSheet(
            topicID: topic.id,
            context: FirePostManagementContext(
                postID: post.id,
                postNumber: post.postNumber,
                username: post.username
            ),
            onSubmitted: { [weak self] message in
                self?.modalRouter.presentNotice(message: message)
            }
        )
    }

    func updateTopicNotificationLevel(_ option: FireTopicNotificationLevelOption) {
        Task { @MainActor in
            do {
                try await viewModel.topicInteraction.setTopicNotificationLevel(
                    topicID: topic.id,
                    notificationLevel: option.rawValue,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
                try await topicDetailStore.setNotificationLevel(
                    topicId: topic.id,
                    level: Int32(option.rawValue)
                )
                FireUIKitToast.show(option.cycleToastMessage, style: .success, in: view)
            } catch {
                // Reconcile toolbar glyph if the optimistic cycle preview diverged.
                buildAndApplyChromeState()
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }
}
