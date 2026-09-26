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

    func setSolutionAccepted(_ post: TopicPostState, accepted: Bool) {
        Task { @MainActor in
            do {
                try await topicDetailStore.acceptSolution(
                    topicId: topic.id,
                    postId: post.id,
                    accepted: accepted
                )
                modalRouter.presentNotice(
                    message: accepted ? "已采纳为解决方案。" : "已取消采纳。"
                )
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
