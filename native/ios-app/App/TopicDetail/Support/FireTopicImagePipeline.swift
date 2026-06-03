import UIKit

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
