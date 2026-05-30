import UIKit

struct FireTopicImagePrefetchKey: Hashable {
    let ownerID: String
    let request: FireRemoteImageRequest
}

final class FireTopicImagePrefetchCoordinator {
    private var requestsByOwner: [String: Set<FireRemoteImageRequest>] = [:]

    func prefetch(_ requests: [FireTopicImagePrefetchKey]) {
        var requestsToStart: [FireRemoteImageRequest] = []
        for key in requests {
            guard FireRemoteImagePipeline.shared.cachedImage(for: key.request) == nil else {
                continue
            }
            var ownerRequests = requestsByOwner[key.ownerID, default: []]
            if ownerRequests.insert(key.request).inserted {
                requestsByOwner[key.ownerID] = ownerRequests
                requestsToStart.append(key.request)
            }
        }
        if !requestsToStart.isEmpty {
            FireRemoteImagePipeline.shared.prefetch(requestsToStart)
        }
    }

    func cancel(ownerID: String) {
        guard let requests = requestsByOwner.removeValue(forKey: ownerID), !requests.isEmpty else {
            return
        }
        FireRemoteImagePipeline.shared.stopPrefetching(Array(requests))
    }

    func cancelAll() {
        let requests = requestsByOwner.values.flatMap { Array($0) }
        requestsByOwner.removeAll()
        FireRemoteImagePipeline.shared.stopPrefetching(requests)
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
