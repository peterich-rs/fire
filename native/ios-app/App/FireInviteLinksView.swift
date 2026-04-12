import SwiftUI
import UIKit

private enum FireInviteExpiryPreset: String, CaseIterable, Identifiable {
    case day1
    case day7
    case day30
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day1:
            return "1 天"
        case .day7:
            return "7 天"
        case .day30:
            return "30 天"
        case .never:
            return "永不过期"
        }
    }

    var expiresAt: String? {
        switch self {
        case .day1:
            return Self.isoString(days: 1)
        case .day7:
            return Self.isoString(days: 7)
        case .day30:
            return Self.isoString(days: 30)
        case .never:
            return nil
        }
    }

    private static func isoString(days: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(Double(days) * 24 * 60 * 60))
    }
}

struct FireInviteLinksView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let username: String

    @State private var invites: [InviteLinkState] = []
    @State private var isLoading = false
    @State private var isSubmitting = false
    @State private var maxRedemptionsAllowed: UInt32 = 5
    @State private var expiryPreset: FireInviteExpiryPreset = .day7
    @State private var descriptionText = ""
    @State private var emailText = ""
    @State private var errorMessage: String?
    @State private var noticeMessage: String?

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var body: some View {
        List {
            if let noticeMessage {
                Section {
                    noticeRow(message: noticeMessage, tint: .green)
                }
            }

            if let errorMessage {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {
                            UIPasteboard.general.string = errorMessage
                        },
                        onDismiss: {
                            self.errorMessage = nil
                        }
                    )
                }
            }

            Section("创建邀请链接") {
                Picker("可用次数", selection: $maxRedemptionsAllowed) {
                    Text("1 次").tag(UInt32(1))
                    Text("3 次").tag(UInt32(3))
                    Text("5 次").tag(UInt32(5))
                    Text("10 次").tag(UInt32(10))
                }

                Picker("有效期", selection: $expiryPreset) {
                    ForEach(FireInviteExpiryPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                TextField("说明（可选）", text: $descriptionText)
                    .textInputAutocapitalization(.never)

                TextField("邮箱（可选）", text: $emailText)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task { await createInvite() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isSubmitting ? "生成中…" : "生成邀请链接")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isSubmitting)
            }

            if isLoading && invites.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
            } else if invites.isEmpty {
                Section("待使用邀请") {
                    Text("暂时没有待使用的邀请链接。")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.subtleInk)
                        .padding(.vertical, 8)
                }
            } else {
                Section("待使用邀请") {
                    ForEach(fireIdentifiedValues(invites) { $0.fireStableBaseID }) { item in
                        inviteRow(item.value)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(FireTheme.canvasTop)
        .navigationTitle("邀请链接")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInvites(force: false)
        }
        .refreshable {
            await loadInvites(force: true)
        }
    }

    private func loadInvites(force: Bool) async {
        guard force || (!isLoading && invites.isEmpty) else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            invites = try await viewModel.fetchPendingInvites(username: username)
            errorMessage = nil
        } catch {
            if invites.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createInvite() async {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let invite = try await viewModel.createInviteLink(
                maxRedemptionsAllowed: maxRedemptionsAllowed,
                expiresAt: expiryPreset.expiresAt,
                description: trimmed(descriptionText),
                email: trimmed(emailText)
            )
            noticeMessage = "邀请链接已生成"
            errorMessage = nil
            let identity = inviteIdentity(invite)
            invites.removeAll { inviteIdentity($0) == identity }
            invites.insert(invite, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func inviteRow(_ invite: InviteLinkState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(effectiveInviteLink(invite))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FireTheme.ink)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                infoPill(
                    symbol: "number.circle",
                    text: usageText(invite)
                )

                if let expiresAt = invite.invite?.expiresAt,
                   let compact = FireTopicPresentation.compactTimestamp(expiresAt) {
                    infoPill(symbol: "clock", text: compact)
                } else {
                    infoPill(symbol: "clock", text: "长期有效")
                }
            }

            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = effectiveInviteLink(invite)
                    noticeMessage = "邀请链接已复制"
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }

                if let url = URL(string: effectiveInviteLink(invite)) {
                    ShareLink(item: url) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(FireTheme.accent)
        }
        .padding(.vertical, 6)
    }

    private func noticeRow(message: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.ink)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func infoPill(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(FireTheme.subtleInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(FireTheme.softSurface, in: Capsule())
    }

    private func effectiveInviteLink(_ invite: InviteLinkState) -> String {
        let explicitLink = invite.inviteLink.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicitLink.isEmpty {
            return explicitLink
        }
        if let key = invite.invite?.inviteKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            return "\(baseURLString)/invites/\(key)"
        }
        return "链接生成中"
    }

    private func inviteIdentity(_ invite: InviteLinkState) -> String {
        if let id = invite.invite?.id {
            return "id:\(id)"
        }
        if let key = invite.invite?.inviteKey {
            return "key:\(key)"
        }
        return effectiveInviteLink(invite)
    }

    private func usageText(_ invite: InviteLinkState) -> String {
        let used = invite.invite?.redemptionCount ?? 0
        let total = invite.invite?.maxRedemptionsAllowed ?? maxRedemptionsAllowed
        return "\(used)/\(total)"
    }

    private func trimmed(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
