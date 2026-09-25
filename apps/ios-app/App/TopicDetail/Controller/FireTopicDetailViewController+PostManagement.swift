import UIKit

@MainActor
extension FireTopicDetailViewController {
    func confirmDelete(_ post: TopicPostState) {
        modalRouter.presentDeleteConfirmation(postNumber: post.postNumber) { [weak self] in
            self?.deletePost(
                FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
            )
        }
    }

    func deletePost(_ context: FirePostManagementContext) {
        Task { @MainActor in
            do {
                try await topicDetailStore.deletePost(
                    topicId: topic.id,
                    postId: context.postID
                )
                modalRouter.presentNotice(message: "已删除 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func recoverPost(_ post: TopicPostState) {
        let context = FirePostManagementContext(postID: post.id, postNumber: post.postNumber)
        Task { @MainActor in
            do {
                try await topicDetailStore.recoverPost(
                    topicId: topic.id,
                    postId: context.postID
                )
                modalRouter.presentNotice(message: "已恢复 #\(context.postNumber)。")
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }
}
