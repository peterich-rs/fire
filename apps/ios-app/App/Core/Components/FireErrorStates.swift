import SwiftUI

// MARK: - Error Banner

struct FireErrorBanner: View {
    let message: String
    let copied: Bool
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(FireTheme.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)

                Text(message)
                    .font(.footnote.monospaced())
                    .foregroundStyle(FireTheme.subtleInk)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    onCopy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(FireTheme.subtleInk)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.mediumCornerRadius, style: .continuous)
                .fill(FireTheme.softSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: FireTheme.mediumCornerRadius, style: .continuous)
                        .strokeBorder(FireTheme.warning.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Blocking Error State

struct FireBlockingErrorState: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    init(
        title: String,
        message: String,
        retryTitle: String = "重试",
        onRetry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FireTheme.warning)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(retryTitle, action: onRetry)
                .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty Feed State

struct FireEmptyFeedState: View {
    let systemImage: String
    let title: String?
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        systemImage: String = "text.bubble",
        title: String? = nil,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
                .font(.title2)
                .foregroundStyle(FireTheme.accent)

            if let title {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.subtleInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FireSecondaryButtonStyle())
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}
