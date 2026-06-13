import UIKit
import XCTest
@testable import Fire

@MainActor
final class FirePostLayoutManagerTests: XCTestCase {
    func testEnqueueCalculationPublishesResolvedLayout() async throws {
        let publicationCounter = CounterBox()
        let manager = FirePostLayoutManager(
            backgroundQueue: DispatchQueue(label: "FirePostLayoutManagerTests.enqueue")
        ) { key, _, _, _, _, _, _ in
            Self.makeLayout(key: key, totalHeight: 123)
        }
        manager.onSnapshotRevisionChanged = {
            publicationCounter.increment()
        }
        let key = Self.makeKey(width: 320, postID: 1)

        manager.enqueueCalculation(
            key: key,
            attributedText: nil,
            plainText: "",
            images: [],
            polls: [],
            boostLines: [],
            trait: key.trait
        )

        try await waitUntil {
            manager.layout(forKey: key)?.totalHeight == 123
                && manager.currentSnapshotRevision > 0
                && publicationCounter.value > 0
        }

        XCTAssertEqual(manager.layout(forKey: key)?.totalHeight, 123)
    }

    func testInvalidateAllDropsStaleInFlightResults() async throws {
        let gate = DispatchSemaphore(value: 0)
        let staleKey = Self.makeKey(width: 320, postID: 2)
        let freshKey = Self.makeKey(width: 400, postID: 2)
        let manager = FirePostLayoutManager(
            backgroundQueue: DispatchQueue(label: "FirePostLayoutManagerTests.invalidate")
        ) { key, _, _, _, _, _, _ in
            if key == staleKey {
                gate.wait()
            }
            return Self.makeLayout(key: key, totalHeight: CGFloat(key.trait.contentWidthPixels))
        }

        manager.enqueueCalculation(
            key: staleKey,
            attributedText: nil,
            plainText: "",
            images: [],
            polls: [],
            boostLines: [],
            trait: staleKey.trait
        )
        manager.invalidateAll(reason: .widthChanged)
        manager.enqueueCalculation(
            key: freshKey,
            attributedText: nil,
            plainText: "",
            images: [],
            polls: [],
            boostLines: [],
            trait: freshKey.trait
        )
        gate.signal()

        try await waitUntil {
            manager.layout(forKey: freshKey)?.totalHeight == 400
                && manager.currentSnapshotRevision > 0
        }

        XCTAssertNil(manager.layout(forKey: staleKey))
        XCTAssertEqual(manager.layout(forKey: freshKey)?.totalHeight, 400)
    }

    func testDuplicateEnqueueDoesNotScheduleDuplicateWork() async throws {
        let counter = CounterBox()
        let gate = DispatchSemaphore(value: 0)
        let key = Self.makeKey(width: 360, postID: 3)
        let manager = FirePostLayoutManager(
            backgroundQueue: DispatchQueue(label: "FirePostLayoutManagerTests.dedup")
        ) { key, _, _, _, _, _, _ in
            counter.increment()
            gate.wait()
            return Self.makeLayout(key: key, totalHeight: 88)
        }

        manager.enqueueCalculation(
            key: key,
            attributedText: nil,
            plainText: "",
            images: [],
            polls: [],
            boostLines: [],
            trait: key.trait
        )
        manager.enqueueCalculation(
            key: key,
            attributedText: nil,
            plainText: "",
            images: [],
            polls: [],
            boostLines: [],
            trait: key.trait
        )
        gate.signal()

        try await waitUntil {
            manager.layout(forKey: key)?.totalHeight == 88
        }

        XCTAssertEqual(counter.value, 1)
    }

    func testDefaultLayoutUsesMeasuredAttributedTextAsAuthoritativeHeight() async throws {
        let manager = FirePostLayoutManager(
            backgroundQueue: DispatchQueue(label: "FirePostLayoutManagerTests.overflow")
        )
        let key = Self.makeKey(
            width: 220,
            postID: 4,
            textExpansionState: FirePostTextExpansionState(isCollapsible: true, isExpanded: false)
        )
        let shortAttributedText = NSAttributedString(
            string: "短文本",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .subheadline)
            ]
        )
        let longPlainText = Array(repeating: "这是一段用于验证长评论折叠判定的中文内容", count: 12)
            .joined(separator: "，")

        manager.enqueueCalculation(
            key: key,
            attributedText: shortAttributedText,
            plainText: longPlainText,
            images: [],
            polls: [],
            boostLines: [],
            trait: key.trait
        )

        try await waitUntil {
            manager.layout(forKey: key) != nil
        }

        XCTAssertNil(manager.layout(forKey: key)?.textExpansionFrame)
    }

    nonisolated private static func makeKey(
        width: Int,
        postID: UInt64,
        textExpansionState: FirePostTextExpansionState = .disabled
    ) -> FirePostCellLayoutKey {
        FirePostCellLayoutKey(
            postID: postID,
            depth: 1,
            showsThreadLine: true,
            showsDivider: true,
            replyTargetPostNumber: nil,
            replyContext: nil,
            textContentID: "text",
            imageSignature: [],
            pollSignature: [],
            boostSignature: [],
            hasReactions: false,
            textExpansionState: textExpansionState,
            acceptedAnswer: false,
            hasAuthorMetadata: false,
            trait: FirePostLayoutTraitSignature(
                contentWidthPixels: width,
                contentSizeCategory: UIContentSizeCategory.large.rawValue
            )
        )
    }

    nonisolated private static func makeLayout(key: FirePostCellLayoutKey, totalHeight: CGFloat) -> FirePostCellLayout {
        FirePostCellLayout(
            key: key,
            totalHeight: totalHeight,
            avatarFrame: .zero,
            threadLineFrame: nil,
            metaFrame: .zero,
            textFrame: nil,
            textContainerSize: .zero,
            textExpansionFrame: nil,
            imageFrames: [],
            pollFrames: [],
            boostFrames: [],
            replyShortcutFrame: nil,
            reactionsFrame: nil,
            menuFrame: nil,
            dividerFrame: nil
        )
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while !condition() {
            if clock.now >= deadline {
                XCTFail("Timed out waiting for async layout work.", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class CounterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
