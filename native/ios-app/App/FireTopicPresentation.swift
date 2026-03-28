import Foundation
import SwiftUI

struct FireTopicCategoryPresentation: Equatable, Sendable {
    let id: UInt64
    let name: String
    let slug: String
    let parentCategoryID: UInt64?
    let colorHex: String?
    let textColorHex: String?

    var displayName: String {
        name.isEmpty ? "Category #\(id)" : name
    }
}

struct FireTopicRowPresentation: Identifiable, Sendable {
    let topic: TopicSummaryState
    let excerptText: String?
    let lastPosterUsername: String?
    let activityTimestampText: String?
    let statusLabels: [String]
    let tagSummaryText: String?

    var id: UInt64 {
        topic.id
    }
}

enum FireTopicPresentation {
    static func parseCategories(from preloadedJSON: String?) -> [UInt64: FireTopicCategoryPresentation] {
        guard
            let preloadedJSON,
            let data = preloadedJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }

        let candidates: [Any?] = [
            (root["site"] as? [String: Any])?["categories"],
            (root["site"] as? [String: Any])?["category_list"],
            root["categories"],
            root["category_list"],
        ]

        let categories = candidates
            .compactMap { value -> [[String: Any]]? in
                if let dictionaries = value as? [[String: Any]] {
                    return dictionaries
                }
                if let dictionary = value as? [String: Any],
                   let nested = dictionary["categories"] as? [[String: Any]] {
                    return nested
                }
                if let array = value as? [Any] {
                    return array.compactMap { $0 as? [String: Any] }
                }
                return nil
            }
            .first ?? []

        return Dictionary(uniqueKeysWithValues: categories.compactMap { raw in
            guard let id = unsignedInteger(from: raw["id"]) else {
                return nil
            }

            return (
                id,
                FireTopicCategoryPresentation(
                    id: id,
                    name: stringValue(raw["name"]),
                    slug: stringValue(raw["slug"]),
                    parentCategoryID: unsignedInteger(from: raw["parent_category_id"]),
                    colorHex: stringValue(raw["color"]),
                    textColorHex: stringValue(raw["text_color"])
                )
            )
        })
    }

    static func nextPage(from moreTopicsURL: String?) -> UInt32? {
        guard let moreTopicsURL, !moreTopicsURL.isEmpty else {
            return nil
        }

        let candidates = [
            URLComponents(string: moreTopicsURL),
            URLComponents(string: "https://linux.do\(moreTopicsURL)"),
        ]

        for components in candidates {
            guard let queryItems = components?.queryItems else {
                continue
            }
            if let page = queryItems
                .first(where: { $0.name == "page" })?
                .value
                .flatMap(UInt32.init)
            {
                return page
            }
        }

        return nil
    }

    static func formatTimestamp(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let date = fractionalISO8601.date(from: rawValue) ?? basicISO8601.date(from: rawValue)
        guard let date else {
            return rawValue
        }
        return displayFormatter.string(from: date)
    }

    static func plainText(from html: String) -> String {
        guard !html.isEmpty else {
            return ""
        }

        let normalized = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "</li>", with: "\n", options: .regularExpression)
        let stripped = normalized
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return normalizeWhitespace(in: decodeCommonEntities(in: stripped))
    }

    static func previewText(from html: String?) -> String? {
        guard let html, !html.isEmpty else {
            return nil
        }

        let compact = normalizeWhitespace(in: plainText(from: html).replacingOccurrences(of: "\n", with: " "))
        return compact.isEmpty ? nil : compact
    }

    static func attributedText(from html: String) -> AttributedString? {
        guard !html.isEmpty else {
            return nil
        }

        let normalized = html
            .replacingOccurrences(of: "<br\\s*/?>", with: "<br />", options: .regularExpression)

        guard let data = normalized.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else {
            return nil
        }

        return AttributedString(attributed)
    }

    static func buildRowPresentations(from topics: [TopicSummaryState]) -> [FireTopicRowPresentation] {
        let timestampFormatter = TimestampFormatter()

        return topics.map { topic in
            let tagNames = tagNames(from: topic.tags)

            return FireTopicRowPresentation(
                topic: topic,
                excerptText: previewText(from: topic.excerpt),
                lastPosterUsername: topic.lastPosterUsername
                    ?? topic.posters.first?.description
                    ?? topic.posters.first.map { "User \($0.userId)" },
                activityTimestampText: timestampFormatter.format(topic.lastPostedAt ?? topic.createdAt),
                statusLabels: topicStatusLabels(for: topic),
                tagSummaryText: tagNames.isEmpty ? nil : "#\(tagNames.joined(separator: " #"))"
            )
        }
    }

    static func topicStatusLabels(for topic: TopicSummaryState) -> [String] {
        var labels: [String] = []

        if topic.pinned {
            labels.append("Pinned")
        }
        if topic.closed {
            labels.append("Closed")
        }
        if topic.archived {
            labels.append("Archived")
        }
        if topic.hasAcceptedAnswer {
            labels.append("Solved")
        }
        if topic.unreadPosts > 0 {
            labels.append("Unread \(topic.unreadPosts)")
        }
        if topic.newPosts > 0 {
            labels.append("New \(topic.newPosts)")
        }

        return labels
    }

    static func tagNames(from tags: [TopicTagState]) -> [String] {
        tags.compactMap { tag in
            if !tag.name.isEmpty {
                return tag.name
            }
            return tag.slug?.isEmpty == false ? tag.slug : nil
        }
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private static func unsignedInteger(from value: Any?) -> UInt64? {
        switch value {
        case let int as Int:
            return int >= 0 ? UInt64(int) : nil
        case let int64 as Int64:
            return int64 >= 0 ? UInt64(int64) : nil
        case let number as NSNumber:
            let raw = number.int64Value
            return raw >= 0 ? UInt64(raw) : nil
        case let string as String:
            return UInt64(string)
        default:
            return nil
        }
    }

    private static func normalizeWhitespace(in string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeCommonEntities(in string: String) -> String {
        var decoded = string
        let entities = [
            ("&nbsp;", " "),
            ("&#160;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&#34;", "\""),
            ("&#39;", "'"),
            ("&#x27;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
        ]

        for (entity, replacement) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        return decoded
    }
}

private struct TimestampFormatter {
    private let fractionalISO8601: ISO8601DateFormatter
    private let basicISO8601: ISO8601DateFormatter
    private let displayFormatter: DateFormatter

    init() {
        let fractionalISO8601 = ISO8601DateFormatter()
        fractionalISO8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.fractionalISO8601 = fractionalISO8601

        let basicISO8601 = ISO8601DateFormatter()
        basicISO8601.formatOptions = [.withInternetDateTime]
        self.basicISO8601 = basicISO8601

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        displayFormatter.timeStyle = .short
        self.displayFormatter = displayFormatter
    }

    func format(_ rawValue: String?) -> String? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        let date = fractionalISO8601.date(from: rawValue) ?? basicISO8601.date(from: rawValue)
        guard let date else {
            return rawValue
        }

        return displayFormatter.string(from: date)
    }
}

extension Color {
    init?(fireHex hex: String?) {
        guard let hex else {
            return nil
        }

        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .uppercased()
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else {
            return nil
        }

        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
