import SwiftUI

struct FirePostReactionPickerSheet: View {
    let post: TopicPostState
    let options: [FireReactionOption]
    let onSelectReaction: @MainActor (String) -> Void
    let onShowUsers: @MainActor (String) -> Void

    @State private var query = ""

    private var filteredOptions: [FireReactionOption] {
        FireTopicPresentation.filterReactionOptions(options, query: query)
    }

    var body: some View {
        List {
            ForEach(filteredOptions) { option in
                reactionRow(option)
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索表情")
        .navigationTitle("回应 #\(post.postNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reactionRow(_ option: FireReactionOption) -> some View {
        let count = post.reactions
            .first { $0.id.caseInsensitiveCompare(option.id) == .orderedSame }
            .map(\.count) ?? 0
        let isSelected = post.currentUserReaction?.id.caseInsensitiveCompare(option.id) == .orderedSame

        return HStack(spacing: 12) {
            Text(option.symbol)
                .font(.title3)
                .frame(width: 32, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(option.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(FireTheme.ink)
                Text("\(option.id) · \(count)")
                    .font(.caption)
                    .foregroundStyle(FireTheme.subtleInk)
            }

            Spacer()

            Button {
                onShowUsers(option.id)
            } label: {
                Image(systemName: "person.2")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("查看\(option.label)用户")

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectReaction(option.id)
        }
        .contextMenu {
            Button {
                onShowUsers(option.id)
            } label: {
                Label("查看回应用户", systemImage: "person.2")
            }
        }
    }
}
