import SwiftUI

struct FireReactionUsersSheet: View {
    let groups: [ReactionUsersGroupState]
    let reactionID: String?

    var body: some View {
        List {
            if groups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.title2)
                        .foregroundStyle(FireTheme.subtleInk)
                    Text("暂时没有回应用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(groups, id: \.id) { group in
                    Section {
                        ForEach(group.users, id: \.id) { user in
                            HStack(spacing: 12) {
                                FireAvatarView(
                                    avatarTemplate: user.avatarTemplate,
                                    username: user.username,
                                    size: 36
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text((user.name ?? "").ifEmpty(user.username))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(FireTheme.ink)
                                    Text("@\(user.username)")
                                        .font(.caption)
                                        .foregroundStyle(FireTheme.subtleInk)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    } header: {
                        let option = FireTopicPresentation.reactionOption(for: group.id)
                        Text("\(option.symbol) \(option.label) · \(group.count)")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        guard let reactionID,
              !reactionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "回应用户"
        }
        let option = FireTopicPresentation.reactionOption(for: reactionID)
        return "\(option.symbol) \(option.label)"
    }
}

extension Array where Element == ReactionUsersGroupState {
    func filter(for reactionID: String?) -> [ReactionUsersGroupState] {
        guard let reactionID = reactionID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reactionID.isEmpty else {
            return self
        }
        return filter { group in
            group.id.caseInsensitiveCompare(reactionID) == .orderedSame
        }
    }
}
