import Foundation

/// Maps `FireTopicDetailPageState` to an immutable `FireTopicDetailPageSnapshot`.
///
/// The assembler is a stateless service — it holds no mutable state and
/// produces a new snapshot on every call to `buildSnapshot(from:configuration:)`.
struct FireTopicDetailSnapshotAssembler: Sendable {

    // MARK: - Build

    func buildSnapshot(
        from input: FireTopicDetailSnapshotInput
    ) -> FireTopicDetailPageSnapshot {
        let runtimeSnapshot = input.configuration.makeSnapshot()

        return FireTopicDetailPageSnapshot(
            items: runtimeSnapshot.items,
            replyIndexByPostID: runtimeSnapshot.replyIndexByPostID,
            canWriteInteractions: input.configuration.canWriteInteractions,
            hasDetail: input.configuration.detail != nil,
            toolbarState: input.toolbarState,
            quickReplyState: input.quickReplyState,
            pendingScrollTarget: input.pendingScrollTarget,
            invalidationToken: input.invalidationToken
        )
    }

    func makeToolbarState(from state: FireTopicDetailChromeState) -> FireTopicDetailToolbarState {
        let slug = (state.detail?.slug ?? state.row.topic.slug)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = slug.isEmpty ? "topic-\(state.row.topic.id)" : slug
        let shareURL = URL(string: "\(state.baseURLString)/t/\(path)/\(state.row.topic.id)")

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

    func makeQuickReplyState(from state: FireTopicDetailComposerState) -> FireTopicDetailQuickReplyState {
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

    func makeChromeToken(from state: FireTopicDetailChromeState) -> FireTopicDetailChromeInvalidationToken {
        FireTopicDetailChromeInvalidationToken(
            topicID: state.row.topic.id,
            title: state.detail?.title ?? state.row.topic.title,
            slug: state.detail?.slug ?? state.row.topic.slug,
            bookmarked: state.detail?.bookmarked == true,
            canWriteInteractions: state.canWriteInteractions,
            canEditTopic: state.detail?.details.canEdit == true,
            archetype: state.detail?.archetype,
            notificationLevel: state.detail?.details.notificationLevel,
            baseURLString: state.baseURLString
        )
    }

    func makeComposerToken(from state: FireTopicDetailComposerState) -> FireTopicDetailComposerInvalidationToken {
        FireTopicDetailComposerInvalidationToken(
            canWriteInteractions: state.canWriteInteractions,
            typingUsernames: state.typingUsers.map(\.username),
            composerContextID: state.composerContext?.id,
            replyDraft: state.replyDraft,
            quickReplyError: state.quickReplyError,
            isSubmittingReply: state.isSubmittingReply,
            minimumReplyLength: state.minimumReplyLength
        )
    }

    func makeSidecarToken(from state: FireTopicDetailSidecarState) -> FireTopicDetailSidecarInvalidationToken {
        FireTopicDetailSidecarInvalidationToken(
            topicAiSummaryToken: state.topicAiSummary.map(Self.topicAiSummaryToken(_:)) ?? "",
            isLoadingTopicAiSummary: state.isLoadingTopicAiSummary,
            topicAiSummaryError: state.topicAiSummaryError ?? ""
        )
    }

    func makeInteractionToken(
        from state: FireTopicDetailInteractionState
    ) -> FireTopicDetailInteractionInvalidationToken {
        FireTopicDetailInteractionInvalidationToken(
            mutatingPostIDs: state.mutatingPostIDs,
            loadingPostReplyContextIDs: state.loadingPostReplyContextIDs,
            postReplyContextErrorIDs: state.postReplyContextErrorsByPostID.keys.sorted(),
            expandedPostTextIDs: state.expandedPostTextIDs,
            expandedReplyRootPostIDs: state.expandedReplyRootPostIDs
        )
    }

    private static func topicAiSummaryToken(_ summary: TopicAiSummaryState) -> String {
        [
            summary.summarizedText,
            summary.algorithm ?? "",
            String(summary.outdated),
            String(summary.canRegenerate),
            String(summary.newPostsSinceSummary),
            summary.updatedAt ?? "",
        ].joined(separator: "\u{1F}")
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
