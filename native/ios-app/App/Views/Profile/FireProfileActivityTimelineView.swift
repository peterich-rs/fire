import SwiftUI
import UIKit

struct FireProfileActivityTimelineView: View {
    @Environment(\.fireTopicRoutePresenter) private var topicRoutePresenter
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var profileViewModel: FireProfileViewModel
    /// Shared with the parent when available; otherwise a scoped store for residual SwiftUI hosts.
    private let topicDetailStore: FireTopicDetailStore
    @State private var copiedActionsError = false
    @State private var selectedRoute: FireAppRoute?

    init(
        viewModel: FireAppViewModel,
        profileViewModel: FireProfileViewModel,
        topicDetailStore: FireTopicDetailStore? = nil
    ) {
        self.viewModel = viewModel
        self.profileViewModel = profileViewModel
        self.topicDetailStore = topicDetailStore ?? FireTopicDetailStore(appViewModel: viewModel)
    }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage ?? profileViewModel.errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            profileViewModel.errorMessage = nil
                            viewModel.dismissError()
                        }
                    )
                }
            }

            Section {
                if let errorMessage = profileViewModel.actionsErrorMessage,
                   profileViewModel.hasLoadedActionsOnce {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: copiedActionsError,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                            copiedActionsError = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.2))
                                copiedActionsError = false
                            }
                        },
                        onDismiss: {
                            profileViewModel.actionsErrorMessage = nil
                        }
                    )
                }

                if !profileViewModel.hasLoadedActionsOnce {
                    if let errorMessage = profileViewModel.actionsErrorMessage {
                        FireBlockingErrorState(
                            title: "动态加载失败",
                            message: errorMessage,
                            onRetry: {
                                profileViewModel.loadActions(reset: true)
                            }
                        )
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 20)
                            Spacer()
                        }
                    }
                } else if profileViewModel.actions.isEmpty {
                    Text("暂无动态")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.tertiaryInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    ForEach(
                        fireIdentifiedValues(profileViewModel.actions) { $0.fireStableBaseID }
                    ) { item in
                        activityRow(item.value)
                            .fireRespectingReduceMotion { content, reduceMotion in
                                content.transition(.fireListItem(reduceMotion: reduceMotion))
                            }
                            .onAppear {
                                if item.index >= max(profileViewModel.actions.count - 3, 0) {
                                    profileViewModel.loadActions(reset: false)
                                }
                            }
                    }

                    if profileViewModel.isLoadingActions {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasMid)
        .fireRespectingReduceMotion { content, reduceMotion in
            content.animation(
                FireMotionTokens.animation(for: .standard, reduceMotion: reduceMotion),
                value: profileViewModel.actions.map(\.fireStableBaseID)
            )
        }
        .navigationTitle("我的动态")
        .navigationBarTitleDisplayMode(.inline)
        .fireNavigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
        }
        .refreshable {
            await profileViewModel.refreshAll()
        }
        .task {
            if profileViewModel.actions.isEmpty && !profileViewModel.isLoadingActions {
                profileViewModel.loadActions(reset: true)
            }
        }
    }

    @ViewBuilder
    private func activityRow(_ action: UserActionState) -> some View {
        if let route = FireAppRoute.topic(action: action) {
            Button {
                presentRoute(route)
            } label: {
                FireProfileActivityRow(action: action)
            }
            .buttonStyle(.plain)
        } else {
            FireProfileActivityRow(action: action)
        }
    }

    private func presentRoute(_ route: FireAppRoute) {
        // Shared cascade: injected presenter → active secondary nav → root secondary.
        // Keeps timeline usable when the environment presenter is the no-op `.local`.
        let outcome = FireAppRouteControllerFactory.present(
            route,
            preferredPresenter: topicRoutePresenter,
            navigationControllerProvider: {
                FireRootCoordinator.activeSecondaryNavigationController
            },
            viewModel: viewModel,
            topicDetailStore: topicDetailStore
        )
        if outcome != .unhandled {
            return
        }
        selectedRoute = route
    }
}
