import SwiftUI

struct FireAppRouteDestinationView: View {
    let viewModel: FireAppViewModel
    let route: FireAppRoute

    var body: some View {
        switch route {
        case .topic(let payload):
            FireTopicDetailView(
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
