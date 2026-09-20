import AsyncDisplayKit
import UIKit

final class FirePostImageNode: ASControlNode {
    let image: FireCookedImage
    var onTap: (() -> Void)?
    private let imageNode = ASImageNode()
    private let statusNode = ASTextNode()
    private let retryNode = ASButtonNode()
    private var renderSize: CGSize
    private var loadTask: Task<Void, Never>?
    private var loadGeneration: UInt64 = 0
    private var isLoaded = false
    private var isLoading = false
    private var didFail = false
    private lazy var tapGestureRecognizer: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        gesture.cancelsTouchesInView = false
        return gesture
    }()

    init(image: FireCookedImage, renderSize: CGSize) {
        self.image = image
        self.renderSize = renderSize
        super.init()
        automaticallyManagesSubnodes = true
        isUserInteractionEnabled = true
        backgroundColor = .clear
        isOpaque = false
        accessibilityLabel = image.altText?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("帖子图片")
        accessibilityTraits = [.image, .button]

        imageNode.contentMode = .scaleAspectFit
        imageNode.clipsToBounds = true
        imageNode.cornerRadius = 4
        imageNode.borderColor = UIColor.separator.cgColor
        imageNode.borderWidth = 0.5
        imageNode.backgroundColor = .tertiarySystemFill
        imageNode.isUserInteractionEnabled = false
        // Sync display avoids intermittent blank bitmaps after theme rebinds / cell reuse.
        imageNode.displaysAsynchronously = false
        imageNode.isOpaque = false

        statusNode.maximumNumberOfLines = 2
        statusNode.isLayerBacked = true
        statusNode.isOpaque = false
        statusNode.backgroundColor = .clear
        statusNode.displaysAsynchronously = false

        retryNode.setAttributedTitle(NSAttributedString(
            string: "重试",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: UIColor.systemBlue,
            ]
        ), for: .normal)
        retryNode.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        retryNode.cornerRadius = 12
        retryNode.borderWidth = 1
        retryNode.borderColor = UIColor.systemBlue.withAlphaComponent(0.45).cgColor
        retryNode.backgroundColor = FireTheme.uiCanvas.withAlphaComponent(0.8)
        retryNode.addTarget(self, action: #selector(handleRetryTap), forControlEvents: .touchUpInside)
        retryNode.fireBindPressBounce(.compact)

        updateRenderSize(renderSize)
        loadImage()
    }

    override func didLoad() {
        super.didLoad()
        view.addGestureRecognizer(tapGestureRecognizer)
    }

    deinit {
        loadTask?.cancel()
    }

    func updateRenderSize(_ renderSize: CGSize) {
        let didChange = self.renderSize != renderSize
        self.renderSize = renderSize
        style.preferredSize = renderSize
        imageNode.style.preferredSize = renderSize
        if didChange {
            if isLoaded {
                loadImage()
            }
            setNeedsLayout()
        }
    }

    override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        let maxWidth = constrainedSize.max.width.isFinite
            ? min(renderSize.width, constrainedSize.max.width)
            : renderSize.width
        let ratio = renderSize.height / max(renderSize.width, 1)
        let boundedSize = CGSize(width: max(maxWidth, 1), height: max(maxWidth * ratio, 1))
        imageNode.style.preferredSize = boundedSize
        guard !isLoaded else {
            return ASWrapperLayoutSpec(layoutElement: imageNode)
        }

        statusNode.attributedText = statusAttributedText()
        retryNode.isHidden = !didFail

        let statusChildren: [ASLayoutElement] = didFail ? [statusNode, retryNode] : [statusNode]
        let statusStack = ASStackLayoutSpec(
            direction: .vertical,
            spacing: 8,
            justifyContent: .center,
            alignItems: .center,
            children: statusChildren
        )
        statusStack.style.maxWidth = ASDimensionMake(max(boundedSize.width - 24, 1))

        let centeredStatus = ASCenterLayoutSpec(
            centeringOptions: .XY,
            sizingOptions: [],
            child: statusStack
        )
        centeredStatus.style.preferredSize = boundedSize

        return ASOverlayLayoutSpec(child: imageNode, overlay: centeredStatus)
    }

    private func loadImage() {
        loadTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration
        let request = FireTopicImageRequestBuilder.cookedImageRequest(image)

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            applyLoadedImage(cachedImage, generation: generation)
            return
        }

        isLoaded = false
        isLoading = true
        didFail = false
        imageNode.image = nil
        setNeedsLayout()

        loadTask = Task { [weak self] in
            do {
                let resolvedImage = try await FireRemoteImagePipeline.shared.loadImage(for: request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyLoadedImage(resolvedImage, generation: generation)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.applyFailedLoad(generation: generation)
                }
            }
        }
    }

    private func applyLoadedImage(_ loadedImage: UIImage, generation: UInt64) {
        guard generation == loadGeneration else { return }
        let displayImage = thumbnailImage(for: loadedImage)
        // Prefer a non-nil displayable bitmap; fall back to the source image if
        // thumbnail generation returns nil for odd source formats.
        imageNode.image = displayImage ?? loadedImage
        isLoaded = imageNode.image != nil
        isLoading = false
        didFail = !isLoaded
        imageNode.setNeedsDisplay()
        setNeedsLayout()
        setNeedsDisplay()
    }

    private func applyFailedLoad(generation: UInt64) {
        guard generation == loadGeneration else { return }
        isLoaded = false
        isLoading = false
        didFail = true
        imageNode.image = nil
        setNeedsLayout()
        setNeedsDisplay()
    }

    @objc private func handleRetryTap() {
        loadImage()
    }

    @objc private func handleTapGesture(_ gestureRecognizer: UITapGestureRecognizer) {
        guard gestureRecognizer.state == .ended, !didFail else {
            return
        }
        onTap?()
    }

    private func statusAttributedText() -> NSAttributedString {
        let text = didFail ? "图片加载失败" : "图片加载中..."
        // Bake subtle ink for the live trait environment so layer-backed status
        // text stays readable on both light paper and pure-black canvases.
        let traits = FireTextureAttributedText.colorTraits(from: isNodeLoaded ? view : nil)
        let ink = FireTextureAttributedText.subtleInk(with: traits)
        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .caption1),
                .foregroundColor: ink,
            ]
        )
    }

    private func thumbnailImage(for image: UIImage) -> UIImage? {
        // May run on a decode queue — avoid UIScreen.main off the main thread.
        let scale: CGFloat = Thread.isMainThread ? UIScreen.main.scale : 3
        let targetSize = CGSize(
            width: max(renderSize.width * scale, 1),
            height: max(renderSize.height * scale, 1)
        )
        // Skip thumbnail when the source is already smaller than the target so we
        // do not replace a valid bitmap with a nil / empty prepare result.
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        if pixelWidth <= targetSize.width + 0.5, pixelHeight <= targetSize.height + 0.5 {
            return image.preparingForDisplay() ?? image
        }
        return image.preparingThumbnail(of: targetSize)
            ?? image.preparingForDisplay()
            ?? image
    }
}
