import Foundation

enum FireRouteParser {
    private enum TopicPathStyle {
        case fireScheme
        case linuxDoWeb
    }

    private struct ParsedTopicPath {
        let topicId: UInt64
        let postNumber: UInt32?
    }

    static func parse(url: URL) -> FireAppRoute? {
        let scheme = url.scheme?.lowercased()
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch scheme {
        case "fire":
            return parseFireURL(url, components: components)
        case "http", "https":
            return parseLinuxDoURL(url, components: components)
        default:
            return nil
        }
    }

    static func route(fromNotificationUserInfo userInfo: [AnyHashable: Any]) -> FireAppRoute? {
        guard let topicId = integerUInt64(from: userInfo["topicId"]) else {
            return nil
        }
        let postNumber = integerUInt32(from: userInfo["postNumber"])
        let preview = FireTopicRoutePreview.fromMetadata(
            title: stringValue(from: userInfo["topicTitle"]) ?? stringValue(from: userInfo["title"]),
            slug: stringValue(from: userInfo["slug"]),
            excerptText: stringValue(from: userInfo["excerpt"])
        )
        return .topic(topicId: topicId, postNumber: postNumber, preview: preview)
    }

    private static func parseFireURL(
        _ url: URL,
        components: URLComponents?
    ) -> FireAppRoute? {
        var segments = pathSegments(from: url)
        if let host = normalizedSegment(url.host), !host.isEmpty {
            segments.insert(host, at: 0)
        }

        guard let head = segments.first?.lowercased() else {
            return nil
        }

        switch head {
        case "topic":
            return parseTopic(
                segments: Array(segments.dropFirst()),
                components: components,
                style: .fireScheme
            )
        case "user", "profile":
            return parseProfile(segments: Array(segments.dropFirst()))
        case "badge", "badges":
            return parseBadge(segments: Array(segments.dropFirst()), components: components)
        default:
            return nil
        }
    }

    private static func parseLinuxDoURL(
        _ url: URL,
        components: URLComponents?
    ) -> FireAppRoute? {
        guard let host = url.host?.lowercased(),
              host == "linux.do" || host.hasSuffix(".linux.do") else {
            return nil
        }

        let segments = pathSegments(from: url)
        guard let head = segments.first?.lowercased() else {
            return nil
        }

        switch head {
        case "t":
            return parseTopic(
                segments: Array(segments.dropFirst()),
                components: components,
                style: .linuxDoWeb
            )
        case "u":
            return parseProfile(segments: Array(segments.dropFirst()))
        case "badge", "badges":
            return parseBadge(segments: Array(segments.dropFirst()), components: components)
        default:
            return nil
        }
    }

    private static func parseTopic(
        segments: [String],
        components: URLComponents?,
        style: TopicPathStyle
    ) -> FireAppRoute? {
        let normalized = segments.compactMap(normalizedSegment)
        guard let topicPath = parseTopicPath(normalized, style: style) else {
            return nil
        }

        let postNumberFromQuery = components?.queryItems?.first {
            $0.name.caseInsensitiveCompare("postNumber") == .orderedSame
        }?.value.flatMap(UInt32.init)

        return .topic(topicId: topicPath.topicId, postNumber: postNumberFromQuery ?? topicPath.postNumber)
    }

    private static func parseTopicPath(
        _ normalized: [String],
        style: TopicPathStyle
    ) -> ParsedTopicPath? {
        switch style {
        case .fireScheme:
            guard let head = normalized.first,
                  let topicId = UInt64(head) else {
                return nil
            }
            let postNumber = normalized.dropFirst().first.flatMap(UInt32.init)
            return ParsedTopicPath(topicId: topicId, postNumber: postNumber)
        case .linuxDoWeb:
            guard let tail = normalized.last else {
                return nil
            }

            if normalized.count >= 3,
               let postNumber = UInt32(tail),
               let topicId = UInt64(normalized[normalized.count - 2]) {
                return ParsedTopicPath(topicId: topicId, postNumber: postNumber)
            }

            guard let topicId = UInt64(tail) else {
                return nil
            }
            return ParsedTopicPath(topicId: topicId, postNumber: nil)
        }
    }

    private static func parseProfile(segments: [String]) -> FireAppRoute? {
        guard let username = segments.compactMap(normalizedSegment).first else {
            return nil
        }
        return .profile(username: username)
    }

    private static func parseBadge(
        segments: [String],
        components: URLComponents?
    ) -> FireAppRoute? {
        let normalized = segments.compactMap(normalizedSegment)
        guard let badgeIndex = normalized.firstIndex(where: { UInt64($0) != nil }),
              let badgeId = UInt64(normalized[badgeIndex]) else {
            return nil
        }

        let querySlug = components?.queryItems?.first {
            $0.name.caseInsensitiveCompare("slug") == .orderedSame
        }?.value.flatMap(normalizedSegment)

        let nextSlug = normalized.dropFirst(badgeIndex + 1).first(where: { UInt64($0) == nil })
        let previousSlug = badgeIndex > 0 ? normalized[badgeIndex - 1] : nil
        let slug = querySlug ?? nextSlug ?? (UInt64(previousSlug ?? "") == nil ? previousSlug : nil)

        return .badge(id: badgeId, slug: slug)
    }

    private static func pathSegments(from url: URL) -> [String] {
        url.path
            .split(separator: "/")
            .compactMap { normalizedSegment(String($0)) }
    }

    private static func normalizedSegment(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix(".json") {
            let value = String(trimmed.dropLast(5))
            return value.isEmpty ? nil : value
        }

        return trimmed
    }

    private static func integerUInt64(from value: Any?) -> UInt64? {
        switch value {
        case let value as UInt64:
            return value
        case let value as Int64:
            return value >= 0 ? UInt64(value) : nil
        case let value as UInt32:
            return UInt64(value)
        case let value as Int:
            return value >= 0 ? UInt64(value) : nil
        case let value as NSNumber:
            return value.uint64Value
        case let value as String:
            return UInt64(value)
        default:
            return nil
        }
    }

    private static func integerUInt32(from value: Any?) -> UInt32? {
        switch value {
        case let value as UInt32:
            return value
        case let value as Int:
            return value >= 0 ? UInt32(value) : nil
        case let value as NSNumber:
            return value.uint32Value
        case let value as String:
            return UInt32(value)
        default:
            return nil
        }
    }

    private static func stringValue(from value: Any?) -> String? {
        guard let value else {
            return nil
        }
        switch value {
        case let value as String:
            return normalizedSegment(value)
        case let value as NSString:
            return normalizedSegment(value as String)
        default:
            return nil
        }
    }
}
