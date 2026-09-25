import Foundation
import SwiftUI
import UIKit

// MARK: - Home / list metric emphasis

/// Visual weight for topic-list reply / view / like chips.
/// Normal stays quiet; only notable / high / surge values light up.
enum FireTopicListMetricEmphasis: Equatable, Sendable {
    /// Default muted chrome — majority of rows.
    case normal
    /// Mild lift for above-average values.
    case notable
    /// Clearly hot absolute value.
    case high
    /// Young topic with unusually high view velocity (views only).
    case surge
}

enum FireTopicListMetricKind: Equatable, Sendable {
    case replies
    case views
    case likes
}

/// Pure ranking helpers for list metrics. Thresholds are absolute + age-aware
/// so ordinary rows stay calm while breakout posts get a small accent.
enum FireTopicListMetricRanking {
    /// Reply thresholds (LinuxDo-scale list density).
    static let repliesNotable: UInt32 = 15
    static let repliesHigh: UInt32 = 40

    /// Like thresholds.
    static let likesNotable: UInt32 = 8
    static let likesHigh: UInt32 = 25

    /// Absolute view thresholds.
    static let viewsNotable: UInt32 = 800
    static let viewsHigh: UInt32 = 3_000

    /// Surge: short-lived topics that already pulled solid traffic.
    static let surgeMaxAgeHours: Double = 36
    static let surgeViewsPerHour: Double = 70
    static let surgeMinViews: UInt32 = 180
    /// Extra absolute floor when still very fresh.
    static let surgeFreshHours: Double = 8
    static let surgeFreshMinViews: UInt32 = 120

    static func ageHours(
        createdTimestampUnixMs: UInt64?,
        now: Date = Date()
    ) -> Double? {
        guard let createdTimestampUnixMs else { return nil }
        let created = Date(timeIntervalSince1970: Double(createdTimestampUnixMs) / 1_000.0)
        let hours = now.timeIntervalSince(created) / 3_600.0
        return max(hours, 0)
    }

    static func emphasis(
        kind: FireTopicListMetricKind,
        value: UInt32,
        createdTimestampUnixMs: UInt64?,
        now: Date = Date()
    ) -> FireTopicListMetricEmphasis {
        switch kind {
        case .replies:
            if value >= repliesHigh { return .high }
            if value >= repliesNotable { return .notable }
            return .normal
        case .likes:
            if value >= likesHigh { return .high }
            if value >= likesNotable { return .notable }
            return .normal
        case .views:
            if isViewSurge(
                views: value,
                createdTimestampUnixMs: createdTimestampUnixMs,
                now: now
            ) {
                return .surge
            }
            if value >= viewsHigh { return .high }
            if value >= viewsNotable { return .notable }
            return .normal
        }
    }

    static func isViewSurge(
        views: UInt32,
        createdTimestampUnixMs: UInt64?,
        now: Date = Date()
    ) -> Bool {
        guard views >= surgeMinViews,
              let ageHours = ageHours(createdTimestampUnixMs: createdTimestampUnixMs, now: now),
              ageHours <= surgeMaxAgeHours
        else {
            return false
        }

        // Brand-new posts need a lower absolute bar so early breakouts still light up.
        if ageHours <= surgeFreshHours, views >= surgeFreshMinViews {
            return true
        }

        let safeHours = max(ageHours, 0.35)
        let viewsPerHour = Double(views) / safeHours
        return viewsPerHour >= surgeViewsPerHour && views >= surgeMinViews
    }

    /// Tiny accessory on surge rows: rocket when very fresh, flame otherwise.
    static func surgeAccessorySymbol(
        createdTimestampUnixMs: UInt64?,
        now: Date = Date()
    ) -> String {
        if let ageHours = ageHours(createdTimestampUnixMs: createdTimestampUnixMs, now: now),
           ageHours <= surgeFreshHours
        {
            return "rocket.fill"
        }
        return "flame.fill"
    }
}

