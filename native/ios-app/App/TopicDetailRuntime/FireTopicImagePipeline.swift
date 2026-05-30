import UIKit

struct FireTopicImagePrefetchKey: Hashable {
    let ownerID: String
    let request: FireRemoteImageRequest
}

final class FireTopicImagePrefetchCoordinator {
    private var tasks: [FireTopicImagePrefetchKey: Task<Void, Never>] = [:]

    func prefetch(_ requests: [FireTopicImagePrefetchKey]) {
        for key in requests {
            guard tasks[key] == nil,
                  FireRemoteImagePipeline.shared.cachedImage(for: key.request) == nil else {
                continue
            }
            tasks[key] = Task {
                _ = try? await FireRemoteImagePipeline.shared.loadImage(for: key.request)
            }
        }
    }

    func cancel(ownerID: String) {
        for (key, task) in tasks where key.ownerID == ownerID {
            task.cancel()
            tasks.removeValue(forKey: key)
        }
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}

enum FireTopicImageRequestBuilder {
    static func avatarRequest(
        avatarTemplate: String?,
        username: String,
        depth: Int,
        baseURLString: String
    ) -> FireRemoteImageRequest? {
        let visualDepth = FirePostCellLayoutCalculator.visualDepth(for: depth)
        let avatarSize = visualDepth > 0
            ? FirePostCellLayoutCalculator.avatarSizeNested
            : FirePostCellLayoutCalculator.avatarSizeRoot
        guard let url = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: avatarSize,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        ) else {
            return nil
        }
        _ = username
        return FireRemoteImageRequest(url: url)
    }

    static func cookedImageRequest(_ image: FireCookedImage) -> FireRemoteImageRequest {
        FireRemoteImageRequest(url: image.url)
    }
}

typealias FirePostTextureCell = FirePostCollectionViewCell
