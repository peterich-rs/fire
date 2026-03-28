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

        if let data = normalized.data(using: .utf8),
           let attributed = try? NSAttributedString(
               data: data,
               options: [
                   .documentType: NSAttributedString.DocumentType.html,
                   .characterEncoding: String.Encoding.utf8.rawValue,
               ],
               documentAttributes: nil
           )
        {
            return normalizeWhitespace(in: attributed.string)
        }

        return normalizeWhitespace(
            in: normalized.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        )
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
