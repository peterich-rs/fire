import UIKit

@MainActor
extension FireTopicDetailViewController {
    func submitPollVote(
        for post: TopicPostState,
        poll: PollState,
        options: [String]
    ) {
        Task { @MainActor in
            do {
                _ = try await viewModel.topicInteraction.votePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    options: options,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }

    func removePollVote(for post: TopicPostState, poll: PollState) {
        Task { @MainActor in
            do {
                _ = try await viewModel.topicInteraction.unvotePoll(
                    topicID: topic.id,
                    postID: post.id,
                    pollName: poll.name,
                    recoveryOriginURL: topicCloudflareRecoveryURL
                )
            } catch {
                modalRouter.presentNotice(message: error.localizedDescription)
            }
        }
    }
}
