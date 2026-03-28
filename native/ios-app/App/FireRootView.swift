import Foundation
import SwiftUI
import UIKit

struct FireRootView: View {
    @StateObject private var viewModel = FireAppViewModel()
    @State private var copiedErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Session") {
                    LabeledContent("Phase", value: viewModel.session.loginPhase.title)
                    LabeledContent("Has Login", value: boolText(viewModel.session.hasLoginSession))
                    LabeledContent(
                        "Username",
                        value: viewModel.session.bootstrap.currentUsername ?? "-"
                    )
                    LabeledContent(
                        "Bootstrap Ready",
                        value: boolText(viewModel.session.bootstrap.hasPreloadedData)
                    )
                    LabeledContent(
                        "Has CSRF",
                        value: boolText(viewModel.session.cookies.csrfToken != nil)
                    )
                }

                Section("Actions") {
                    Button("Restore Session") {
                        viewModel.loadInitialState()
                    }
                    Button {
                        viewModel.openLogin()
                    } label: {
                        if viewModel.isPreparingLogin {
                            Text("Preparing Login...")
                        } else {
                            Text("Open Login")
                        }
                    }
                    .disabled(viewModel.isPreparingLogin)
                    Button("Refresh Bootstrap") {
                        viewModel.refreshBootstrap()
                    }
                    Button("Refresh Topics") {
                        viewModel.refreshTopics()
                    }
                    .disabled(!viewModel.session.readiness.canReadAuthenticatedApi)
                    Button("Logout", role: .destructive) {
                        viewModel.logout()
                    }
                }

                Section("Diagnostics") {
                    NavigationLink("Open Diagnostics") {
                        FireDiagnosticsView(viewModel: viewModel)
                    }
                }

                Section("Topic Browser") {
                    if !viewModel.session.readiness.canReadAuthenticatedApi {
                        Text("Complete login first to load the authenticated topic list.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Feed") {
                            Menu(viewModel.selectedTopicKind.title) {
                                ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                                    Button(kind.title) {
                                        viewModel.selectTopicKind(kind)
                                    }
                                }
                            }
                        }

                        if viewModel.isLoadingTopics && viewModel.topics.isEmpty {
                            ProgressView("Loading topics...")
                        } else if viewModel.topics.isEmpty {
                            Text("No topics loaded yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.topics, id: \.id) { topic in
                                NavigationLink {
                                    FireTopicDetailView(viewModel: viewModel, topic: topic)
                                } label: {
                                    FireTopicRow(
                                        topic: topic,
                                        category: viewModel.categoryPresentation(for: topic.categoryId)
                                    )
                                }
                            }

                            if let moreTopicsUrl = viewModel.moreTopicsUrl, !moreTopicsUrl.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    if let nextTopicsPage = viewModel.nextTopicsPage {
                                        Text("More topics are available on page \(nextTopicsPage + 1).")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Button {
                                        viewModel.loadMoreTopics()
                                    } label: {
                                        if viewModel.isAppendingTopics {
                                            Text("Loading More...")
                                        } else {
                                            Text("Load More Topics")
                                        }
                                    }
                                    .disabled(viewModel.isLoadingTopics || viewModel.nextTopicsPage == nil)

                                    LabeledContent("Source", value: moreTopicsUrl)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }

                        if viewModel.isLoadingTopics && !viewModel.topics.isEmpty {
                            ProgressView(viewModel.isAppendingTopics ? "Loading more topics..." : "Refreshing topics...")
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
                    } header: {
                        HStack {
                            Text("Last Error")
                            Spacer()
                            Button {
                                copyErrorMessage(errorMessage)
                            } label: {
                                Image(systemName: copiedErrorMessage == errorMessage ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(copiedErrorMessage == errorMessage ? "Copied last error" : "Copy last error")
                        }
                    }
                }
            }
            .navigationTitle("Fire Native")
        }
        .fullScreenCover(isPresented: $viewModel.isPresentingLogin) {
            FireLoginScreen(viewModel: viewModel)
        }
        .task {
            viewModel.loadInitialState()
        }
    }

    private func boolText(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func copyErrorMessage(_ errorMessage: String) {
        UIPasteboard.general.string = errorMessage
        copiedErrorMessage = errorMessage

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))

            if copiedErrorMessage == errorMessage {
                copiedErrorMessage = nil
            }
        }
    }
}

private struct FireTopicRow: View {
    let topic: TopicSummaryState
    let category: FireTopicCategoryPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 6) {
                if let category {
                    FireTopicPill(
                        label: category.displayName,
                        backgroundColor: Color(fireHex: category.colorHex)?.opacity(0.18) ?? Color.accentColor.opacity(0.12),
                        foregroundColor: Color(fireHex: category.textColorHex) ?? Color(fireHex: category.colorHex) ?? .accentColor
                    )
                }

                ForEach(FireTopicPresentation.topicStatusLabels(for: topic), id: \.self) { label in
                    FireTopicPill(
                        label: label,
                        backgroundColor: Color.secondary.opacity(0.12),
                        foregroundColor: .secondary
                    )
                }
            }

            Text(topic.title)
                .font(.headline)

            if let excerpt = topic.excerpt {
                Text(FireTopicPresentation.plainText(from: excerpt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let lastPosterUsername = topic.lastPosterUsername
                ?? topic.posters.first?.description
                ?? topic.posters.first.map({ "User \($0.userId)" })
            {
                HStack(spacing: 8) {
                    Text(lastPosterUsername)
                    if let timestamp = FireTopicPresentation.formatTimestamp(topic.lastPostedAt ?? topic.createdAt) {
                        Text(timestamp)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Text("Posts \(topic.postsCount)")
                Text("Replies \(topic.replyCount)")
                Text("Views \(topic.views)")
                Text("Likes \(topic.likeCount)")
                if topic.unreadPosts > 0 {
                    Text("Unread \(topic.unreadPosts)")
                }
                if !topic.tags.isEmpty {
                    Text("#\(topic.tags.joined(separator: " #"))")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct FireTopicDetailView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let topic: TopicSummaryState

    var body: some View {
        List {
            Section("Overview") {
                if let category = viewModel.categoryPresentation(for: topic.categoryId) {
                    FireTopicCategoryHeader(category: category)
                }
                LabeledContent("Replies", value: "\(topic.replyCount)")
                LabeledContent("Posts", value: "\(topic.postsCount)")
                LabeledContent("Views", value: "\(topic.views)")
                LabeledContent("Likes", value: "\(topic.likeCount)")
                if let timestamp = FireTopicPresentation.formatTimestamp(topic.createdAt) {
                    LabeledContent("Created", value: timestamp)
                }
                if let timestamp = FireTopicPresentation.formatTimestamp(topic.lastPostedAt) {
                    LabeledContent("Last Activity", value: timestamp)
                }
                if let lastPoster = topic.lastPosterUsername {
                    LabeledContent("Last Poster", value: lastPoster)
                }
                if let lastReadPostNumber = topic.lastReadPostNumber {
                    LabeledContent("Last Read", value: "#\(lastReadPostNumber)")
                }
                if !topic.tags.isEmpty {
                    LabeledContent("Tags", value: topic.tags.joined(separator: ", "))
                }
            }

            if let detail = viewModel.topicDetail(for: topic.id) {
                Section("Posts") {
                    ForEach(detail.postStream.posts, id: \.id) { post in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(post.username)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("#\(post.postNumber)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if let timestamp = FireTopicPresentation.formatTimestamp(post.createdAt) {
                                Text(timestamp)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let attributed = FireTopicPresentation.attributedText(from: post.cooked) {
                                Text(attributed)
                                    .font(.body)
                                    .tint(.accentColor)
                            } else {
                                Text(FireTopicPresentation.plainText(from: post.cooked))
                                    .font(.body)
                            }
                            HStack(spacing: 12) {
                                Text("Likes \(post.likeCount)")
                                Text("Replies \(post.replyCount)")
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else if viewModel.isLoadingTopic(topicId: topic.id) {
                Section("Posts") {
                    ProgressView("Loading topic...")
                }
            } else {
                Section("Posts") {
                    Text("No topic detail loaded.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") {
                    viewModel.loadTopicDetail(topicId: topic.id, force: true)
                }
            }
        }
        .task {
            viewModel.loadTopicDetail(topicId: topic.id)
        }
    }
}

private struct FireTopicCategoryHeader: View {
    let category: FireTopicCategoryPresentation

    var body: some View {
        HStack {
            Text(category.displayName)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(fireHex: category.colorHex)?.opacity(0.18) ?? Color.accentColor.opacity(0.12))
                .foregroundStyle(Color(fireHex: category.textColorHex) ?? Color(fireHex: category.colorHex) ?? .accentColor)
                .clipShape(Capsule())
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

private struct FireTopicPill: View {
    let label: String
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth)

        return CGSize(width: maxLineWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: cursor,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
