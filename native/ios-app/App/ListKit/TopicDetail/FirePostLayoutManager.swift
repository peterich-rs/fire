import Foundation
import SwiftUI
import UIKit

enum FirePostLayoutInvalidationReason {
    case widthChanged
    case contentSizeCategoryChanged
    case contentChanged
}

typealias FirePostLayoutComputation = @Sendable (
    FirePostCellLayoutKey,
    NSAttributedString?,
    [FireCookedImage],
    FirePostLayoutTraitSignature
) -> FirePostCellLayout

private final class FireAttributedTextBox: @unchecked Sendable {
    let value: NSAttributedString?

    init(_ value: NSAttributedString?) {
        self.value = value
    }
}

@MainActor
final class FirePostLayoutManager: ObservableObject {
    private var layoutCache: [FirePostCellLayoutKey: FirePostCellLayout] = [:]
    @Published private var snapshotRevision: UInt64 = 0
    private let backgroundQueue: DispatchQueue
    private let computeLayout: FirePostLayoutComputation
    private var inFlightKeys: Set<FirePostCellLayoutKey> = []
    private var publicationTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastTraitSignature: FirePostLayoutTraitSignature?

    var currentSnapshotRevision: UInt64 {
        snapshotRevision
    }

    init(
        backgroundQueue: DispatchQueue = DispatchQueue(
            label: "com.fire.post-layout-manager",
            qos: .userInitiated
        ),
        computeLayout: @escaping FirePostLayoutComputation = { key, attributedText, images, trait in
            FirePostLayoutManager.defaultComputeLayout(
                key: key,
                attributedText: attributedText,
                images: images,
                trait: trait
            )
        }
    ) {
        self.backgroundQueue = backgroundQueue
        self.computeLayout = computeLayout
    }

    func cachedLayout(forKey key: FirePostCellLayoutKey) -> FirePostCellLayout? {
        layoutCache[key]
    }

    func layout(forKey key: FirePostCellLayoutKey) -> FirePostCellLayout? {
        layoutCache[key]
    }

    func enqueueCalculation(
        key: FirePostCellLayoutKey,
        attributedText: NSAttributedString?,
        images: [FireCookedImage],
        trait: FirePostLayoutTraitSignature
    ) {
        if layoutCache[key] != nil || inFlightKeys.contains(key) {
            return
        }

        inFlightKeys.insert(key)
        let generation = self.generation
        let queue = backgroundQueue
        let computeLayout = self.computeLayout
        let attributedTextBox = FireAttributedTextBox(attributedText?.copy() as? NSAttributedString)

        queue.async { [weak self] in
            let layout = computeLayout(key, attributedTextBox.value, images, trait)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inFlightKeys.remove(key)
                guard generation == self.generation else {
                    return
                }
                guard self.layoutCache[key] == nil else {
                    return
                }
                self.layoutCache[key] = layout
                self.scheduleSnapshotPublication()
            }
        }
    }

    func invalidateAll(reason: FirePostLayoutInvalidationReason) {
        generation &+= 1
        layoutCache.removeAll()
        inFlightKeys.removeAll()
        publicationTask?.cancel()
        publicationTask = nil
        snapshotRevision &+= 1
        lastTraitSignature = nil
    }

    func invalidateItems(keys: Set<FirePostCellLayoutKey>) {
        guard !keys.isEmpty else { return }
        for key in keys {
            layoutCache.removeValue(forKey: key)
            inFlightKeys.remove(key)
        }
        snapshotRevision &+= 1
    }

    func updateTraitSignature(_ signature: FirePostLayoutTraitSignature) {
        if let lastTraitSignature, lastTraitSignature != signature {
            invalidateAll(reason: signature.contentSizeCategory != lastTraitSignature.contentSizeCategory
                ? .contentSizeCategoryChanged
                : .widthChanged)
        }
        lastTraitSignature = signature
    }

    private func scheduleSnapshotPublication() {
        guard publicationTask == nil else {
            return
        }

        publicationTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard let self, !Task.isCancelled else { return }
            self.publicationTask = nil
            self.snapshotRevision &+= 1
        }
    }

    nonisolated private static func defaultComputeLayout(
        key: FirePostCellLayoutKey,
        attributedText: NSAttributedString?,
        images: [FireCookedImage],
        trait: FirePostLayoutTraitSignature
    ) -> FirePostCellLayout {
        let contentSizeCategory = UIContentSizeCategory(rawValue: trait.contentSizeCategory)
        let availableWidth = FirePostCellLayoutCalculator.availableContentWidth(
            for: key,
            trait: trait
        )

        let textHeight = FirePostCellLayoutCalculator.measureRichTextHeight(
            attributedText: attributedText,
            containerWidth: availableWidth,
            contentSizeCategory: contentSizeCategory
        )
        let imageHeights = images.map { image in
            FirePostCellLayoutCalculator.imageHeight(for: image, availableWidth: availableWidth)
        }

        return FirePostCellLayoutCalculator.calculate(
            key: key,
            textHeight: textHeight,
            imageHeights: imageHeights,
            trait: trait
        )
    }
}
