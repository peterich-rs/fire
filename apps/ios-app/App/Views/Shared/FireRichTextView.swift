import SwiftUI
import UIKit

/// A UIViewRepresentable that displays rich attributed text with interactive links.
struct FireRichTextView: UIViewRepresentable {
    let contentID: String
    let attributedString: NSAttributedString
    let onLinkTapped: ((URL) -> Void)?

    init(
        contentID: String,
        attributedString: NSAttributedString,
        onLinkTapped: ((URL) -> Void)? = nil
    ) {
        self.contentID = contentID
        self.attributedString = attributedString
        self.onLinkTapped = onLinkTapped
    }

    func makeUIView(context: Context) -> FireRichTextUIView {
        let view = FireRichTextUIView()
        view.isEditable = false
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.backgroundColor = .clear
        view.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ uiView: FireRichTextUIView, context: Context) {
        if uiView.renderedContentID != contentID {
            uiView.renderedContentID = contentID
            uiView.attributedText = attributedString
            uiView.invalidateIntrinsicContentSize()
        }
        context.coordinator.onLinkTapped = onLinkTapped
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTapped: ((URL) -> Void)?

        init(onLinkTapped: ((URL) -> Void)?) {
            self.onLinkTapped = onLinkTapped
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            onLinkTapped?(URL)
            return false
        }
    }
}
