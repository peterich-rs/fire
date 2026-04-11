import SwiftUI

struct FireBadgeDetailView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let badgeID: UInt64
    let initialBadge: BadgeState?

    @State private var badge: BadgeState?
    @State private var isLoading = false
    @State private var errorMessage: String?

    init(viewModel: FireAppViewModel, badgeID: UInt64, initialBadge: BadgeState? = nil) {
        self.viewModel = viewModel
        self.badgeID = badgeID
        self.initialBadge = initialBadge
        _badge = State(initialValue: initialBadge)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let errorMessage {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {},
                        onDismiss: { self.errorMessage = nil }
                    )
                }

                if let badge {
                    FirePanel(style: .contrast, padding: 18) {
                        HStack(alignment: .center, spacing: 14) {
                            badgeHeroIcon(badge)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(badge.name)
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(FireTheme.inverseInk)

                                Text(typeLabel(for: badge))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(FireTheme.inverseSubtleInk)

                                Text("已授予 \(FireTopicPresentation.compactCount(badge.grantCount)) 次")
                                    .font(.caption)
                                    .foregroundStyle(FireTheme.inverseSubtleInk)
                            }
                            Spacer()
                        }
                    }

                    if let description = badge.description, !description.isEmpty {
                        sectionCard(title: "简介", body: plainTextFromHtml(rawHtml: description))
                    }

                    if let longDescription = badge.longDescription, !longDescription.isEmpty {
                        sectionCard(title: "详情", body: plainTextFromHtml(rawHtml: longDescription))
                    }
                } else if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 24)
                        Spacer()
                    }
                } else {
                    Text("未找到徽章信息")
                        .font(.subheadline)
                        .foregroundStyle(FireTheme.subtleInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                }
            }
            .padding(16)
        }
        .background(FireTheme.canvasTop)
        .navigationTitle("徽章")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: badgeID) {
            await loadBadgeIfNeeded()
        }
    }

    private func loadBadgeIfNeeded() async {
        guard badge?.id != badgeID else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            badge = try await viewModel.fetchBadgeDetail(badgeID: badgeID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionCard(title: String, body: String) -> some View {
        FirePanel(style: .quiet, padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.subtleInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func badgeHeroIcon(_ badge: BadgeState) -> some View {
        if let imageURL = badge.imageUrl.flatMap(URL.init(string:)) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    fallbackBadgeIcon(badge)
                }
            }
            .frame(width: 56, height: 56)
        } else {
            fallbackBadgeIcon(badge)
        }
    }

    private func fallbackBadgeIcon(_ badge: BadgeState) -> some View {
        ZStack {
            Circle()
                .fill(badgeAccentColor(badge).opacity(0.18))
                .frame(width: 56, height: 56)
            Image(systemName: badge.icon?.isEmpty == false ? "seal.fill" : "medal.fill")
                .font(.title2)
                .foregroundStyle(badgeAccentColor(badge))
        }
    }

    private func typeLabel(for badge: BadgeState) -> String {
        switch badge.badgeTypeId {
        case 1: return "金徽章"
        case 2: return "银徽章"
        default: return "铜徽章"
        }
    }

    private func badgeAccentColor(_ badge: BadgeState) -> Color {
        switch badge.badgeTypeId {
        case 1: return .yellow
        case 2: return .gray
        default: return .orange
        }
    }
}
