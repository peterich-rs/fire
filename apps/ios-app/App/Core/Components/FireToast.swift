import SwiftUI

// MARK: - Toast

enum FireToastStyle: Equatable {
    case success
    case error
    case info
    case warning

    var iconName: String {
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

    var tintColor: Color {
        switch self {
        case .success:
            return FireTheme.success
        case .error:
            return Color.red
        case .info:
            return FireTheme.accent
        case .warning:
            return FireTheme.warning
        }
    }
}

struct FireToast: Equatable, Identifiable {
    let id: UUID
    let message: String
    let style: FireToastStyle

    init(message: String, style: FireToastStyle = .info) {
        self.id = UUID()
        self.message = message
        self.style = style
    }
}

struct FireToastView: View {
    let toast: FireToast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: toast.style.iconName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(toast.style.tintColor)
                .accessibilityHidden(true)

            Text(toast.message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.ink)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.chromeStrong)
                .overlay(
                    RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                        .strokeBorder(FireTheme.chromeBorder, lineWidth: 1)
                )
        )
        .shadow(color: FireTheme.panelShadow, radius: 12, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.message)
    }
}

private struct FireToastModifier: ViewModifier {
    @Binding var toast: FireToast?
    let topPadding: CGFloat
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    FireToastView(toast: toast)
                        .padding(.top, topPadding)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.25), value: toast)
            .onChange(of: toast) { newToast in
                scheduleDismiss(for: newToast)
            }
            .onDisappear {
                dismissTask?.cancel()
                dismissTask = nil
            }
    }

    private func scheduleDismiss(for toast: FireToast?) {
        dismissTask?.cancel()
        guard let toast else {
            dismissTask = nil
            return
        }
        let toastID = toast.id
        dismissTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2.5))
            } catch {
                return
            }
            guard self.toast?.id == toastID else {
                return
            }
            withAnimation(.easeOut(duration: 0.25)) {
                self.toast = nil
            }
        }
    }
}

extension View {
    func fireToast(_ toast: Binding<FireToast?>, topPadding: CGFloat = 60) -> some View {
        modifier(FireToastModifier(toast: toast, topPadding: topPadding))
    }
}
