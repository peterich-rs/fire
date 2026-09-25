import UIKit

extension FireOnboardingViewController {
    func installKeyboardDismissGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    func observeKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }
    @objc func backgroundTapped() {
        view.endEditing(true)
    }
    @objc func keyboardWillChangeFrame(_ notification: Notification) {
        guard let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }

        let convertedFrame = view.convert(frameEnd, from: nil)
        let overlap = max(0, view.bounds.maxY - convertedFrame.minY - view.safeAreaInsets.bottom)
        let keyboardVisible = overlap > 0

        if keyboardVisible {
            // Pin content above the keyboard; drop vertical centering while editing.
            contentCenterYConstraint?.isActive = false
            contentTopConstraint?.constant = 12
            contentBottomConstraint?.constant = -(overlap + 12)
        } else {
            contentCenterYConstraint?.isActive = true
            contentTopConstraint?.constant = 16
            contentBottomConstraint?.constant = -20
        }

        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
            ?? 0.25
        let curve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
            ?? UIView.AnimationOptions.curveEaseInOut.rawValue
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: UIView.AnimationOptions(rawValue: curve << 16)
        ) {
            self.view.layoutIfNeeded()
        }
    }
}
