import SwiftUI

struct FirePostRepliesSheet: View {
    @Environment(\.dismiss) private var dismiss

    let post: TopicPostState
    let replies: [TopicPostState]
    let replyHistory: [TopicPostState]
    let isLoading: Bool
    let errorMessage: String?
    let baseURLString: String
    let onJumpToPost: (UInt32) -> Void
    let onRetry: () async -> Void

    private var hasContent: Bool {
        !replies.isEmpty || !replyHistory.isEmpty
    }

    var body: some View {
        List {
            if isLoading && !hasContent {
                loadingRow
            }

            if let errorMessage {
                errorRow(message: errorMessage)
            }

            if !replyHistory.isEmpty {
                Section("回复来源") {
                    ForEach(replyHistory, id: \.id) { reply in
                        FirePostReplyContextRow(
                            post: reply,
                            baseURLString: baseURLString,
                            onJump: onJumpToPost
                        )
                    }
                }
            }

            if !replies.isEmpty {
                Section("直接回复") {
                    ForEach(replies, id: \.id) { reply in
                        FirePostReplyContextRow(
                            post: reply,
                            baseURLString: baseURLString,
                            onJump: onJumpToPost
                        )
                    }
                }
            }

            if !isLoading && errorMessage == nil && !hasContent {
                emptyRow
            }
        }
        .navigationTitle("#\(post.postNumber) 的回复")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("收起") {
                    dismiss()
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack {
            Spacer()
            ProgressView()
                .padding(.vertical, 20)
            Spacer()
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)

            Button {
                Task { await onRetry() }
            } label: {
                Label("重试", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 6)
    }

    private var emptyRow: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundStyle(FireTheme.subtleInk)
            Text("暂时没有可显示的回复上下文")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FireTheme.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct FirePostReplyContextRow: View {
    let post: TopicPostState
    let baseURLString: String
    let onJump: (UInt32) -> Void

    private var displayName: String {
        (post.name ?? "").ifEmpty(post.username.ifEmpty("Unknown"))
    }

    private var excerpt: String {
        (post.presentation?.plainText() ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty("无正文预览")
    }

    var body: some View {
        Button {
            onJump(post.postNumber)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                FireAvatarView(
                    avatarTemplate: post.avatarTemplate,
                    username: post.username.ifEmpty("?"),
                    size: 34,
                    baseURLString: baseURLString
                )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(FireTheme.ink)
                            .lineLimit(1)

                        Text("#\(post.postNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(FireTheme.tertiaryInk)

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(FireTheme.tertiaryInk)
                    }

                    Text(excerpt)
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
