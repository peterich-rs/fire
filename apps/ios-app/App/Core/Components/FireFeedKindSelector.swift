import SwiftUI

// MARK: - Feed Kind Selector

struct FireFeedKindSelector: View {
    let selectedKind: TopicListKindState
    let namespace: Namespace.ID
    let onSelect: (TopicListKindState) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TopicListKindState.orderedCases, id: \.self) { kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        ZStack {
                            if selectedKind == kind {
                                Capsule()
                                    .fill(FireTheme.panel)
                                    .matchedGeometryEffect(id: "feed-selection", in: namespace)
                            } else {
                                Capsule()
                                    .fill(Color.clear)
                            }

                            Text(kind.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedKind == kind ? FireTheme.inverseInk : FireTheme.subtleInk)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(FireTheme.track)
            )
        }
        .scrollIndicators(.hidden)
    }
}
