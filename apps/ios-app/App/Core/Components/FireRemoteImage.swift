import Nuke
import SwiftUI
import UIKit

struct FireRemoteImageRequest: Hashable, Sendable {
    let url: URL

    var cacheKey: String {
        url.absoluteString
    }
}

typealias FireAvatarImageRequest = FireRemoteImageRequest

enum FireRemoteImagePipelineError: Error {
    case badServerResponse
    case invalidImageData
}

typealias FireAvatarImagePipelineError = FireRemoteImagePipelineError

final class FireRemoteImageMemoryCache: @unchecked Sendable {
    static let shared = FireRemoteImageMemoryCache()

    private let storage: NSCache<NSString, UIImage>

    init(
        countLimit: Int = 256,
        totalCostLimit: Int = 48 * 1024 * 1024,
        storage: NSCache<NSString, UIImage> = NSCache<NSString, UIImage>()
    ) {
        self.storage = storage
        self.storage.countLimit = countLimit
        self.storage.totalCostLimit = totalCostLimit
    }

    func image(for key: String) -> UIImage? {
        storage.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        storage.setObject(image, forKey: key as NSString, cost: image.fireMemoryCost)
    }

    func removeAllObjects() {
        storage.removeAllObjects()
    }
}

typealias FireAvatarImageMemoryCache = FireRemoteImageMemoryCache

final class FireRemoteImagePipeline: @unchecked Sendable {
    static let shared = FireRemoteImagePipeline(pipeline: makeDefaultPipeline())

    private let pipeline: ImagePipeline
    private let prefetcher: ImagePrefetcher

    init(pipeline: ImagePipeline = makeDefaultPipeline()) {
        self.pipeline = pipeline
        self.prefetcher = ImagePrefetcher(pipeline: pipeline)
    }

    func cachedImage(for request: FireRemoteImageRequest) -> UIImage? {
        pipeline.cache.cachedImage(for: nukeRequest(for: request))?.image
    }

    func loadImage(for request: FireRemoteImageRequest) async throws -> UIImage {
        try await pipeline.image(for: nukeRequest(for: request))
    }

    func prefetch(_ requests: [FireRemoteImageRequest]) {
        prefetcher.startPrefetching(with: requests.map(nukeRequest(for:)))
    }

    func stopPrefetching(_ requests: [FireRemoteImageRequest]) {
        prefetcher.stopPrefetching(with: requests.map(nukeRequest(for:)))
    }

    private static func makeDefaultPipeline() -> ImagePipeline {
        ImagePipeline(
            configuration: .withDataCache(
                name: "com.fire.remote-images",
                sizeLimit: 128 * 1024 * 1024
            )
        )
    }

    private func nukeRequest(for request: FireRemoteImageRequest) -> ImageRequest {
        ImageRequest(url: request.url)
    }
}

typealias FireAvatarImagePipeline = FireRemoteImagePipeline

enum FireRemoteImagePlaceholderState: Equatable {
    case loading
    case failure
    case missingRequest
}

struct FireRemoteImage<Content: View, Placeholder: View>: View {
    let request: FireRemoteImageRequest?
    private let content: (UIImage) -> Content
    private let placeholder: (FireRemoteImagePlaceholderState) -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedImageKey: String?
    @State private var loadFailed = false

    init(
        request: FireRemoteImageRequest?,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping (FireRemoteImagePlaceholderState) -> Placeholder
    ) {
        self.request = request
        self.content = content
        self.placeholder = placeholder
    }

    private var resolvedImage: UIImage? {
        guard let request else {
            return nil
        }
        if loadedImageKey == request.cacheKey, let loadedImage {
            return loadedImage
        }
        return FireRemoteImagePipeline.shared.cachedImage(for: request)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                content(resolvedImage)
            } else if request != nil {
                placeholder(loadFailed ? .failure : .loading)
            } else {
                placeholder(.missingRequest)
            }
        }
        .task(id: request?.cacheKey) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard let request else {
            loadedImage = nil
            loadedImageKey = nil
            loadFailed = false
            return
        }

        if loadedImageKey == request.cacheKey, loadedImage != nil {
            loadFailed = false
            return
        }

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            loadedImage = cachedImage
            loadedImageKey = request.cacheKey
            loadFailed = false
            return
        }

        if loadedImageKey != request.cacheKey {
            loadedImage = nil
            loadedImageKey = nil
        }
        loadFailed = false

        do {
            let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
            guard !Task.isCancelled else {
                return
            }
            loadedImage = image
            loadedImageKey = request.cacheKey
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            loadFailed = true
        }
    }
}

private extension UIImage {
    var fireMemoryCost: Int {
        guard let cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}
