import Foundation

@MainActor
extension FireTopicDetailViewController {
    func handleRichTextLink(_ url: URL) {
        timingTracker.recordInteraction()

        guard let route = FireRouteParser.parse(url: url) else {
            modalRouter.presentWebLink(url)
            return
        }

        switch route {
        case .profile(let username):
            modalRouter.presentProfile(username: username)
        case .topic(let payload):
            handleTopicLink(payload)
        case .badge:
            modalRouter.push(route: route)
        case .notifications, .profileTab, .search:
            break
        }
    }

    func handleTopicLink(_ payload: FireTopicRoutePayload) {
        if payload.topicId == topic.id {
            guard let postNumber = payload.postNumber else { return }
            openPostNumber(postNumber)
            return
        }
        modalRouter.push(route: .topic(payload: payload))
    }

    func openPostNumber(_ postNumber: UInt32) {
        guard postNumber > 0 else { return }
        Task {
            await loadTopicDetail(targetPostNumber: postNumber)
        }
    }
}
