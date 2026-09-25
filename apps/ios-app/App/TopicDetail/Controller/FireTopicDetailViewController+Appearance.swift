import Combine
import UIKit

@MainActor
extension FireTopicDetailViewController {
    func bindColorAppearanceObservers() {
        // Single bus from Environment (preference write / storage sync). Avoid also
        // listening to the NotificationCenter name here — same event would re-apply twice.
        FireAppearanceEnvironment.snapshotPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.applyAppearance(snapshot)
            }
            .store(in: &appearanceCancellables)
    }

    func handleColorAppearanceChange(reason: String) {
        let snapshot = FireAppearanceEnvironment.snapshot(for: view, window: view.window)
        applyAppearance(snapshot)
        viewModel.topicDetailLogger()?.debug(
            "topic detail appearance reason=\(reason) token=\(snapshot.token)"
        )
    }

    /// Shell layers that sit outside factory cell rebuilds (VC view + Texture root).
    func applyAppearanceShell(_ snapshot: FireAppearanceSnapshot? = nil) {
        let resolved = snapshot ?? FireAppearanceEnvironment.snapshot(for: view, window: view.window)
        FireAppearanceTexture.applySnapshot(resolved, to: view)
        rootNode.applyAppearance(resolved)
        feedController.assertFeedShellAppearance(resolved)
        configureNavigationAppearance()
    }
}

extension FireTopicDetailViewController: FireAppearanceApplying {
    func applyAppearance(_ snapshot: FireAppearanceSnapshot) {
        let style = snapshot.userInterfaceStyle
        let styleChanged = lastColorAppearanceStyle != style
        lastColorAppearanceStyle = style
        viewModel.topicDetailLogger()?.info(
            "topic detail applyAppearance topic_id=\(row.topic.id) style=\(style.rawValue) token=\(snapshot.token) style_changed=\(styleChanged)"
        )
        applyAppearanceShell(snapshot)
        quickReplyBar.applyThemeColorsIfNeeded()
        feedController.refreshColorAppearance(snapshot)
    }
}
