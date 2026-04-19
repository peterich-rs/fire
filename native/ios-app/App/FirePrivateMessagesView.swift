import SwiftUI
import UIKit

@MainActor
final class FirePrivateMessagesViewModel: ObservableObject {
    typealias FetchPrivateMessages = @MainActor (
        TopicListKindState,
        UInt32?
    ) async throws -> TopicListState

    @Published var selectedKind: TopicListKindState = .privateMessagesInbox
    @Published private(set) var rows: [TopicRowState] = []
    @Published private(set) var users: [TopicUserState] = []
    @Published private(set) var renderedKind: TopicListKindState?
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private let fetchPrivateMessages: FetchPrivateMessages
    private var nextPage: UInt32?
    private var hasMore = true
    private var loadGeneration: UInt64 = 0

    init(appViewModel: FireAppViewModel) {
        self.fetchPrivateMessages = { kind, page in
            try await appViewModel.fetchPrivateMessages(kind: kind, page: page)
        }
    }

    init(fetchPrivateMessages: @escaping FetchPrivateMessages) {
        self.fetchPrivateMessages = fetchPrivateMessages
    }

    var hasResolvedCurrentKind: Bool {
        renderedKind == selectedKind
    }

    var displayedRows: [TopicRowState] {
        hasResolvedCurrentKind ? rows : []
    }

    var displayedUsers: [TopicUserState] {
        hasResolvedCurrentKind ? users : []
    }

    var currentKindDisplayState: FireScopedTopicListDisplayState {
        FireScopedTopicListDisplayState.resolve(
            hasResolvedCurrentScope: hasResolvedCurrentKind,
            hasRows: !displayedRows.isEmpty,
            errorMessage: errorMessage
        )
    }

    private func deduplicatedRows(_ rows: [TopicRowState]) -> [TopicRowState] {
        var seenTopicIDs = Set<UInt64>()
        return rows.filter { row in
            seenTopicIDs.insert(row.topic.id).inserted
        }
    }

    private func deduplicatedUsers(_ users: [TopicUserState]) -> [TopicUserState] {
        var seenUserIDs = Set<UInt64>()
        return users.filter { user in
            seenUserIDs.insert(user.id).inserted
        }
    }

    func loadIfNeeded() async {
        guard (!hasResolvedCurrentKind || rows.isEmpty), !isLoading else { return }
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
        guard hasResolvedCurrentKind else { return }
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard displayedRows.last?.topic.id == currentTopicID else { return }
        await load(reset: false)
    }

    private func load(reset: Bool) async {
        let requestKind = selectedKind
        let requestPage = reset ? nil : nextPage
        loadGeneration &+= 1
        let generation = loadGeneration

        if reset {
            isLoading = true
            isLoadingMore = false
            nextPage = nil
            hasMore = false
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let response = try await fetchPrivateMessages(requestKind, requestPage)
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }

            let uniqueRows = deduplicatedRows(response.rows)
            let uniqueUsers = deduplicatedUsers(response.users)
            let freshRows: [TopicRowState]
            let freshUsers: [TopicUserState]

            if reset {
                rows = uniqueRows
                users = uniqueUsers
                freshRows = uniqueRows
                freshUsers = uniqueUsers
            } else {
                let existingIDs = Set(rows.map(\.topic.id))
                freshRows = uniqueRows.filter { !existingIDs.contains($0.topic.id) }
                rows.append(contentsOf: freshRows)
                let existingUserIDs = Set(users.map(\.id))
                freshUsers = uniqueUsers.filter { !existingUserIDs.contains($0.id) }
                users.append(contentsOf: freshUsers)
            }

            let resolvedNextPage: UInt32? = {
                guard let candidate = response.nextPage else {
                    return nil
                }
                guard let requestPage else {
                    return candidate
                }
                return candidate > requestPage ? candidate : nil
            }()

            let receivedFreshContent = !freshRows.isEmpty || !freshUsers.isEmpty
            nextPage = resolvedNextPage
            hasMore = resolvedNextPage != nil && (reset || receivedFreshContent)
            renderedKind = requestKind
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            guard generation == loadGeneration, requestKind == selectedKind else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }
}

struct FirePrivateMessagesView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var mailboxViewModel: FirePrivateMessagesViewModel
    @State private var showComposer = false
    @State private var selectedRoute: FireAppRoute?
    @State private var copiedErrorMessage = false
    @State private var composerNotice: String?

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _mailboxViewModel = StateObject(
            wrappedValue: FirePrivateMessagesViewModel(appViewModel: viewModel)
        )
    }

    private var displayState: FireScopedTopicListDisplayState {
        mailboxViewModel.currentKindDisplayState
    }

    private var currentUsername: String? {
        viewModel.session.bootstrap.currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usersByID: [UInt64: TopicUserState] {
        mailboxViewModel.displayedUsers.reduce(into: [:]) { partialResult, user in
            partialResult[user.id] = user
        }
    }

    private var nonBlockingErrorMessage: String? {
        switch displayState {
        case .empty(let message), .content(let message):
            return message
        case .loading, .blockingError:
            return nil
        }
    }

    var body: some View {
        List {
            pickerSection

            if let errorMessage = nonBlockingErrorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: copiedErrorMessage,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                            copiedErrorMessage = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.2))
                                copiedErrorMessage = false
                            }
                        },
                        onDismiss: {
                            mailboxViewModel.errorMessage = nil
                        }
                    )
                }
            }

            switch displayState {
            case .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            case .blockingError(let errorMessage):
                Section {
                    FireBlockingErrorState(
                        title: "私信加载失败",
                        message: errorMessage,
                        onRetry: {
                            Task {
                                await mailboxViewModel.refresh()
                            }
                        }
                    )
                }
            case .empty:
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

                        Button("重新加载") {
                            Task {
                                await mailboxViewModel.refresh()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(FireTheme.accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            case .content:
                Section {
                    if mailboxViewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    }

                    ForEach(mailboxViewModel.displayedRows, id: \.topic.id) { row in
                        Button {
                            selectedRoute = .topic(row: row)
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
                    onPrivateMessageCreated: { topicID, title in
                        showComposer = false
                        selectedRoute = .topic(
                            topicId: topicID,
                            postNumber: nil,
                            preview: FireTopicRoutePreview.fromMetadata(title: title, slug: nil)
                        )
                        Task { await mailboxViewModel.refresh() }
                    },
                    onSubmissionNotice: { message in
                        if message.contains("等待审核") {
                            composerNotice = message
                        }
                    }
                )
            }
        }
        .alert("提示", isPresented: Binding(
            get: { composerNotice != nil },
            set: { presenting in
                if !presenting {
                    composerNotice = nil
                }
            }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(composerNotice ?? "")
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
