import UIKit

@MainActor
extension FireTopicQuickReplyBarView {
    // MARK: - Actions

    @objc func handleClearTarget() {
        callbacks?.onClearTarget()
        inputBar.resignInputFocus()
        callbacks?.onFocusChanged(false)
    }

    // MARK: - Private

    func bindInputBarCallbacks() {
        inputBar.callbacks = .init(
            onTextChanged: { [weak self] text in
                guard let self, !self.applyingState else { return }
                self.callbacks?.onDraftChanged(text)
            },
            onSend: { [weak self] payload in
                self?.callbacks?.onSubmit(payload)
            },
            onLeadingAction: { [weak self] in
                self?.callbacks?.onOpenAdvancedComposer()
            },
            onFocusChanged: { [weak self] focused in
                self?.callbacks?.onFocusChanged(focused)
            },
            onHeightChanged: { [weak self] _ in
                guard let self else { return }
                self.invalidateIntrinsicContentSize()
                self.callbacks?.onHeightChanged()
            },
            onSearchMentions: { [weak self] term in
                await self?.callbacks?.onSearchMentions(term) ?? []
            },
            onPickImage: { [weak self] in
                self?.callbacks?.onPickImage()
            }
        )
    }
}
