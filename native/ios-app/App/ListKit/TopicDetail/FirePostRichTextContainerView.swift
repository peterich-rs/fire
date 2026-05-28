import UIKit

final class FirePostRichTextContainerView: UIView {
    private let textView = FireRichTextUIView()
    private var linkDelegate: RichTextLinkDelegate?

    var onLinkTapped: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSubviews() {
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        linkDelegate = RichTextLinkDelegate(handler: { [weak self] url in
            self?.onLinkTapped?(url)
        })
        textView.delegate = linkDelegate

        addSubview(textView)
    }

    func configure(
        attributedText: NSAttributedString,
        contentID: String,
        containerSize: CGSize
    ) {
        if textView.renderedContentID != contentID {
            textView.renderedContentID = contentID
            textView.attributedText = attributedText
        }
        textView.frame = CGRect(origin: .zero, size: CGSize(width: containerSize.width, height: containerSize.height))
        textView.invalidateIntrinsicContentSize()
    }

    func resetContent() {
        textView.renderedContentID = nil
        textView.attributedText = NSAttributedString(string: "")
        textView.invalidateIntrinsicContentSize()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        textView.frame = bounds
    }
}

private final class RichTextLinkDelegate: NSObject, UITextViewDelegate {
    private let handler: (URL) -> Void

    init(handler: @escaping (URL) -> Void) {
        self.handler = handler
    }

    func textView(
        _ textView: UITextView,
        shouldInteractWith url: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        handler(url)
        return false
    }
}