import Foundation

protocol FireTopicDetailFullSnapshotSource {
    func full() -> TopicDetailUiSnapshotState
}

extension TopicDetailSnapshotHandle: FireTopicDetailFullSnapshotSource {}

struct FireTopicDetailMirrorState {
    var snapshot: FireTopicDetailSnapshot
    var order: [UInt64]
}

final class FireTopicDetailSnapshotMirror: @unchecked Sendable {
    private let lock = NSLock()
    private var state: FireTopicDetailMirrorState?

    /// Runs on the Rust callback thread, in delivery order.
    func apply(
        _ change: TopicDetailSnapshotChangeState,
        source: FireTopicDetailFullSnapshotSource
    ) -> FireTopicDetailSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        if let generation = state?.snapshot.generation, change.generation <= generation {
            return nil
        }
        if state == nil || change.baseGeneration != state?.snapshot.generation {
            return replace(with: source.full(), generation: change.generation, revisions: change.revisions)
        }
        guard var current = state else {
            return replace(with: source.full(), generation: change.generation, revisions: change.revisions)
        }
        if let status = change.status {
            current.snapshot.phase = status.phase
            current.snapshot.loadError = status.loadError
            current.snapshot.notice = status.notice
            current.snapshot.hasMore = status.hasMore
            current.snapshot.isLoadingMore = status.isLoadingMore
            current.snapshot.loadMoreError = status.loadMoreError
            current.snapshot.scrollTargetPostNumber = status.scrollTargetPostNumber
        }
        if let chrome = change.chrome {
            current.snapshot.chrome = chrome
        }
        if let composer = change.composer {
            current.snapshot.composer = composer
        }
        if let sidecar = change.sidecar {
            current.snapshot.sidecar = sidecar
        }
        switch change.replyContext {
        case .unchanged:
            break
        case .cleared:
            current.snapshot.focusedReplyContext = nil
        case let .set(context):
            current.snapshot.focusedReplyContext = context
        }
        if let flagTypes = change.flagTypes {
            current.snapshot.flagTypes = flagTypes
        }
        current.snapshot.homeRowPatch = change.homeRowPatch
        for row in change.upsertedRows {
            current.snapshot.rowsByPostID[row.postId] = row
        }
        if let rowOrder = change.rowOrder {
            current.order = rowOrder
            let keep = Set(rowOrder)
            current.snapshot.rowsByPostID = current.snapshot.rowsByPostID.filter { keep.contains($0.key) }
        }
        if current.order.contains(where: { current.snapshot.rowsByPostID[$0] == nil }) {
            return replace(with: source.full(), generation: change.generation, revisions: change.revisions)
        }
        current.snapshot.rows = current.order.compactMap { current.snapshot.rowsByPostID[$0] }
        current.snapshot.generation = change.generation
        current.snapshot.collectionRevision = change.revisions.collection
        current.snapshot.chromeRevision = change.revisions.chrome
        current.snapshot.sidecarRevision = change.revisions.sidecar
        current.snapshot.interactionRevision = change.revisions.interaction
        current.snapshot.composerRevision = change.revisions.composer
        state = current
        return current.snapshot
    }

    private func replace(
        with full: TopicDetailUiSnapshotState,
        generation: UInt64,
        revisions: TopicDetailRevisionsState
    ) -> FireTopicDetailSnapshot {
        var snapshot = FireTopicDetailSnapshot(full: full)
        snapshot.generation = generation
        snapshot.collectionRevision = revisions.collection
        snapshot.chromeRevision = revisions.chrome
        snapshot.sidecarRevision = revisions.sidecar
        snapshot.interactionRevision = revisions.interaction
        snapshot.composerRevision = revisions.composer
        state = FireTopicDetailMirrorState(
            snapshot: snapshot,
            order: snapshot.rows.map(\.postId)
        )
        return snapshot
    }
}
