import SwiftUI

struct FireMarkdownToolbar: View {
    let onFormat: (FireMarkdownFormatAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(FireMarkdownFormatAction.allCases) { action in
                    toolbarButton(action)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .strokeBorder(FireTheme.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func toolbarButton(_ action: FireMarkdownFormatAction) -> some View {
        Button {
            onFormat(action)
        } label: {
            Group {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Text(action.title)
                        .font(toolbarFont(for: action))
                        .strikethrough(action == .strikethrough)
                }
            }
            .frame(width: 36, height: 34)
            .foregroundStyle(FireTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
    }

    private func toolbarFont(for action: FireMarkdownFormatAction) -> Font {
        switch action {
        case .bold:
            return .system(size: 15, weight: .bold)
        case .italic:
            return .system(size: 15, weight: .medium).italic()
        default:
            return .system(size: 14, weight: .semibold)
        }
    }
}
