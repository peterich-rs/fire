import Foundation

enum FireAppRoute: Hashable, Identifiable {
    case topic(topicId: UInt64, postNumber: UInt32?)
    case profile(username: String)
    case badge(id: UInt64, slug: String?)

    var id: String {
        switch self {
        case .topic(let topicId, let postNumber):
            return "topic:\(topicId):\(postNumber.map(String.init) ?? "nil")"
        case .profile(let username):
            return "profile:\(username.lowercased())"
        case .badge(let id, let slug):
            return "badge:\(id):\(slug?.lowercased() ?? "nil")"
        }
    }
}
