import Combine
import UIKit

@MainActor
extension FireTopicDetailViewController {
    func subscribeToKeyboardNotifications() {
        // Deliver synchronously on the posting thread (main). Do not hop through
        // RunLoop.main / DispatchQueue.main — that defers handling by a turn and
        // makes the quick-reply bar lag behind the keyboard after swipe-to-reply.
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification))
            .sink { [weak self] notification in
                self?.handleKeyboardNotification(notification)
            }
            .store(in: &cancellables)
    }

    func handleKeyboardNotification(_ notification: Notification) {
        if notification.name == UIResponder.keyboardWillHideNotification {
            keyboardFrameInScreen = .null
        } else {
            keyboardFrameInScreen =
                (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
        }
        updateBottomChromeInset(animatedWith: notification)
    }

    func updateBottomChromeInset(animatedWith notification: Notification? = nil) {
        // WeChat-style bottom input — pure UIKit, no Texture overlay:
        //
        // 1) Bar internal bottom padding
        //    - keyboard hidden → home-indicator safe area
        //    - keyboard up     → small pad (keyboard covers home indicator)
        // 2) Keyboard overlap → bar bottom constraint constant
        // 3) Feed contentInset.bottom = barHeight + keyboardOverlap
        let keyboardOverlap = keyboardOverlapHeight
        let keyboardVisible = keyboardOverlap > 0.5
        let homeIndicator = view.safeAreaInsets.bottom
        let barBottomPadding: CGFloat = keyboardVisible ? 8 : homeIndicator

        quickReplyBar.updateBottomInset(barBottomPadding)

        let previousBottom = quickReplyBottomConstraint?.constant ?? 0
        let previousHeight = quickReplyHeightConstraint?.constant ?? 0
        let measuredBarHeight = quickReplyBar.preferredHeight(forWidth: max(view.bounds.width, 1))
        quickReplyBottomConstraint?.constant = -keyboardOverlap
        quickReplyHeightConstraint?.constant = measuredBarHeight

        let barVisible = !quickReplyBar.isHidden
        let feedBottom = fireTopicDetailFeedBottomInset(
            quickReplyBarHeight: measuredBarHeight,
            safeAreaBottom: homeIndicator,
            keyboardOverlap: keyboardOverlap,
            isQuickReplyVisible: barVisible
        )
        rootNode.updateFeedBottomInset(feedBottom)
        updateFeedTopInset()
        view.bringSubviewToFront(quickReplyBar)

        let geometryChanged =
            abs(previousBottom + keyboardOverlap) > 0.5
            || abs(previousHeight - measuredBarHeight) > 0.5

        guard geometryChanged || notification != nil else { return }

        if let notification {
            let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?
                .doubleValue ?? 0.25
            let curveRawValue = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?
                .uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
            // Keyboard uses a private curve (rawValue 7). Shift into
            // UIView.AnimationOptions so the bar tracks the system animation.
            let options = UIView.AnimationOptions(rawValue: curveRawValue << 16)
            UIView.animate(
                withDuration: duration,
                delay: 0,
                options: [options, .beginFromCurrentState, .allowUserInteraction]
            ) {
                self.view.layoutIfNeeded()
            }
        }
        // Non-keyboard geometry commits on the next layout pass, or via an
        // explicit layoutIfNeeded() in presentQuickReplyInput() before focus.
    }

    var currentSearchBarHeight: CGFloat {
        topicSearchBar.isHidden ? 0 : topicSearchBar.bounds.height
    }

    var keyboardOverlapHeight: CGFloat {
        guard !keyboardFrameInScreen.isNull else {
            return 0
        }
        let frameInView = view.convert(keyboardFrameInScreen, from: nil)
        return max(view.bounds.intersection(frameInView).height, 0)
    }
}
