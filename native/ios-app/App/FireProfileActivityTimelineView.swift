import SwiftUI
import UIKit

struct FireProfileActivityTimelineView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var profileViewModel: FireProfileViewModel
    @State private var copiedActionsError = false

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
                                        .onAppear {
                                            if item.index >= max(profileViewModel.actions.count - 3, 0) {
                                                profileViewModel.loadActions(reset: false)
                                            }
                                        }
                                }
                            .padding(.vertical, 20)
                        Spacer()
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
        .background(FireTheme.canvasTop)
        .navigationTitle("全部动态")
        .navigationBarTitleDisplayMode(.inline)
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
        if let row = topicRow(for: action) {
            NavigationLink {
                FireTopicDetailView(
                    viewModel: viewModel,
                    row: row,
                    scrollToPostNumber: action.postNumber
                )
            } label: {
                FireProfileActivityRow(action: action)
            }
            .buttonStyle(.plain)
        } else {
            FireProfileActivityRow(action: action)
        }
    }

    private func topicRow(for action: UserActionState) -> FireTopicRowPresentation? {
        guard let topicId = action.topicId else {
            return nil
        }

        let resolvedSlug = {
            let trimmed = action.slug?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? "topic-\(topicId)" : trimmed
        }()

        return .stub(
            topicId: topicId,
            title: action.title?.ifEmpty("话题 #\(topicId)") ?? "话题 #\(topicId)",
            slug: resolvedSlug,
            categoryId: action.categoryId
        )
    }
}
