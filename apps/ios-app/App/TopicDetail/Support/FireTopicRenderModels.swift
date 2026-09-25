import Foundation
import UIKit

struct FireCookedImage: Identifiable, Hashable, Sendable {
    let url: URL
    let altText: String?
    let width: CGFloat?
    let height: CGFloat?

    var id: String { url.absoluteString }

    var aspectRatio: CGFloat? {
        guard let width, let height, width > 0, height > 0 else {
            return nil
        }
        return width / height
    }
}
struct FireTopicOneboxCard: Hashable, Sendable {
    let url: String?
    let title: String?
    let description: String?
    let sourceName: String?
    let iconURL: URL?
    let thumbnailURL: URL?
    let thumbnailWidth: CGFloat?
    let thumbnailHeight: CGFloat?
}
struct FireTopicPostRenderSignature: Hashable, Sendable {
    let sourceLength: Int
    let sourceChecksum: UInt64
    let segmentIDs: [String]

    var token: String {
        var parts: [String] = []
        parts.reserveCapacity(segmentIDs.count + 2)
        parts.append(String(sourceLength))
        parts.append(String(sourceChecksum, radix: 16))
        parts.append(contentsOf: segmentIDs)
        return parts.joined(separator: ":")
    }

    static func make(
        source: String,
        imageAttachments: [FireCookedImage],
        segments: [FireTopicPostRenderSegment] = []
    ) -> Self {
        FireTopicPostRenderSignature(
            sourceLength: source.utf8.count,
            sourceChecksum: stableChecksum(source),
            segmentIDs: segments.isEmpty
                ? imageAttachments.map { "image:\($0.id)" }
                : segments.map(\.signatureToken)
        )
    }

    fileprivate static func stableChecksum(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        hash ^= hash >> 33
        hash &*= 0xff51afd7ed558ccd
        hash ^= hash >> 33
        hash &*= 0xc4ceb9fe1a85ec53
        hash ^= hash >> 33
        return hash
    }
}
// NSAttributedString is not Sendable; render content is built during cache preparation and then shared immutably.
struct FireTopicPostRenderContent: @unchecked Sendable {
    let plainText: String
    let attributedText: NSAttributedString?
    let imageAttachments: [FireCookedImage]
    let segments: [FireTopicPostRenderSegment]
    let signature: FireTopicPostRenderSignature
}
// NSAttributedString is immutable after construction and segment values are only read by the UI layer.
enum FireTopicPostRenderSegment: @unchecked Sendable {
    case text(NSAttributedString)
    case image(FireCookedImage)
    case onebox(FireTopicOneboxCard)

    var signatureToken: String {
        switch self {
        case .text(let attributedText):
            return "text:\(attributedText.string.utf8.count):\(FireTopicPostRenderSignature.stableChecksum(attributedText.string))"
        case .image(let image):
            return "image:\(image.id)"
        case .onebox(let card):
            return "onebox:\(card.url ?? ""):\(card.thumbnailURL?.absoluteString ?? ""):\(card.title ?? "")"
        }
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    var isOnebox: Bool {
        if case .onebox = self { return true }
        return false
    }

    enum Kind: Hashable {
        case text
        case image
        case onebox
    }

    var kind: Kind {
        switch self {
        case .text: return .text
        case .image: return .image
        case .onebox: return .onebox
        }
    }
}
struct FireTopicPostRenderInput: Equatable, Sendable {
    let presentationChecksum: UInt64?
}
struct FireTopicDetailRenderState: Sendable {
    let originalRow: FirePreparedTopicTimelineRow?
    let replyRows: [FirePreparedTopicTimelineRow]
    let contentByPostID: [UInt64: FireTopicPostRenderContent]
}
struct FireTopicDetailRenderCache: Sendable {
    let baseURLString: String
    let rowInputs: [FireTopicTimelineRowInput]
    let contentInputsByPostID: [UInt64: FireTopicPostRenderInput]
    let renderState: FireTopicDetailRenderState
}
