import UIKit

enum FireTopicDetailToolbarChromeMetrics {
    /// Approximate distance from the header cell top to below its title band.
    static let headerTitleBandHeight: CGFloat = 52

    static func isTitlePinned(
        headerFrame: CGRect?,
        visibleTop: CGFloat
    ) -> Bool {
        if let headerFrame {
            return headerFrame.minY + headerTitleBandHeight <= visibleTop + 0.5
        }
        return visibleTop > 24
    }
}

enum FireTopicDetailToolbarTitleMetrics {
    static let minimumHeight: CGFloat = 24

    /// Title views must not publish a content-sized width.
    ///
    /// Publishing the text width (even capped) makes `UINavigationBar` treat the
    /// title as a fixed peer of the trailing actions, so long titles shove icons
    /// toward — or past — the screen edge. Request expanded width instead; the
    /// bar assigns leftover space between back and actions, and the label
    /// truncates inside those bounds.
    static func preferredIntrinsicSize(
        isVisible: Bool,
        labelHeight: CGFloat
    ) -> CGSize {
        let height = max(labelHeight, minimumHeight)
        guard isVisible else {
            return CGSize(width: UIView.noIntrinsicMetric, height: height)
        }
        return CGSize(
            width: UIView.layoutFittingExpandedSize.width,
            height: height
        )
    }
}
