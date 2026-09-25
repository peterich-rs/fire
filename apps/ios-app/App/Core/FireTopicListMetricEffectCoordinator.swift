import UIKit

/// Session gate for topic-list metric micro-animations.
///
/// Rules:
/// 1. Effects only run while the host list is **settled** (not dragging / decelerating).
/// 2. Each topic plays each effect **at most once** per app session — scrolling back
///    must not re-trigger balloons / surge pulses and clutter the feed.
@MainActor
final class FireTopicListMetricEffectCoordinator {
    static let shared = FireTopicListMetricEffectCoordinator()

    enum EffectKind: Hashable {
        case heartBalloon
        case viewSurgePulse
    }

    /// Debounce after the finger stops so the eye can rest on the row first.
    static let settleDelay: TimeInterval = 0.22

    /// Starts unsettled so the first paint waits a beat (same path as scroll-stop).
    private(set) var isSettled = false
    private var played = Set<PlayedKey>()
    private var settleWorkItem: DispatchWorkItem?
    private let pendingCells = NSHashTable<FireTopicListTopicCell>.weakObjects()

    private init() {}

    /// Host lists call this from scroll begin / end callbacks.
    func setScrolling(_ scrolling: Bool) {
        settleWorkItem?.cancel()
        settleWorkItem = nil

        if scrolling {
            isSettled = false
            return
        }

        scheduleSettle()
    }

    /// Register a configured topic cell. Effects play once the list is settled.
    func track(_ cell: FireTopicListTopicCell) {
        pendingCells.add(cell)
        if isSettled {
            cell.playPendingMetricEffectsIfNeeded()
        } else if settleWorkItem == nil {
            // First visible rows after launch / tab switch: settle without a scroll event.
            scheduleSettle()
        }
    }

    private func scheduleSettle() {
        settleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isSettled = true
            self.settleWorkItem = nil
            self.flushPendingCells()
        }
        settleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    func untrack(_ cell: FireTopicListTopicCell) {
        pendingCells.remove(cell)
    }

    /// Returns `true` only the first time this topic claims the effect.
    @discardableResult
    func claim(_ kind: EffectKind, topicID: UInt64) -> Bool {
        let key = PlayedKey(topicID: topicID, kind: kind)
        if played.contains(key) {
            return false
        }
        played.insert(key)
        return true
    }

    func hasPlayed(_ kind: EffectKind, topicID: UInt64) -> Bool {
        played.contains(PlayedKey(topicID: topicID, kind: kind))
    }

    /// Test / logout hook.
    func resetSessionStateForTesting() {
        settleWorkItem?.cancel()
        settleWorkItem = nil
        isSettled = false
        played.removeAll()
        pendingCells.removeAllObjects()
    }

    private func flushPendingCells() {
        for cell in pendingCells.allObjects {
            cell.playPendingMetricEffectsIfNeeded()
        }
    }

    private struct PlayedKey: Hashable {
        let topicID: UInt64
        let kind: EffectKind
    }
}
