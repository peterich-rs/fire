import SwiftUI

/// Centralised motion timing/spring/haptic constants. All durations and
/// spring configs flow through here so app-wide tuning is a single edit.
///
/// Every `duration(for:reduceMotion:)` accessor zeros out under Reduce
/// Motion. Spring response/damping pairs likewise collapse to a stiff,
/// near-instant config under Reduce Motion so motion-driven layout
/// changes still settle without animation.
@MainActor
enum FireMotionTokens {
    enum Duration {
        /// Tactile micro-feedback (button press, badge pulse).
        case tap
        /// Symbol replacement / number flip / standard list-row transition.
        case standard
        /// NavigationStack push fallback on iOS 17.
        case navPush
    }

    enum Spring {
        /// Sheet presentation tuning (slightly softer than system default).
        case sheet
        /// Generic interactive element spring (CTA press, list reorder).
        case interactive
    }

    static let tapDuration: Double = 0.18
    static let standardDuration: Double = 0.22
    static let navPushDuration: Double = 0.25

    static let sheetResponse: Double = 0.34
    static let sheetDamping: Double = 0.78
    static let interactiveResponse: Double = 0.30
    static let interactiveDamping: Double = 0.72

    static func duration(for kind: Duration, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        switch kind {
        case .tap: return tapDuration
        case .standard: return standardDuration
        case .navPush: return navPushDuration
        }
    }

    static func animation(for kind: Duration, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        return .easeInOut(duration: duration(for: kind, reduceMotion: false))
    }

    static func spring(for kind: Spring, reduceMotion: Bool) -> Animation {
        guard !reduceMotion else { return .linear(duration: 0) }
        switch kind {
        case .sheet:
            return .spring(response: sheetResponse, dampingFraction: sheetDamping)
        case .interactive:
            return .spring(response: interactiveResponse, dampingFraction: interactiveDamping)
        }
    }
}
