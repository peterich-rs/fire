import Foundation
import UIKit

extension FireTopicPresentation {
    static func imageAttachments(from presentation: RenderDocumentHandle) -> [FireCookedImage] {
        FireRenderPresentation.images(from: presentation)
    }
    static func renderContent(
        from presentation: RenderDocumentHandle,
        sourceToken: String
    ) -> FireTopicPostRenderContent {
        renderContentFromPresentation(presentation, source: sourceToken)
    }
    static func renderContent(from post: TopicPostState) -> FireTopicPostRenderContent? {
        guard let presentation = post.presentation else {
            return nil
        }
        return renderContentFromPresentation(
            presentation,
            source: Self.renderInput(for: post).presentationChecksum.map(String.init) ?? "missing"
        )
    }
    private static func renderInput(for post: TopicPostState) -> FireTopicPostRenderInput {
        FireTopicPostRenderInput(
            presentationChecksum: post.presentation.map { $0.checksum() }
        )
    }
    private static func renderContentFromPresentation(
        _ presentation: RenderDocumentHandle,
        source: String
    ) -> FireTopicPostRenderContent {
        let imageAttachments = FireRenderPresentation.images(from: presentation)
        let mappedSegments = FireRenderPresentation.segments(from: presentation)
        let richNodes = FireRenderPresentation.richNodes(from: mappedSegments)
        let segments = mappedSegments.compactMap { segment -> FireTopicPostRenderSegment? in
            switch segment {
            case let .rich(nodes):
                let attributedText = FireRichTextAttributedStringBuilder.build(
                    from: nodes,
                    textColor: FireTheme.uiInk,
                    accentColor: FireTopicDetailCellColors.accent
                )
                return attributedText.length > 0 ? .text(attributedText) : nil
            case let .image(image):
                return .image(image)
            case let .onebox(card):
                return .onebox(card)
            case let .quote(nodes):
                let attributedText = FireRichTextAttributedStringBuilder.build(
                    from: nodes,
                    textColor: FireTheme.uiInk,
                    accentColor: FireTopicDetailCellColors.accent
                )
                return attributedText.length > 0 ? .quote(attributedText) : nil
            }
        }

        let attributedText = richNodes.isEmpty ? nil :
            FireRichTextAttributedStringBuilder.build(
                from: richNodes,
                textColor: FireTheme.uiInk,
                accentColor: FireTopicDetailCellColors.accent
            )

        return FireTopicPostRenderContent(
            plainText: presentation.plainText(),
            attributedText: attributedText,
            imageAttachments: imageAttachments,
            segments: segments,
            signature: FireTopicPostRenderSignature.make(
                source: source,
                imageAttachments: imageAttachments,
                segments: segments
            )
        )
    }
    /// Project snapshot rows into stored posts and rich text once.
    /// Unchanged presentation checksums keep the previous attributed text.
    static func adopt(
        snapshot: FireTopicDetailSnapshot,
        reusing previous: FireTopicDetailAdoptedProjection?
    ) -> FireTopicDetailAdoptedProjection {
        var posts: [UInt64: TopicPostState] = [:]
        posts.reserveCapacity(snapshot.rows.count)
        var rowsByPostID: [UInt64: TopicDetailUiRowState] = [:]
        rowsByPostID.reserveCapacity(snapshot.rows.count)
        var mutatingPostIDs = Set<UInt64>()
        var loadingReplyContextPostIDs = Set<UInt64>()
        var changedPostIDs = Set<UInt64>()
        var originalRow: FirePreparedTopicTimelineRow?
        var replyRows: [FirePreparedTopicTimelineRow] = []
        replyRows.reserveCapacity(snapshot.rows.count)
        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(snapshot.rows.count)

        for row in snapshot.rows {
            guard rowsByPostID[row.postId] == nil else { continue }
            rowsByPostID[row.postId] = row
            if row.isMutating {
                mutatingPostIDs.insert(row.postId)
            }
            if row.isLoadingReplyContext {
                loadingReplyContextPostIDs.insert(row.postId)
            }
            let previousRow = previous?.rowsByPostID[row.postId]
            let unchanged = previousRow?.rowFingerprint == row.rowFingerprint
            if unchanged, let previousPost = previous?.posts[row.postId] {
                posts[row.postId] = previousPost
            } else {
                changedPostIDs.insert(row.postId)
                posts[row.postId] = FireTopicDetailUiProjection.post(from: row)
            }
            let post = posts[row.postId]!
            let timelineRow = FirePreparedTopicTimelineRow(
                entry: FireTopicDetailUiProjection.timelineEntry(from: row)
            )
            if unchanged, let reused = previous?.renderState.contentByPostID[row.postId] {
                contentByPostID[row.postId] = reused
            } else if let content = renderContent(from: post) {
                contentByPostID[row.postId] = content
            } else {
                continue
            }
            if row.isOriginalPost, originalRow == nil {
                originalRow = timelineRow
            } else {
                replyRows.append(timelineRow)
            }
        }
        if originalRow == nil {
            originalRow = replyRows.first
            if !replyRows.isEmpty {
                replyRows.removeFirst()
            }
        }

        return FireTopicDetailAdoptedProjection(
            posts: posts,
            rowsByPostID: rowsByPostID,
            mutatingPostIDs: mutatingPostIDs,
            loadingReplyContextPostIDs: loadingReplyContextPostIDs,
            changedPostIDs: changedPostIDs,
            renderState: FireTopicDetailRenderState(
                originalRow: originalRow,
                replyRows: replyRows,
                contentByPostID: contentByPostID
            )
        )
    }

    static func detailRenderState(
        from detail: TopicDetailState,
        baseURLString: String
    ) -> FireTopicDetailRenderState {
        detailRenderCache(
            from: detail,
            baseURLString: baseURLString
        ).renderState
    }
    private static func timelineRowInput(for post: TopicPostState) -> FireTopicTimelineRowInput {
        FireTopicTimelineRowInput(
            postID: post.id,
            postNumber: post.postNumber,
            replyToPostNumber: post.replyToPostNumber,
            responseParentPostNumber: nil,
            responseDepth: nil,
            responsePreorderIndex: nil,
            responseHasChildren: nil,
            responseDescendantCount: nil,
            responseSiblingIndex: nil,
            responseIsLastSibling: nil
        )
    }
    private static func timelineRowInput(for treeRow: TopicTreeRowState) -> FireTopicTimelineRowInput {
        FireTopicTimelineRowInput(
            postID: treeRow.postId,
            postNumber: treeRow.postNumber,
            replyToPostNumber: treeRow.parentPostNumber,
            responseParentPostNumber: treeRow.parentPostNumber,
            responseDepth: treeRow.depth,
            responsePreorderIndex: treeRow.preorderIndex,
            responseHasChildren: treeRow.hasChildren,
            responseDescendantCount: treeRow.descendantCount,
            responseSiblingIndex: treeRow.siblingIndex,
            responseIsLastSibling: treeRow.isLastSibling
        )
    }
    private static func originalTimelineRow(for post: TopicPostState) -> FirePreparedTopicTimelineRow {
        FirePreparedTopicTimelineRow(
            entry: FireTopicTimelineEntry(
                postId: post.id,
                postNumber: post.postNumber,
                parentPostNumber: nil,
                depth: 0,
                isOriginalPost: true
            )
        )
    }
    private static func replyTimelineRow(from treeRow: TopicTreeRowState) -> FirePreparedTopicTimelineRow {
        FirePreparedTopicTimelineRow(
            entry: FireTopicTimelineEntry(
                postId: treeRow.postId,
                postNumber: treeRow.postNumber,
                parentPostNumber: treeRow.parentPostNumber,
                depth: UInt32(treeRow.depth),
                isOriginalPost: false
            )
        )
    }
    static func detailRenderCache(
        from detail: TopicDetailState,
        baseURLString: String,
        previous: FireTopicDetailRenderCache? = nil
    ) -> FireTopicDetailRenderCache {
        let orderedPosts = uniqueTopicPostsPreservingOrder(
            mergeTopicPosts(
                existing: detail.postStream.posts,
                incoming: [],
                orderedPostIDs: detail.postStream.stream
            )
        )
        let rowInputs = orderedPosts.map(timelineRowInput(for:))
        let contentInputsByPostID = Dictionary(
            orderedPosts.map { post in
                (post.id, renderInput(for: post))
            },
            uniquingKeysWith: { _, newest in newest }
        )

        let originalRow: FirePreparedTopicTimelineRow?
        let replyRows: [FirePreparedTopicTimelineRow]
        if previous?.rowInputs == rowInputs {
            originalRow = previous?.renderState.originalRow
            replyRows = previous?.renderState.replyRows ?? []
        } else {
            let rows = rebuildTimelineEntries(from: orderedPosts).map(FirePreparedTopicTimelineRow.init)
            let resolvedOriginalRow = rows.first(where: { $0.entry.isOriginalPost })
            originalRow = resolvedOriginalRow
            replyRows = rows.filter { row in
                row.entry.postId != resolvedOriginalRow?.entry.postId
            }
        }

        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(orderedPosts.count)
        let canReuseContent = previous?.baseURLString == baseURLString
        for post in orderedPosts {
            if canReuseContent,
               previous?.contentInputsByPostID[post.id] == contentInputsByPostID[post.id],
               let cachedContent = previous?.renderState.contentByPostID[post.id] {
                contentByPostID[post.id] = cachedContent
            } else {
                contentByPostID[post.id] = renderContent(from: post)
            }
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: originalRow,
                replyRows: replyRows,
                contentByPostID: contentByPostID
            )
        )
    }
    static func detailRenderCache(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        treePresentation: TopicTreePresentationState,
        baseURLString: String,
        previous: FireTopicDetailRenderCache? = nil
    ) -> FireTopicDetailRenderCache {
        let normalizedReplyRows = uniqueTreeRowsPreservingOrder(treePresentation.replyRows).filter { row in
            row.postId != sourceSnapshot.body.post.id
        }
        let postsByID = topicPostsByID([sourceSnapshot.body.post] + sourceSnapshot.loadedPosts)
        let orderedPosts = uniqueTopicPostsPreservingOrder(
            [sourceSnapshot.body.post] + normalizedReplyRows.compactMap { postsByID[$0.postId] }
        )
        let rowInputs = [timelineRowInput(for: sourceSnapshot.body.post)]
            + normalizedReplyRows.map(timelineRowInput(for:))
        let contentInputsByPostID = Dictionary(
            orderedPosts.map { post in
                (post.id, renderInput(for: post))
            },
            uniquingKeysWith: { _, newest in newest }
        )

        let originalRow = originalTimelineRow(for: sourceSnapshot.body.post)
        let preparedReplyRows: [FirePreparedTopicTimelineRow]
        if let previous,
           previous.rowInputs.count <= rowInputs.count,
           Array(rowInputs.prefix(previous.rowInputs.count)) == previous.rowInputs {
            let suffixRows = normalizedReplyRows
                .dropFirst(previous.renderState.replyRows.count)
                .map(replyTimelineRow(from:))
            preparedReplyRows = previous.renderState.replyRows + suffixRows
        } else {
            preparedReplyRows = normalizedReplyRows.map(replyTimelineRow(from:))
        }

        var contentByPostID: [UInt64: FireTopicPostRenderContent] = [:]
        contentByPostID.reserveCapacity(orderedPosts.count)
        let canReuseContent = previous?.baseURLString == baseURLString
        for post in orderedPosts {
            if canReuseContent,
               previous?.contentInputsByPostID[post.id] == contentInputsByPostID[post.id],
               let cachedContent = previous?.renderState.contentByPostID[post.id] {
                contentByPostID[post.id] = cachedContent
            } else {
                contentByPostID[post.id] = renderContent(from: post)
            }
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: originalRow,
                replyRows: preparedReplyRows,
                contentByPostID: contentByPostID
            )
        )
    }
    static func detailRenderCache(
        sourceSnapshot: TopicDetailSourceSnapshotState,
        appending replyRows: [TopicTreeRowState],
        baseURLString: String,
        previous: FireTopicDetailRenderCache
    ) -> FireTopicDetailRenderCache? {
        let originalInput = renderInput(for: sourceSnapshot.body.post)
        guard !replyRows.isEmpty,
              previous.baseURLString == baseURLString,
              previous.rowInputs.first == timelineRowInput(for: sourceSnapshot.body.post),
              previous.contentInputsByPostID[sourceSnapshot.body.post.id] == originalInput,
              previous.renderState.originalRow?.entry.postId == sourceSnapshot.body.post.id,
              previous.renderState.contentByPostID[sourceSnapshot.body.post.id] != nil,
              previous.rowInputs.count == previous.renderState.replyRows.count + 1 else {
            return nil
        }

        var rowInputs = previous.rowInputs
        rowInputs.reserveCapacity(rowInputs.count + replyRows.count)

        var contentInputsByPostID = previous.contentInputsByPostID
        contentInputsByPostID.reserveCapacity(contentInputsByPostID.count + replyRows.count)

        var preparedReplyRows = previous.renderState.replyRows
        preparedReplyRows.reserveCapacity(preparedReplyRows.count + replyRows.count)

        var contentByPostID = previous.renderState.contentByPostID
        contentByPostID.reserveCapacity(contentByPostID.count + replyRows.count)

        let postsByID = topicPostsByID([sourceSnapshot.body.post] + sourceSnapshot.loadedPosts)
        for treeRow in replyRows {
            guard let post = postsByID[treeRow.postId] else {
                return nil
            }
            guard contentInputsByPostID[post.id] == nil else {
                return nil
            }

            rowInputs.append(timelineRowInput(for: treeRow))
            contentInputsByPostID[post.id] = renderInput(for: post)
            preparedReplyRows.append(replyTimelineRow(from: treeRow))
            contentByPostID[post.id] = renderContent(from: post)
        }

        return FireTopicDetailRenderCache(
            baseURLString: baseURLString,
            rowInputs: rowInputs,
            contentInputsByPostID: contentInputsByPostID,
            renderState: FireTopicDetailRenderState(
                originalRow: previous.renderState.originalRow ?? originalTimelineRow(for: sourceSnapshot.body.post),
                replyRows: preparedReplyRows,
                contentByPostID: contentByPostID
            )
        )
    }
}
