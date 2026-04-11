import SwiftUI
import UIKit

@MainActor
final class FireDraftsViewModel: ObservableObject {
    @Published private(set) var drafts: [DraftState] = []
    @Published private(set) var hasMore = true
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var errorMessage: String?

    private static let pageSize: UInt32 = 20
    private let appViewModel: FireAppViewModel

    init(appViewModel: FireAppViewModel) {
        self.appViewModel = appViewModel
    }

    func loadIfNeeded() async {
        guard drafts.isEmpty, !isLoading else { return }
        await load(reset: true)
    }

    func refresh() async {
        await load(reset: true)
    }

    func loadMoreIfNeeded(currentDraftKey: String) async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        guard drafts.last?.draftKey == currentDraftKey else { return }
        await load(reset: false)
    }

    func deleteDraft(_ draft: DraftState) async {
        do {
            try await appViewModel.deleteDraft(
                draftKey: draft.draftKey,
                sequence: draft.sequence
            )
            drafts.removeAll { $0.draftKey == draft.draftKey }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            let offset: UInt32? = reset ? 0 : UInt32(drafts.count)
            let response = try await appViewModel.fetchDrafts(
                offset: offset,
                limit: Self.pageSize
            )
            if reset {
                drafts = response.drafts
            } else {
                let existingKeys = Set(drafts.map(\.draftKey))
                drafts.append(contentsOf: response.drafts.filter { !existingKeys.contains($0.draftKey) })
            }
            hasMore = response.hasMore
            errorMessage = nil
        } catch {
            if drafts.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct FireDraftsView: View {
    @ObservedObject var viewModel: FireAppViewModel
    @StateObject private var draftsViewModel: FireDraftsViewModel
    @State private var unsupportedDraftMessage: String?

    init(viewModel: FireAppViewModel) {
        self.viewModel = viewModel
        _draftsViewModel = StateObject(
            wrappedValue: FireDraftsViewModel(appViewModel: viewModel)
        )
    }

    var body: some View {
        List {
            if let errorMessage = draftsViewModel.errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            draftsViewModel.errorMessage = nil
                        }
                    )
                }
            }

            if draftsViewModel.isLoading && draftsViewModel.drafts.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else if draftsViewModel.drafts.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.full")
                            .font(.title2)
                            .foregroundStyle(FireTheme.subtleInk)
                        Text("草稿箱是空的")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                        Text("这里会保留未发出的新话题和完整回复。")
                            .font(.caption)
                            .foregroundStyle(FireTheme.subtleInk)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                Section {
                    ForEach(draftsViewModel.drafts, id: \.draftKey) { draft in
                        if let route = composerRoute(for: draft) {
                            NavigationLink {
                                FireComposerView(
                                    viewModel: viewModel,
                                    route: route,
                                    onTopicCreated: { _ in
                                        Task { await draftsViewModel.refresh() }
                                    },
                                    onReplySubmitted: {
                                        Task { await draftsViewModel.refresh() }
                                    }
                                )
                            } label: {
                                draftRow(draft, supported: true)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await draftsViewModel.deleteDraft(draft) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .task {
                                await draftsViewModel.loadMoreIfNeeded(currentDraftKey: draft.draftKey)
                            }
                        } else {
                            Button {
                                unsupportedDraftMessage = "当前 beta 还不支持打开私信草稿。"
                            } label: {
                                draftRow(draft, supported: false)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await draftsViewModel.deleteDraft(draft) }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }

                    if draftsViewModel.isLoadingMore {
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
        .navigationTitle("草稿箱")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await draftsViewModel.loadIfNeeded()
        }
        .refreshable {
            await draftsViewModel.refresh()
        }
        .alert(
            "暂不支持",
            isPresented: Binding(
                get: { unsupportedDraftMessage != nil },
                set: { presenting in
                    if !presenting {
                        unsupportedDraftMessage = nil
                    }
                }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(unsupportedDraftMessage ?? "")
        }
    }

    private func composerRoute(for draft: DraftState) -> FireComposerRoute? {
        let key = draft.draftKey
        if key == "new_topic" {
            return FireComposerRoute(kind: .createTopic)
        }
        if key == "new_private_message" || draft.data.archetypeId == "private_message" {
            return nil
        }
        guard let topicID = draft.topicId else {
            return nil
        }
        let title = draft.title?.ifEmpty("话题 #\(topicID)") ?? "话题 #\(topicID)"
        return FireComposerRoute(
            kind: .advancedReply(
                topicID: topicID,
                topicTitle: title,
                categoryID: draft.data.categoryId,
                replyToPostNumber: draft.data.replyToPostNumber,
                replyToUsername: nil
            )
        )
    }

    private func draftRow(_ draft: DraftState, supported: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill((supported ? FireTheme.accent : FireTheme.subtleInk).opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: draftIcon(for: draft))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(supported ? FireTheme.accent : FireTheme.subtleInk)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(draftTitle(for: draft))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                        .lineLimit(2)

                    if !supported {
                        Text("暂不支持")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }

                    Spacer(minLength: 0)
                }

                if let excerpt = draftExcerpt(for: draft) {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(3)
                }

                HStack(spacing: 8) {
                    Text(draftKindLabel(for: draft))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(FireTheme.accent)

                    if let updatedAt = FireTopicPresentation.compactTimestamp(draft.updatedAt) {
                        Text(updatedAt)
                            .font(.caption2)
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func draftTitle(for draft: DraftState) -> String {
        if draft.draftKey == "new_topic" {
            return draft.title?.ifEmpty("未命名新话题") ?? "未命名新话题"
        }
        return draft.title?.ifEmpty("回复草稿") ?? "回复草稿"
    }

    private func draftExcerpt(for draft: DraftState) -> String? {
        let excerpt = draft.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !excerpt.isEmpty {
            return excerpt
        }
        let reply = draft.data.reply?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reply.isEmpty ? nil : reply
    }

    private func draftKindLabel(for draft: DraftState) -> String {
        if draft.draftKey == "new_topic" {
            return "新话题"
        }
        if draft.draftKey == "new_private_message" || draft.data.archetypeId == "private_message" {
            return "私信"
        }
        return "完整回复"
    }

    private func draftIcon(for draft: DraftState) -> String {
        switch draftKindLabel(for: draft) {
        case "新话题":
            return "square.and.pencil"
        case "私信":
            return "paperplane"
        default:
            return "arrowshape.turn.up.left"
        }
    }
}
