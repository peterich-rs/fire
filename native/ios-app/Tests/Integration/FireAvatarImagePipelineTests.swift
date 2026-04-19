import XCTest
import UIKit
import SwiftUI
@testable import Fire

final class FireAvatarImagePipelineTests: XCTestCase {
    func testAvatarURLReplacesTemplateSizeAndResolvesRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 34,
            scale: 3,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://linux.do/user_avatar/linux.do/alice/102/1_2.png"
        )
    }

    func testAvatarURLSupportsProtocolRelativePath() {
        let url = fireAvatarURL(
            avatarTemplate: "//cdn.linux.do/user_avatar/linux.do/alice/{size}/1_2.png",
            size: 32,
            scale: 2,
            baseURLString: "https://linux.do"
        )

        XCTAssertEqual(
            url?.absoluteString,
            "https://cdn.linux.do/user_avatar/linux.do/alice/64/1_2.png"
        )
    }

    func testAvatarPipelineCachesSuccessfulLoadForSynchronousReuse() async throws {
        let counter = FireAvatarImageLoadCounter()
        let cache = FireAvatarImageMemoryCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        let pipeline = FireAvatarImagePipeline(memoryCache: cache) { _ in
            counter.increment()
            return try XCTUnwrap(Self.makeTestImageData())
        }
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/avatar.png"))
        )

        XCTAssertNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.loadImage(for: request)

        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(pipeline.cachedImage(for: request))

        _ = try await pipeline.loadImage(for: request)

        XCTAssertEqual(counter.value, 1)
    }

    func testAvatarPipelineCoalescesConcurrentLoadsForSameURL() async throws {
        let counter = FireAvatarImageLoadCounter()
        let cache = FireAvatarImageMemoryCache(countLimit: 8, totalCostLimit: 1_024 * 1_024)
        let pipeline = FireAvatarImagePipeline(memoryCache: cache) { _ in
            counter.increment()
            try await Task.sleep(nanoseconds: 20_000_000)
            return try XCTUnwrap(Self.makeTestImageData())
        }
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(URL(string: "https://example.com/avatar.png"))
        )

        async let firstImage = pipeline.loadImage(for: request)
        async let secondImage = pipeline.loadImage(for: request)

        _ = try await (firstImage, secondImage)

        XCTAssertEqual(counter.value, 1)
    }

    @MainActor
    func testAvatarViewRendersWarmCachedImageOnInitialRender() throws {
        let size: CGFloat = 40
        let avatarTemplate = "/user_avatar/linux.do/alice/{size}/1_2.png"
        let request = FireAvatarImageRequest(
            url: try XCTUnwrap(
                fireAvatarURL(
                    avatarTemplate: avatarTemplate,
                    size: size,
                    scale: UIScreen.main.scale,
                    baseURLString: "https://linux.do"
                )
            )
        )
        let expectedColor = UIColor(red: 0.04, green: 0.82, blue: 0.99, alpha: 1)

        FireAvatarImageMemoryCache.shared.removeAllObjects()
        addTeardownBlock {
            FireAvatarImageMemoryCache.shared.removeAllObjects()
        }

        let cachedImage = Self.makeSolidTestImage(color: expectedColor, size: CGSize(width: size, height: size))
        FireAvatarImageMemoryCache.shared.insert(cachedImage, for: request.cacheKey)

        let renderedImage = try XCTUnwrap(
            Self.renderAvatarView(
                FireAvatarView(avatarTemplate: avatarTemplate, username: "alice", size: size),
                size: CGSize(width: size, height: size)
            )
        )
        let centerColor = try XCTUnwrap(renderedImage.fireColor(at: CGPoint(x: size / 2, y: size / 2)))

        XCTAssertTrue(centerColor.fireIsApproximatelyEqual(to: expectedColor, tolerance: 0.08))
    }

    private static func makeTestImageData() -> Data? {
        makeSolidTestImage(color: .systemOrange, size: CGSize(width: 4, height: 4)).pngData()
    }

    private static func makeSolidTestImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        return image
    }

    @MainActor
    private static func renderAvatarView(_ view: FireAvatarView, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

private final class FireAvatarImageLoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        storage += 1
    }
}

private extension UIImage {
    func fireColor(at point: CGPoint) -> UIColor? {
        guard let cgImage else {
            return nil
        }

        let pixelX = min(max(Int(point.x * scale), 0), cgImage.width - 1)
        let pixelY = min(max(Int(point.y * scale), 0), cgImage.height - 1)
        guard let pixelImage = cgImage.cropping(to: CGRect(x: pixelX, y: pixelY, width: 1, height: 1)) else {
            return nil
        }

        var pixelData = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return UIColor(
            red: CGFloat(pixelData[0]) / 255,
            green: CGFloat(pixelData[1]) / 255,
            blue: CGFloat(pixelData[2]) / 255,
            alpha: CGFloat(pixelData[3]) / 255
        )
    }
}

private extension UIColor {
    func fireIsApproximatelyEqual(to other: UIColor, tolerance: CGFloat) -> Bool {
        guard let lhs = fireRGBA, let rhs = other.fireRGBA else {
            return false
        }

        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    private var fireRGBA: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return (red, green, blue, alpha)
    }
}