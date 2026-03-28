import Foundation
import SwiftUI

struct FireRootView: View {
    @StateObject private var viewModel = FireAppViewModel()

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

                Section("Topic Browser") {
                    if !viewModel.session.readiness.canReadAuthenticatedApi {
                        Text("Complete login first to load the authenticated topic list.")
                            .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("Feed") {
                            Menu(viewModel.selectedTopicKind.title) {
                                ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                                    Button(kind.title) {
                                        viewModel.selectedTopicKind = kind
                                        viewModel.refreshTopics()
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
                                    FireTopicRow(topic: topic)
                                }
                            }
                            if let moreTopicsUrl = viewModel.moreTopicsUrl {
                                LabeledContent("More", value: moreTopicsUrl)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if viewModel.isLoadingTopics && !viewModel.topics.isEmpty {
                            ProgressView("Refreshing topics...")
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Section("Last Error") {
                        Text(errorMessage)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.red)
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
}

private struct FireTopicRow: View {
    let topic: TopicSummaryState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(topic.title)
                .font(.headline)
            if let excerpt = topic.excerpt {
                Text(excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Text("Replies \(topic.replyCount)")
                Text("Views \(topic.views)")
                if topic.unreadPosts > 0 {
                    Text("Unread \(topic.unreadPosts)")
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
                LabeledContent("Replies", value: "\(topic.replyCount)")
                LabeledContent("Views", value: "\(topic.views)")
                LabeledContent("Likes", value: "\(topic.likeCount)")
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
                            Text(plainText(from: post.cooked))
                                .font(.body)
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

    private func plainText(from html: String) -> String {
        html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
