import Foundation

enum FireSearchCollectionSection: Int, Hashable {
    case content
}

enum FireSearchCollectionItem: Hashable {
    case placeholder
    case loading(Int)
    case blockingError(String)
    case inlineErrorBanner(String)
    case sectionHeader(String)
    case topic(UInt64)
    case post(UInt64)
    case user(UInt64)
    case loadMore
    case empty
}
