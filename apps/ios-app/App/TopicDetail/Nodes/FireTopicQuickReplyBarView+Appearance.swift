import UIKit

@MainActor
extension FireTopicQuickReplyBarView {

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }
        applyThemeColorsIfNeeded()
    }

    /// Re-resolve opaque canvas colors after appearance preference changes.
    func applyThemeColorsIfNeeded() {
        let canvas = FireTheme.uiCanvas.resolvedColor(with: traitCollection)
        backgroundColor = canvas
        backgroundFill.backgroundColor = canvas
        topBorderView.backgroundColor = FireTheme.uiDivider
        tintColor = FireTheme.uiAccent
        inputBar.applyThemeColorsIfNeeded()
    }
}
