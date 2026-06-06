import SwiftUI

struct FireRecipientTokenField: View {
    let recipients: [String]
    @Binding var query: String
    let results: [UserMentionUserState]
    let onRemoveRecipient: (String) -> Void
    let onAddRecipient: (UserMentionUserState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !recipients.isEmpty {
                FlowLayout(spacing: 8, fallbackWidth: max(UIScreen.main.bounds.width - 32, 200)) {
                    ForEach(recipients, id: \.self) { username in
                        Button {
                            onRemoveRecipient(username)
                        } label: {
                            HStack(spacing: 6) {
                                Text("@\(username)")
                                    .font(.caption.weight(.medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .foregroundStyle(FireTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(FireTheme.accent.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            TextField("添加收件人", text: $query)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(results, id: \.username) { user in
                        Button {
                            onAddRecipient(user)
                        } label: {
                            HStack(spacing: 10) {
                                Text(monogramForUsername(username: user.username))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(FireTheme.accent))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@\(user.username)")
                                        .foregroundStyle(.primary)
                                    if let name = user.name, !name.isEmpty {
                                        Text(name)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if user.username != results.last?.username {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }
}
