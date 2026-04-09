import SwiftUI

struct FireProfileStatsRow: View {
    let items: [(value: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Divider()
                        .frame(height: 30)
                }
                VStack(spacing: 4) {
                    Text(item.value)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(FireTheme.ink)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(FireTheme.subtleInk)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }
}
