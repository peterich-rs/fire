import Foundation

/// Maps `FireTopicDetailPageState` to an immutable `FireTopicDetailPageSnapshot`.
///
/// The assembler is a stateless service — it holds no mutable state and
/// produces a new snapshot on every call to `buildSnapshot(from:configuration:)`.
///
/// Threading: must be called on the main actor (all store state is `@MainActor`).
@MainActor
struct FireTopicDetailSnapshotAssembler {

    // MARK: - Build

    /// Builds an immutable page snapshot from the current page state.
    ///
    /// - Parameters:
    ///   - state: The current page state, assembled by the controller.
    ///   - configuration: The controller-owned runtime configuration used to
    ///     produce feed items and stable content tokens.
    func buildSnapshot(
        from state: FireTopicDetailPageState,
        configuration: FireTopicDetailRuntimeConfiguration
    ) -> FireTopicDetailPageSnapshot {
        let runtimeSnapshot = configuration.makeSnapshot()

        return FireTopicDetailPageSnapshot(
            items: runtimeSnapshot.items,
            replyIndexByPostID: runtimeSnapshot.replyIndexByPostID,
            canWriteInteractions: state.canWriteInteractions,
            hasDetail: state.detail != nil,
            toolbarState: makeToolbarState(from: state),
            quickReplyState: makeQuickReplyState(from: state),
            pendingScrollTarget: state.pendingScrollTarget,
            invalidationToken: configuration.snapshotInvalidationToken
        )
    }

    func makeToolbarState(from state: FireTopicDetailPageState) -> FireTopicDetailToolbarState {
        let slug = (state.detail?.slug ?? state.row.topic.slug)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = slug.isEmpty ? "topic-\(state.topic.id)" : slug
        let shareURL = URL(string: "\(state.baseURLString)/t/\(path)/\(state.topic.id)")

        return FireTopicDetailToolbarState(
            title: "话题",
            shareURL: shareURL,
            isBookmarked: state.detail?.bookmarked == true,
            canWriteInteractions: state.canWriteInteractions,
            canEditTopic: state.detail?.details.canEdit == true,
            isPrivateMessageThread: FireTopicPresentation.isPrivateMessageArchetype(state.detail?.archetype),
            currentNotificationLevel: FireTopicNotificationLevelOption(
                rawValue: Int32(state.detail?.details.notificationLevel ?? 1)
            ) ?? .regular
        )
    }

    func makeQuickReplyState(from state: FireTopicDetailPageState) -> FireTopicDetailQuickReplyState {
        let trimmedDraft = state.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let validationMessage: String?
        if let quickReplyError = state.quickReplyError,
           quickReplyError.isEmpty == false {
            validationMessage = quickReplyError
        } else if !trimmedDraft.isEmpty, trimmedDraft.count < state.minimumReplyLength {
            validationMessage = "回复至少需要 \(state.minimumReplyLength) 个字"
        } else {
            validationMessage = nil
        }

        return FireTopicDetailQuickReplyState(
            isVisible: state.canWriteInteractions,
            typingSummary: typingSummary(from: state.typingUsers),
            targetSummary: state.composerContext?.targetSummary,
            placeholder: state.composerContext?.placeholder ?? "快速回复…",
            draft: state.replyDraft,
            isSubmitting: state.isSubmittingReply,
            validationMessage: validationMessage
        )
    }

    private func typingSummary(from users: [TopicPresenceUserState]) -> String? {
        guard !users.isEmpty else { return nil }
        let names = users.prefix(3).map(\.username)
        let leading = names.joined(separator: "、")
        if users.count > 3 {
            return "\(leading) 等 \(users.count) 人正在输入"
        }
        return "\(leading) 正在输入"
    }
}
