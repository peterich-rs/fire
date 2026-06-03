import SwiftUI

struct FireAppRouteDestinationView: View {
    let viewModel: FireAppViewModel
    let route: FireAppRoute

    var body: some View {
        switch route {
        case .topic(let payload):
            // Active path: UIKit controller host.
            // FireTopicDetailView is retained as a file but is no longer on
            // the active route path.
            FireTopicDetailControllerHost(
                viewModel: viewModel,
                row: payload.row,
                scrollToPostNumber: payload.postNumber
            )
        case .profile(let username):
            FirePublicProfileView(viewModel: viewModel, username: username)
        case .badge(let badgeID, _):
            FireBadgeDetailView(viewModel: viewModel, badgeID: badgeID)
        }
    }
}
