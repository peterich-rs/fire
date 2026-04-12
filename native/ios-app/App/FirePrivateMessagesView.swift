import SwiftUI

@MainActor
final class FirePrivateMessagesViewModel: ObservableObject {
    @Published var selectedKind: TopicListKindState = .privateMessagesInbox
    @Published private(set) var rows: [TopicRowState] = []
    @Published private(set) var users: [TopicUserState] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private let appViewModel: FireAppViewModel
    private var nextPage: UInt32?
    private var hasMore = true

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func loadIfNeeded() async {
        guard rows.isEmpty, !isLoading else { return }
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func selectKind(_ kind: TopicListKindState) async {
        guard selectedKind != kind else { return }
        selectedKind = kind
        await load(reset: true)
    }

    func loadMoreIfNeeded(currentTopicID: UInt64) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard rows.last?.topic.id == currentTopicID else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let response = try await appViewModel.fetchPrivateMessages(
                kind: selectedKind,
                page: reset ? nil : nextPage
            )
            if reset {
                rows = response.rows
                users = response.users
            } else {
                let existingIDs = Set(rows.map(\.topic.id))
                rows.append(contentsOf: response.rows.filter { !existingIDs.contains($0.topic.id) })
                let existingUserIDs = Set(users.map(\.id))
                users.append(contentsOf: response.users.filter { !existingUserIDs.contains($0.id) })
            }
            nextPage = response.nextPage
            hasMore = response.nextPage != nil || response.moreTopicsUrl != nil
            errorMessage = nil
        } catch {
            if rows.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FirePrivateMessagesView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var mailboxViewModel: FirePrivateMessagesViewModel
    @State private var showComposer = false
    @State private var selectedRoute: FireAppRoute?

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _mailboxViewModel = StateObject(
            wrappedValue: FirePrivateMessagesViewModel(appViewModel: viewModel)
        )
    }

    private var currentUsername: String? {
        viewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usersByID: [UInt64: TopicUserState] {
        Dictionary(uniqueKeysWithValues: mailboxViewModel.users.map { ($0.id, $0) })
    }

    var body: some View {
        List {
            pickerSection

            if let errorMessage = mailboxViewModel.errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {},
                        onDismiss: {
                            mailboxViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if mailboxViewModel.isLoading && mailboxViewModel.rows.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else if mailboxViewModel.rows.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.2")
                            .font(.title2)
                            .foregroundStyle(FireTheme.subtleInk)
                        Text(mailboxViewModel.selectedKind == .privateMessagesInbox ? "私信收件箱为空" : "还没有已发送私信")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                        Text(mailboxViewModel.selectedKind == .privateMessagesInbox ? "新收到的私信会出现在这里。" : "你发出的私信会出现在这里。")
                            .font(.caption)
                            .foregroundStyle(FireTheme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section {
                    ForEach(mailboxViewModel.rows, id: \.topic.id) { row in
                        NavigationLink {
                            FireTopicDetailView(viewModel: viewModel, row: row)
                        } label: {
                            privateMessageRow(row)
                        }
                        .buttonStyle(.plain)
                        .task {
                            await mailboxViewModel.loadMoreIfNeeded(currentTopicID: row.topic.id)
                        }
                    }

                    if mailboxViewModel.isLoadingMore {
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
        .navigationTitle("私信")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedRoute) { route in
            FireAppRouteDestinationView(viewModel: viewModel, route: route)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showComposer = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .task {
            await mailboxViewModel.loadIfNeeded()
        }
        .refreshable {
            await mailboxViewModel.refresh()
        }
        .fullScreenCover(isPresented: $showComposer) {
            NavigationStack {
                FireComposerView(
                    viewModel: viewModel,
                    route: FireComposerRoute(kind: .privateMessage(recipients: [], title: nil)),
                    onPrivateMessageCreated: { topicID in
                        showComposer = false
                        selectedRoute = .topic(topicId: topicID, postNumber: nil)
                        Task { await mailboxViewModel.refresh() }
                    }
                )
            }
        }
    }

    private var pickerSection: some View {
        Section {
            Picker("邮箱", selection: Binding(
                get: { mailboxViewModel.selectedKind },
                set: { newValue in
                    Task { await mailboxViewModel.selectKind(newValue) }
                }
            )) {
                Text("收件箱").tag(TopicListKindState.privateMessagesInbox)
                Text("已发送").tag(TopicListKindState.privateMessagesSent)
            }
            .pickerStyle(.segmented)
        }
    }

    private func privateMessageRow(_ row: TopicRowState) -> some View {
        let participants = resolvedParticipants(for: row.topic)
        let avatar = participants.first?.avatarTemplate
        let username = participants.first?.username ?? participants.first?.name ?? "pm"
        let subtitle = participantSubtitle(for: participants)
        let excerpt = row.excerptText?.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(alignment: .top, spacing: 12) {
            FireAvatarView(
                avatarTemplate: avatar,
                username: username,
                size: 34
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.topic.title.ifEmpty("私信会话"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    FireStatusChip(label: "私信", tone: .accent)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(FireTheme.subtleInk)
                            .lineLimit(1)
                    }
                }

                if let excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    Text("\(row.topic.replyCount) 回复")
                        .font(.caption2)
                        .foregroundStyle(FireTheme.tertiaryInk)

                    if let timestamp = FireTopicPresentation.compactTimestamp(
                        unixMs: row.activityTimestampUnixMs
                    ) {
                        Text(timestamp)
                            .font(.caption2)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func resolvedParticipants(for topic: TopicSummaryState) -> [TopicParticipantState] {
        var merged: [TopicParticipantState] = []
        for participant in topic.participants {
            let resolvedUser = usersByID[participant.userId]
            let resolved = TopicParticipantState(
                userId: participant.userId,
                username: participant.username ?? resolvedUser?.username,
                name: participant.name,
                avatarTemplate: participant.avatarTemplate ?? resolvedUser?.avatarTemplate
            )
            let stableName = resolved.username?.lowercased() ?? "id:\(resolved.userId)"
            if merged.contains(where: {
                ($0.username?.lowercased() ?? "id:\($0.userId)") == stableName
            }) {
                continue
            }
            if let currentUsername, resolved.username?.caseInsensitiveCompare(currentUsername) == .orderedSame {
                continue
            }
            merged.append(resolved)
        }
        return merged
    }

    private func participantSubtitle(for participants: [TopicParticipantState]) -> String {
        let labels = participants.compactMap { participant in
            let preferred = (participant.name ?? "").ifEmpty(
                participant.username ?? "用户 \(participant.userId)"
            )
            let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !labels.isEmpty else {
            return "私信会话"
        }
        return labels.joined(separator: "、")
    }
}
