import SwiftUI

struct FireProfileStatsRow: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(FireTheme.divider)
                        .frame(width: 1, height: 30)
                }

                VStack(spacing: 6) {
                    Text(item.value)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                        .contentTransition(.numericText())

                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(FireTheme.tertiaryInk)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
    }
}
