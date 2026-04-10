import SwiftUI
import UIKit

struct FireProfileActivityTimelineView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @ObservedObject var profileViewModel: FireProfileViewModel

    var body: some View {
        List {
            if let errorMessage = profileViewModel.errorMessage ?? viewModel.errorMessage {
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
                Picker(
                    "动态筛选",
                    selection: Binding(
                        get: { profileViewModel.selectedTab },
                        set: { profileViewModel.selectTab($0) }
                    )
                ) {
                    ForEach(FireProfileViewModel.ProfileTab.allCases, id: \.self) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)
            }

            Section {
                if profileViewModel.actions.isEmpty, profileViewModel.isLoadingActions {
                    HStack {
                        Spacer()
                        ProgressView()
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
                    ForEach(Array(profileViewModel.actions.enumerated()), id: \.offset) { index, action in
                        activityRow(action)
                            .onAppear {
                                if index >= max(profileViewModel.actions.count - 3, 0) {
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
                FireProfileActivityRow(action: action, showsChevron: true)
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
