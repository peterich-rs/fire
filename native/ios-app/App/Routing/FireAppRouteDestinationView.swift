import SwiftUI

struct FireAppRouteDestinationView: View {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter

    let viewModel: FireAppViewModel
    let route: FireAppRoute

    var body: some View {
        switch route {
        case .topic(let payload):
            // Topic detail is owned by the UIKit + Texture controller path.
            FireTopicDetailControllerHost(
                viewModel: viewModel,
                row: payload.row,
                scrollToPostNumber: payload.postNumber
            )
        case .profile(let username):
            FirePublicProfileControllerHost(
                viewModel: viewModel,
                username: username,
                topicRoutePresenter: topicRoutePresenter
            )
            .ignoresSafeArea()
        case .profileTab, .notifications, .search:
            EmptyView()
        case .badge(let badgeID, _):
            FireBadgeDetailView(viewModel: viewModel, badgeID: badgeID)
        }
    }
}

struct FirePublicProfileControllerHost: UIViewControllerRepresentable {
    let viewModel: FireAppViewModel
    let username: String
    let topicRoutePresenter: FireTopicRoutePresenter

    func makeUIViewController(context: Context) -> FirePublicProfileViewController {
        // Nested SwiftUI navigation creates a scoped detail store for topic pushes.
        let topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)
        return FirePublicProfileViewController(
            viewModel: viewModel,
            username: username,
            topicDetailStore: topicDetailStore,
            topicRoutePresenter: topicRoutePresenter
        )
    }

    func updateUIViewController(_ uiViewController: FirePublicProfileViewController, context: Context) {}
}
