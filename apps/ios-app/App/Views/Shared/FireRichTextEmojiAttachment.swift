import UIKit

extension FireRichTextAttributedStringBuilder {
    static func makeEmojiAttachment(
        urlString: String,
        fallbackText: String,
        font: UIFont,
        onlyEmoji: Bool
    ) -> FireRichTextEmojiAttachment? {
        guard let url = URL(string: urlString) else {
            return nil
        }

        let displaySize = onlyEmoji
            ? max(font.pointSize * 1.9, font.pointSize + 10)
            : max(font.pointSize * 1.15, font.pointSize + 1)

        return FireRichTextEmojiAttachment(
            remoteURL: url,
            fallbackText: fallbackText,
            displaySize: displaySize,
            baselineOffset: font.descender - max(displaySize - font.lineHeight, 0) / 2
        )
    }
}

final class FireRichTextEmojiAttachment: NSTextAttachment {
    let remoteURL: URL
    let fallbackText: String
    let cacheKey: String
    let request: FireRemoteImageRequest

    init(
        remoteURL: URL,
        fallbackText: String,
        displaySize: CGFloat,
        baselineOffset: CGFloat
    ) {
        self.remoteURL = remoteURL
        self.fallbackText = fallbackText
        self.cacheKey = remoteURL.absoluteString
        self.request = FireRemoteImageRequest(url: remoteURL)
        super.init(data: nil, ofType: nil)
        bounds = CGRect(x: 0, y: baselineOffset, width: displaySize, height: displaySize)
        image = Self.placeholderImage(size: displaySize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyLoadedImage(_ loadedImage: UIImage) {
        image = loadedImage.preparingForDisplay() ?? loadedImage
    }

    private static func placeholderImage(size: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: max(size, 1), height: max(size, 1)))
        return renderer.image { _ in }
    }
}
