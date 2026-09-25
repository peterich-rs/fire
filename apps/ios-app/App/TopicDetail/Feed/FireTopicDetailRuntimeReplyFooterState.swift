import Foundation

enum FireTopicDetailRuntimeReplyFooterState: Equatable {
    case none
    case loadMoreAvailable
    case loadingFooter
    case loadFailed(String)
    case endReached
    case emptyPrompt

    private static let loadFailedPrefix = "loadFailed\u{1F}"

    var contentToken: String {
        switch self {
        case .none:
            return "none"
        case .loadMoreAvailable:
            return "loadMoreAvailable"
        case .loadingFooter:
            return "loadingFooter"
        case let .loadFailed(message):
            return Self.loadFailedPrefix + message
        case .endReached:
            return "endReached"
        case .emptyPrompt:
            return "emptyPrompt"
        }
    }

    var identityToken: String {
        switch self {
        case .none:
            return "none"
        case .loadMoreAvailable:
            return "loadMoreAvailable"
        case .loadingFooter:
            return "loadingFooter"
        case .loadFailed:
            return "loadFailed"
        case .endReached:
            return "endReached"
        case .emptyPrompt:
            return "emptyPrompt"
        }
    }

    static func fromContentToken(_ token: String) -> Self? {
        switch token {
        case Self.none.contentToken:
            return FireTopicDetailRuntimeReplyFooterState.none
        case Self.loadMoreAvailable.contentToken:
            return .loadMoreAvailable
        case Self.loadingFooter.contentToken:
            return .loadingFooter
        case Self.endReached.contentToken:
            return .endReached
        case Self.emptyPrompt.contentToken:
            return .emptyPrompt
        default:
            guard token.hasPrefix(Self.loadFailedPrefix) else {
                return nil
            }
            return .loadFailed(String(token.dropFirst(Self.loadFailedPrefix.count)))
        }
    }
}
