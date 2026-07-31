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
    let topicDetailStore: FireTopicDetailStore
    let topicRoutePresenter: FireTopicRoutePresenter

    init(
        viewModel: FireAppViewModel,
        username: String,
        topicDetailStore: FireTopicDetailStore,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.viewModel = viewModel
        self.username = username
        self.topicDetailStore = topicDetailStore
        self.topicRoutePresenter = topicRoutePresenter
    }

    /// Environment-driven entry: allocates a scoped detail store for nested topic pushes.
    init(
        viewModel: FireAppViewModel,
        username: String,
        topicRoutePresenter: FireTopicRoutePresenter
    ) {
        self.viewModel = viewModel
        self.username = username
        self.topicDetailStore = FireTopicDetailStore(appViewModel: viewModel)
        self.topicRoutePresenter = topicRoutePresenter
    }

    func makeUIViewController(context: Context) -> FirePublicProfileViewController {
        // Prefer injected presenter when it has real capability; otherwise use a
        // stack-aware secondary presenter so `.local` environment defaults cannot
        // leave "最近动态" taps as silent selection animations.
        let preferred: FireTopicRoutePresenter
        if topicRoutePresenter.isLocalNoOp {
            preferred = FireAppRouteControllerFactory.makeStackAwareTopicRoutePresenter(
                viewModel: viewModel,
                topicDetailStore: topicDetailStore,
                navigationControllerProvider: {
                    FireRootCoordinator.activeSecondaryNavigationController
                }
            )
        } else {
            preferred = topicRoutePresenter
        }

        return FireAppRouteControllerFactory.makePublicProfileViewController(
            viewModel: viewModel,
            username: username,
            topicDetailStore: topicDetailStore,
            preferredPresenter: preferred
        )
    }

    func updateUIViewController(_ uiViewController: FirePublicProfileViewController, context: Context) {}
}
