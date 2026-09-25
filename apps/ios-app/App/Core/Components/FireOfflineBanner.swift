import SwiftUI

// MARK: - Offline Banner

struct FireOfflineBanner: View {
    let message: String

    init(_ message: String = "正在显示离线缓存") {
        self.message = message
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.footnote.weight(.semibold))
                .accessibilityHidden(true)

            Text(message)
                .font(.footnote.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .foregroundStyle(FireTheme.warning)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                        .strokeBorder(FireTheme.warning.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
