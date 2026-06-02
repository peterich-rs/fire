import SwiftUI

struct FireProfileTrustLevelPill: View {
    let trustLevel: UInt32

    private var label: String {
        switch trustLevel {
        case 0: return "新人"
        case 1: return "基本"
        case 2: return "成员"
        case 3: return "老手"
        case 4: return "领导者"
        default: return "TL\(trustLevel)"
        }
    }

    private var color: Color {
        switch trustLevel {
        case 0: return FireTheme.tertiaryInk
        case 1: return FireTheme.subtleInk
        case 2: return FireTheme.success
        case 3: return FireTheme.accent
        case 4: return FireTheme.warning
        default: return FireTheme.tertiaryInk
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }
}
