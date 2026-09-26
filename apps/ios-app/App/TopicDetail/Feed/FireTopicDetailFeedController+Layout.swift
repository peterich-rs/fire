import AsyncDisplayKit
import UIKit

@MainActor
extension FireTopicDetailFeedController {
    static func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = 0
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.estimatedItemSize = .zero
        return flowLayout
    }

    func configureTextureRanges() {
        collectionNode.leadingScreensForBatching = 1.0

        var displayTuning = ASRangeTuningParameters()
        displayTuning.leadingBufferScreenfuls = 1.0
        displayTuning.trailingBufferScreenfuls = 0.5
        collectionNode.setTuningParameters(displayTuning, for: .display)

        var preloadTuning = ASRangeTuningParameters()
        preloadTuning.leadingBufferScreenfuls = 1.0
        preloadTuning.trailingBufferScreenfuls = 0.5
        collectionNode.setTuningParameters(preloadTuning, for: .preload)
    }
}
