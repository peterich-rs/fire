import SwiftUI
import UIKit

// MARK: - Scene Background

struct FireSceneBackground: View {
    var body: some View {
        LinearGradient(
            colors: [FireTheme.canvasTop, FireTheme.canvasMid, FireTheme.canvasBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(FireTheme.accent.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 54)
                .offset(x: -80, y: -90)
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(FireTheme.accentSoft.opacity(0.08))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: 90, y: 80)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Panel

enum FirePanelStyle {
    case contrast
    case chrome
    case quiet
}

struct FirePanel<Content: View>: View {
    let style: FirePanelStyle
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        style: FirePanelStyle,
        padding: CGFloat = 20,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    private var fillStyle: AnyShapeStyle {
        switch style {
        case .contrast:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [FireTheme.panel, FireTheme.panelElevated],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .chrome:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [FireTheme.chromeStrong, FireTheme.chrome],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .quiet:
            return AnyShapeStyle(FireTheme.softSurface)
        }
    }

    private var borderColor: Color {
        switch style {
        case .contrast:
            return FireTheme.inverseDivider
        case .chrome:
            return FireTheme.chromeBorder
        case .quiet:
            return FireTheme.divider
        }
    }

    private var shadowColor: Color {
        switch style {
        case .contrast:
            return Color.black.opacity(0.14)
        case .chrome, .quiet:
            return Color.black.opacity(0.06)
        }
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                    .fill(fillStyle)
                    .overlay(
                        RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: FireTheme.panelShadowRadius, y: FireTheme.panelShadowY)
    }
}

// MARK: - Section Lead

struct FireSectionLead: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var inverse = false

    private var eyebrowColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.tertiaryInk
    }

    private var titleColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    private var subtitleColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(eyebrowColor)

            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(titleColor)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(subtitleColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Status Chip

struct FireStatusChip: View {
    let label: String
    let tone: Tone
    var inverse = false

    enum Tone {
        case accent
        case success
        case warning
        case muted
    }

    private var background: Color {
        switch tone {
        case .accent:
            return FireTheme.accent.opacity(inverse ? 0.2 : 0.12)
        case .success:
            return FireTheme.success.opacity(inverse ? 0.2 : 0.12)
        case .warning:
            return FireTheme.warning.opacity(inverse ? 0.18 : 0.12)
        case .muted:
            return inverse ? FireTheme.inverseDivider : FireTheme.softSurface
        }
    }

    private var foreground: Color {
        switch tone {
        case .accent:
            return inverse ? FireTheme.accentGlow : FireTheme.accent
        case .success:
            return FireTheme.success
        case .warning:
            return FireTheme.warning
        case .muted:
            return inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
        }
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }
}

// MARK: - Topic Pill

struct FireTopicPill: View {
    let label: String
    let backgroundColor: Color
    let foregroundColor: Color

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }
}

// MARK: - Inline Meta

struct FireInlineMeta: View {
    let label: String
    let symbol: String
    var color: Color = FireTheme.tertiaryInk

    var body: some View {
        Label(label, systemImage: symbol)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

// MARK: - Metric Tile

struct FireMetricTile: View {
    let label: String
    let value: String
    var inverse = false

    private var backgroundColor: Color {
        inverse ? FireTheme.inverseDivider : FireTheme.softSurface
    }

    private var valueColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    private var labelColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.tertiaryInk
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption)
                .foregroundStyle(labelColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(backgroundColor)
        )
    }
}

// MARK: - Key Value Row

struct FireKeyValueRow: View {
    let label: String
    let value: String
    var inverse = false

    private var labelColor: Color {
        inverse ? FireTheme.inverseSubtleInk : FireTheme.subtleInk
    }

    private var valueColor: Color {
        inverse ? FireTheme.inverseInk : FireTheme.ink
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(labelColor)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Error Banner

struct FireErrorBanner: View {
    let message: String
    let copied: Bool
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(FireTheme.warning)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FireTheme.ink)

                Text(message)
                    .font(.footnote.monospaced())
                    .foregroundStyle(FireTheme.subtleInk)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button {
                    onCopy()
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(FireTheme.subtleInk)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.softSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                        .strokeBorder(FireTheme.warning.opacity(0.28), lineWidth: 1)
                )
        )
    }
}

// MARK: - Blocking Error State

struct FireBlockingErrorState: View {
    let title: String
    let message: String
    let retryTitle: String
    let onRetry: () -> Void

    init(
        title: String,
        message: String,
        retryTitle: String = "重试",
        onRetry: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FireTheme.warning)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FireTheme.ink)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(FireTheme.subtleInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(retryTitle, action: onRetry)
                .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty Feed State

struct FireEmptyFeedState: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.title2)
                .foregroundStyle(FireTheme.accent)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(FireTheme.subtleInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(actionTitle, action: action)
                .buttonStyle(FireSecondaryButtonStyle())
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Skeleton List

struct FireTopicSkeletonList: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle()
                        .fill(FireTheme.track)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FireTheme.chromeStrong)
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(FireTheme.track)
                            .frame(width: 120, height: 10)
                    }

                    Spacer()

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(FireTheme.track)
                        .frame(width: 28, height: 20)
                }
                .padding(.vertical, 12)
                .redacted(reason: .placeholder)

                if index != 5 {
                    Divider()
                        .overlay(FireTheme.divider)
                }
            }
        }
    }
}

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

// MARK: - Toolbar Icon

struct FireToolbarIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FireTheme.subtleInk)
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(FireTheme.softSurface)
                    .overlay(
                        Circle()
                            .strokeBorder(FireTheme.divider, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Button Styles

struct FirePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [FireTheme.accent, FireTheme.accentSoft],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isEnabled)
    }
}

struct FireSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FireTheme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(FireTheme.softSurface)
                    .overlay(
                        Capsule()
                            .strokeBorder(FireTheme.divider, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var fallbackWidth: CGFloat? = nil

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = resolvedMaxWidth(for: proposal)
        let hasExplicitWidth = proposal.width.map { $0.isFinite && $0 > 0 } ?? false
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxLineWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                totalHeight += lineHeight + spacing
                maxLineWidth = max(maxLineWidth, lineWidth)
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += (lineWidth > 0 ? spacing : 0) + size.width
                lineHeight = max(lineHeight, size.height)
            }
        }

        totalHeight += lineHeight
        maxLineWidth = max(maxLineWidth, lineWidth)

        let reportedWidth = hasExplicitWidth ? maxWidth : maxLineWidth
        return CGSize(width: reportedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var cursor = CGPoint(x: bounds.minX, y: bounds.minY)
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > bounds.minX, cursor.x + size.width > bounds.maxX {
                cursor.x = bounds.minX
                cursor.y += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: cursor,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            cursor.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func resolvedMaxWidth(for proposal: ProposedViewSize) -> CGFloat {
        if let proposalWidth = proposal.width, proposalWidth.isFinite, proposalWidth > 0 {
            return proposalWidth
        }

        if let fallbackWidth, fallbackWidth.isFinite, fallbackWidth > 0 {
            return fallbackWidth
        }

        return max(UIScreen.main.bounds.width - 120, 180)
    }
}

// MARK: - Avatar View

private let fireAvatarPlaceholderOpacity = 0.6

struct FireRemoteImageRequest: Hashable, Sendable {
    let url: URL

    var cacheKey: String {
        url.absoluteString
    }
}

typealias FireAvatarImageRequest = FireRemoteImageRequest

enum FireRemoteImagePipelineError: Error {
    case badServerResponse
    case invalidImageData
}

typealias FireAvatarImagePipelineError = FireRemoteImagePipelineError

final class FireRemoteImageMemoryCache: @unchecked Sendable {
    static let shared = FireRemoteImageMemoryCache()

    private let storage: NSCache<NSString, UIImage>

    init(
        countLimit: Int = 256,
        totalCostLimit: Int = 48 * 1024 * 1024,
        storage: NSCache<NSString, UIImage> = NSCache<NSString, UIImage>()
    ) {
        self.storage = storage
        self.storage.countLimit = countLimit
        self.storage.totalCostLimit = totalCostLimit
    }

    func image(for key: String) -> UIImage? {
        storage.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        storage.setObject(image, forKey: key as NSString, cost: image.fireMemoryCost)
    }

    func removeAllObjects() {
        storage.removeAllObjects()
    }
}

typealias FireAvatarImageMemoryCache = FireRemoteImageMemoryCache

final class FireRemoteImagePipeline: @unchecked Sendable {
    static let shared = FireRemoteImagePipeline()

    private struct InFlightLoad {
        let id: UUID
        let task: Task<UIImage, Error>
    }

    private let memoryCache: FireRemoteImageMemoryCache
    private let dataLoader: @Sendable (URL) async throws -> Data
    private let lock = NSLock()
    private var inFlightLoads: [String: InFlightLoad] = [:]

    init(
        memoryCache: FireRemoteImageMemoryCache = .shared,
        dataLoader: @escaping @Sendable (URL) async throws -> Data = FireRemoteImagePipeline.defaultDataLoader
    ) {
        self.memoryCache = memoryCache
        self.dataLoader = dataLoader
    }

    func cachedImage(for request: FireRemoteImageRequest) -> UIImage? {
        memoryCache.image(for: request.cacheKey)
    }

    func loadImage(for request: FireRemoteImageRequest) async throws -> UIImage {
        if let cachedImage = cachedImage(for: request) {
            return cachedImage
        }

        let load = withLock { () -> InFlightLoad in
            if let existingLoad = inFlightLoads[request.cacheKey] {
                return existingLoad
            }

            let load = InFlightLoad(
                id: UUID(),
                task: Task(priority: .userInitiated) { [memoryCache, dataLoader] in
                    let data = try await dataLoader(request.url)
                    guard let image = UIImage(data: data) else {
                        throw FireRemoteImagePipelineError.invalidImageData
                    }
                    let preparedImage = image.preparingForDisplay() ?? image
                    memoryCache.insert(preparedImage, for: request.cacheKey)
                    return preparedImage
                }
            )
            inFlightLoads[request.cacheKey] = load
            return load
        }

        defer {
            withLock {
                guard inFlightLoads[request.cacheKey]?.id == load.id else {
                    return
                }
                inFlightLoads.removeValue(forKey: request.cacheKey)
            }
        }

        let image = try await load.task.value
        memoryCache.insert(image, for: request.cacheKey)
        return image
    }

    private static func defaultDataLoader(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw FireRemoteImagePipelineError.badServerResponse
        }
        return data
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

typealias FireAvatarImagePipeline = FireRemoteImagePipeline

enum FireRemoteImagePlaceholderState: Equatable {
    case loading
    case failure
    case missingRequest
}

struct FireRemoteImage<Content: View, Placeholder: View>: View {
    let request: FireRemoteImageRequest?
    private let content: (UIImage) -> Content
    private let placeholder: (FireRemoteImagePlaceholderState) -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var loadedImageKey: String?
    @State private var loadFailed = false

    init(
        request: FireRemoteImageRequest?,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder placeholder: @escaping (FireRemoteImagePlaceholderState) -> Placeholder
    ) {
        self.request = request
        self.content = content
        self.placeholder = placeholder
    }

    private var resolvedImage: UIImage? {
        guard let request else {
            return nil
        }
        if loadedImageKey == request.cacheKey, let loadedImage {
            return loadedImage
        }
        return FireRemoteImagePipeline.shared.cachedImage(for: request)
    }

    var body: some View {
        Group {
            if let resolvedImage {
                content(resolvedImage)
            } else if request != nil {
                placeholder(loadFailed ? .failure : .loading)
            } else {
                placeholder(.missingRequest)
            }
        }
        .task(id: request?.cacheKey) {
            await loadImageIfNeeded()
        }
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard let request else {
            loadedImage = nil
            loadedImageKey = nil
            loadFailed = false
            return
        }

        loadedImage = nil
        loadedImageKey = nil
        loadFailed = false

        if let cachedImage = FireRemoteImagePipeline.shared.cachedImage(for: request) {
            loadedImage = cachedImage
            loadedImageKey = request.cacheKey
            return
        }

        do {
            let image = try await FireRemoteImagePipeline.shared.loadImage(for: request)
            guard !Task.isCancelled else {
                return
            }
            loadedImage = image
            loadedImageKey = request.cacheKey
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else {
                return
            }
            loadFailed = true
        }
    }
}

func fireAvatarURL(
    avatarTemplate: String?,
    size: CGFloat,
    scale: CGFloat,
    baseURLString: String = "https://linux.do"
) -> URL? {
    guard let avatarTemplate, !avatarTemplate.isEmpty else {
        return nil
    }

    let pixelSize = Int(size * scale)
    let path = avatarTemplate.replacingOccurrences(of: "{size}", with: "\(pixelSize)")
    if path.hasPrefix("http") {
        return URL(string: path)
    }
    if path.hasPrefix("//") {
        let scheme = URL(string: baseURLString)?.scheme ?? "https"
        return URL(string: "\(scheme):\(path)")
    }
    return URL(string: path, relativeTo: URL(string: baseURLString))?.absoluteURL
}

private extension UIImage {
    var fireMemoryCost: Int {
        guard let cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
    }
}

struct FireAvatarView: View {
    let avatarTemplate: String?
    let username: String
    let size: CGFloat
    var baseURLString: String = "https://linux.do"

    private var avatarRequest: FireAvatarImageRequest? {
        guard let avatarURL = fireAvatarURL(
            avatarTemplate: avatarTemplate,
            size: size,
            scale: UIScreen.main.scale,
            baseURLString: baseURLString
        ) else {
            return nil
        }
        return FireAvatarImageRequest(url: avatarURL)
    }

    private var monogram: String {
        monogramForUsername(username: username.isEmpty ? "?" : username)
    }

    var body: some View {
        FireRemoteImage(request: avatarRequest) { resolvedImage in
            Image(uiImage: resolvedImage)
                .resizable()
                .scaledToFill()
        } placeholder: { state in
            monogramView
                .opacity(state == .loading && avatarRequest != nil ? fireAvatarPlaceholderOpacity : 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var monogramView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FireTheme.accent, FireTheme.accentSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(monogram)
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - String Extension

extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
