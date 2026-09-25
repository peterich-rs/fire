import UIKit

@MainActor
extension FireTopicDetailViewController {
    func toggleTopicVote() async {
        let userVoted = detailSnapshot?.chrome.userVoted ?? false
        do {
            _ = try await viewModel.topicInteraction.voteTopic(
                topicID: topic.id,
                voted: !userVoted,
                recoveryOriginURL: topicCloudflareRecoveryURL
            )
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }

    func presentTopicVoters() async {
        do {
            let voters = try await viewModel.topicInteraction.fetchTopicVoters(topicID: topic.id)
            modalRouter.presentTopicVoters(voters, isLoading: false)
        } catch {
            modalRouter.presentNotice(message: error.localizedDescription)
        }
    }
}
