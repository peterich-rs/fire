import SwiftUI
import UIKit

@MainActor
final class FireFollowListViewModel: ObservableObject {
    enum Kind {
        case following
        case followers

        var title: String {
            switch self {
            case .following:
                return "关注"
            case .followers:
                return "粉丝"
            }
        }
    }

    @Published private(set) var users: [FollowUserState] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private let username: String
    private let kind: Kind

    init(appViewModel: FireAppViewModel, username: String, kind: Kind) {
        self.appViewModel = appViewModel
        self.username = username
        self.kind = kind
    }

    func load(force: Bool = false) async {
        guard force || (!isLoading && users.isEmpty) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            switch kind {
            case .following:
                users = try await appViewModel.fetchFollowing(username: username)
            case .followers:
                users = try await appViewModel.fetchFollowers(username: username)
            }
            errorMessage = nil
        } catch {
            if users.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FireFollowListView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String
    let kind: FireFollowListViewModel.Kind

    @StateObject private var listViewModel: FireFollowListViewModel

    init(viewModel: FireAppViewModel, username: String, kind: FireFollowListViewModel.Kind) {
        self.viewModel = viewModel
        self.username = username
        self.kind = kind
        _listViewModel = StateObject(
            wrappedValue: FireFollowListViewModel(
                appViewModel: viewModel,
                username: username,
                kind: kind
            )
        )
    }

    var body: some View {
        List {
            if let errorMessage = listViewModel.errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            listViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if listViewModel.isLoading && listViewModel.users.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else if listViewModel.users.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: kind == .following ? "person.2" : "person.2.fill")
                            .font(.title2)
                            .foregroundStyle(FireTheme.subtleInk)
                        Text("@\(username) 还没有\(kind.title)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section {
                    ForEach(listViewModel.users, id: \.id) { user in
                        NavigationLink {
                            FirePublicProfileView(viewModel: viewModel, username: user.username)
                        } label: {
                            HStack(spacing: 12) {
                                FireAvatarView(
                                    avatarTemplate: user.avatarTemplate,
                                    username: user.username,
                                    size: 42
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text((user.name ?? "").ifEmpty(user.username))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(FireTheme.ink)

                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(FireTheme.subtleInk)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasTop)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await listViewModel.load()
        }
        .refreshable {
            await listViewModel.load(force: true)
        }
    }
}
