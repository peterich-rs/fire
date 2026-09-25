import Toast
import UIKit

/// Thin facade over BastiaanJansen/toast-swift so call sites never depend on
/// library types directly. Styles map onto FireTheme semantic colors.
@MainActor
enum FireUIKitToast {
    enum Style {
        case success
        case error
        case info
        case warning
    }

    static func show(
        _ message: String,
        style: Style = .info,
        in view: UIView? = nil,
        duration: TimeInterval = 2.4,
        haptic: Bool = true
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let image = UIImage(systemName: style.systemImage) ?? UIImage()
        let config = ToastConfiguration(
            direction: .top,
            dismissBy: [.time(time: duration), .swipe(direction: .natural)],
            animationTime: FireMotionTokens.duration(for: .standard, reduceMotion: false),
            attachTo: view,
            allowToastOverlap: false
        )

        let toast = Toast.default(
            image: image,
            imageTint: style.tintColor,
            title: trimmed,
            config: config
        )

        if haptic {
            switch style {
            case .success:
                toast.show(haptic: .success)
            case .error:
                toast.show(haptic: .error)
            case .info, .warning:
                toast.show(haptic: .warning)
            }
        } else {
            toast.show()
        }
    }
}

private extension FireUIKitToast.Style {
    var systemImage: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "xmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }

    var tintColor: UIColor {
        switch self {
        case .success:
            return FireTheme.uiSuccess
        case .error:
            return FireTheme.uiError
        case .info:
            return FireTheme.uiInfo
        case .warning:
            return FireTheme.uiWarning
        }
    }
}

// Compatibility bridge for call sites still typed against the old list toast.
extension FireUIKitToast.Style {
    init(_ legacy: FireTopicListToastView.Style) {
        switch legacy {
        case .success:
            self = .success
        case .error:
            self = .error
        case .info:
            self = .info
        }
    }
}
