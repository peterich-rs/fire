import SwiftUI

// MARK: - Skeleton List

struct FireTopicSkeletonRow: View {
    var avatarSize: CGFloat = 38
    var subtitleWidth: CGFloat = 120
    var showsTrailingMeta = true
    var verticalPadding: CGFloat = 12

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(FireTheme.track)
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FireTheme.chromeStrong)
                    .frame(height: 14)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FireTheme.track)
                    .frame(width: subtitleWidth, height: 10)
            }

            Spacer()

            if showsTrailingMeta {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(FireTheme.track)
                    .frame(width: 28, height: 20)
            }
        }
        .padding(.vertical, verticalPadding)
        .fireShimmer()
        .accessibilityHidden(true)
    }
}

struct FireTopicSkeletonList: View {
    var rowCount = 6
    var avatarSize: CGFloat = 38
    var subtitleWidth: CGFloat = 120
    var showsTrailingMeta = true
    var verticalPadding: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { index in
                FireTopicSkeletonRow(
                    avatarSize: avatarSize,
                    subtitleWidth: subtitleWidth,
                    showsTrailingMeta: showsTrailingMeta,
                    verticalPadding: verticalPadding
                )

                if index != rowCount - 1 {
                    Divider()
                        .overlay(FireTheme.divider)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct FireNotificationSkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 7, height: 7)
                .padding(.top, 6)

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: 13)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(.quaternarySystemFill))
                    .frame(width: 80, height: 10)
            }
        }
        .padding(.vertical, 10)
        .fireShimmer()
        .accessibilityHidden(true)
    }
}

struct FireNotificationSkeletonList: View {
    var rowCount = 8

    var body: some View {
        List {
            ForEach(0..<rowCount, id: \.self) { _ in
                FireNotificationSkeletonRow()
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .accessibilityHidden(true)
    }
}
