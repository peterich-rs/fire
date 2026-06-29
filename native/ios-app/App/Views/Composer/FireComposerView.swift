import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

func shouldRestorePrivateMessageDraft(
    explicitRecipients: [String],
    draftRecipients: [String]
) -> Bool {
    let normalizedExplicitRecipients = normalizedPrivateMessageRecipients(explicitRecipients)
    guard !normalizedExplicitRecipients.isEmpty else {
        return true
    }
    return normalizedPrivateMessageRecipients(draftRecipients) == normalizedExplicitRecipients
}

func normalizedPrivateMessageRecipients(_ recipients: [String]) -> [String] {
    var normalized: [String] = []

    for recipient in recipients {
        let trimmed = recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            continue
        }

        let stableRecipient = trimmed.lowercased()
        if normalized.contains(stableRecipient) {
            continue
        }
        normalized.append(stableRecipient)
    }

    return normalized.sorted()
}

enum FireQuoteMarkdown {
    static func build(
        username: String,
        postNumber: UInt32,
        topicID: UInt64,
        plainText: String
    ) -> String? {
        let body = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            return nil
        }

        let author = username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "'")
            .ifEmpty("unknown")
        return "[quote=\"\(author), post:\(postNumber), topic:\(topicID)\"]\n" +
            body +
            "\n[/quote]\n\n"
    }
}

enum FireComposerInitialBody {
    static func merge(
        initialBody: String,
        currentBody: String,
        preferredSelectionLocation: Int? = nil
    ) -> FireMarkdownInsertionResult {
        let initialLength = (initialBody as NSString).length
        let preferredSelection = min(max(preferredSelectionLocation ?? initialLength, 0), initialLength)
        guard !initialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: (currentBody as NSString).length, length: 0)
            )
        }

        let currentSource = currentBody as NSString
        let exactRange = currentSource.range(of: initialBody)
        if exactRange.location != NSNotFound {
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: exactRange.location + preferredSelection, length: 0)
            )
        }

        let trimmedInitial = initialBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRange = currentSource.range(of: trimmedInitial)
        if trimmedRange.location != NSNotFound {
            let trimmedSelection = min(preferredSelection, (trimmedInitial as NSString).length)
            return FireMarkdownInsertionResult(
                text: currentBody,
                selectedRange: NSRange(location: trimmedRange.location + trimmedSelection, length: 0)
            )
        }

        guard !currentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return FireMarkdownInsertionResult(
                text: initialBody,
                selectedRange: NSRange(location: preferredSelection, length: 0)
            )
        }

        let separator = initialBody.hasSuffix("\n\n") || currentBody.hasPrefix("\n") ? "" : "\n\n"
        return FireMarkdownInsertionResult(
            text: initialBody + separator + currentBody,
            selectedRange: NSRange(location: preferredSelection, length: 0)
        )
    }
}

struct FireComposerRoute: Identifiable, Equatable {
    enum Kind: Equatable {
        case createTopic
        case advancedReply(
            topicID: UInt64,
            topicTitle: String,
            categoryID: UInt64?,
            replyToPostNumber: UInt32?,
            replyToUsername: String?,
            isPrivateMessage: Bool
        )
        case privateMessage(
            recipients: [String],
            title: String?
        )
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .createTopic:
            return "create-topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, let isPrivateMessage):
            let suffix = isPrivateMessage ? "pm" : "topic"
            return "reply-\(topicID)-\(replyToPostNumber ?? 0)"
                + "-\(suffix)"
        case .privateMessage(let recipients, _):
            let seed = recipients.isEmpty ? "new" : recipients.sorted().joined(separator: ",")
            return "private-message-\(seed)"
        }
    }

    var navigationTitle: String {
        switch kind {
        case .createTopic:
            return "新建话题"
        case .advancedReply(_, _, _, _, _, let isPrivateMessage):
            return isPrivateMessage ? "完整私信回复" : "完整回复"
        case .privateMessage:
            return "新建私信"
        }
    }

    var submitLabel: String {
        switch kind {
        case .createTopic:
            return "发布"
        case .advancedReply, .privateMessage:
            return "发送"
        }
    }

    var topicID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(let topicID, _, _, _, _, _):
            return topicID
        case .privateMessage:
            return nil
        }
    }

    var topicTitle: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, let topicTitle, _, _, _, _):
            return topicTitle
        case .privateMessage(_, let title):
            return title
        }
    }

    var replyToPostNumber: UInt32? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, let replyToPostNumber, _, _):
            return replyToPostNumber
        case .privateMessage:
            return nil
        }
    }

    var replyToUsername: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, _, let replyToUsername, _):
            return replyToUsername
        case .privateMessage:
            return nil
        }
    }

    var fallbackCategoryID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, let categoryID, _, _, _):
            return categoryID
        case .privateMessage:
            return nil
        }
    }

    var recipients: [String] {
        switch kind {
        case .privateMessage(let recipients, _):
            return recipients
        default:
            return []
        }
    }

    var isPrivateMessage: Bool {
        switch kind {
        case .privateMessage:
            return true
        case .advancedReply(_, _, _, _, _, let isPrivateMessage):
            return isPrivateMessage
        case .createTopic:
            return false
        }
    }

    var draftKey: String {
        switch kind {
        case .createTopic:
            return "new_topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, _):
            if let replyToPostNumber, replyToPostNumber > 0 {
                return "topic_\(topicID)_post_\(replyToPostNumber)"
            }
            return "topic_\(topicID)"
        case .privateMessage:
            return "new_private_message"
        }
    }
}

private struct FireComposerMentionContext: Equatable {
    let replacementRange: NSRange
    let term: String
}

private struct FireComposerMarkdownImage: Identifiable, Hashable {
    let urlString: String
    let altText: String?

    var id: String { urlString }
}

enum FireMarkdownFormatAction: CaseIterable, Identifiable {
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case quote
    case unorderedList
    case orderedList
    case link
    case image

    var id: Self { self }

    var title: String {
        switch self {
        case .bold:
            return "B"
        case .italic:
            return "I"
        case .strikethrough:
            return "S"
        case .inlineCode:
            return "<>"
        case .codeBlock:
            return "```"
        case .quote:
            return "Quote"
        case .unorderedList:
            return "UL"
        case .orderedList:
            return "OL"
        case .link:
            return "Link"
        case .image:
            return "Image"
        }
    }

    var systemImage: String? {
        switch self {
        case .bold, .italic, .strikethrough:
            return nil
        case .inlineCode:
            return "chevron.left.forwardslash.chevron.right"
        case .codeBlock:
            return "curlybraces"
        case .quote:
            return "text.quote"
        case .unorderedList:
            return "list.bullet"
        case .orderedList:
            return "list.number"
        case .link:
            return "link"
        case .image:
            return "photo"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .bold:
            return "加粗"
        case .italic:
            return "斜体"
        case .strikethrough:
            return "删除线"
        case .inlineCode:
            return "行内代码"
        case .codeBlock:
            return "代码块"
        case .quote:
            return "引用"
        case .unorderedList:
            return "项目列表"
        case .orderedList:
            return "编号列表"
        case .link:
            return "链接"
        case .image:
            return "图片标记"
        }
    }
}

private extension FireMarkdownFormatAction {
    var rawTag: Int {
        switch self {
        case .bold: return 1
        case .italic: return 2
        case .strikethrough: return 3
        case .inlineCode: return 4
        case .codeBlock: return 5
        case .quote: return 6
        case .unorderedList: return 7
        case .orderedList: return 8
        case .link: return 9
        case .image: return 10
        }
    }

    init?(rawTag: Int) {
        guard let action = Self.allCases.first(where: { $0.rawTag == rawTag }) else {
            return nil
        }
        self = action
    }
}

struct FireMarkdownInsertionResult: Equatable {
    let text: String
    let selectedRange: NSRange
}

enum FireMarkdownInsertion {
    static func apply(
        _ action: FireMarkdownFormatAction,
        text: String,
        selectedRange: NSRange
    ) -> FireMarkdownInsertionResult {
        switch action {
        case .bold:
            return wrap(text: text, selectedRange: selectedRange, prefix: "**", suffix: "**", placeholder: "")
        case .italic:
            return wrap(text: text, selectedRange: selectedRange, prefix: "*", suffix: "*", placeholder: "")
        case .strikethrough:
            return wrap(text: text, selectedRange: selectedRange, prefix: "~~", suffix: "~~", placeholder: "")
        case .inlineCode:
            return wrap(text: text, selectedRange: selectedRange, prefix: "`", suffix: "`", placeholder: "")
        case .codeBlock:
            return codeBlock(text: text, selectedRange: selectedRange)
        case .quote:
            return prefixLines(text: text, selectedRange: selectedRange) { _ in "> " }
        case .unorderedList:
            return prefixLines(text: text, selectedRange: selectedRange) { _ in "- " }
        case .orderedList:
            return prefixLines(text: text, selectedRange: selectedRange) { index in "\(index + 1). " }
        case .link:
            return wrap(text: text, selectedRange: selectedRange, prefix: "[", suffix: "](url)", placeholder: "text")
        case .image:
            return wrap(text: text, selectedRange: selectedRange, prefix: "![", suffix: "](url)", placeholder: "alt")
        }
    }

    private static func wrap(
        text: String,
        selectedRange: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        let selectedText = safeRange.length > 0 ? source.substring(with: safeRange) : placeholder
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        let nextText = source.replacingCharacters(in: safeRange, with: replacement)
        let selectedLength = safeRange.length > 0
            ? safeRange.length
            : (placeholder as NSString).length
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(
                location: safeRange.location + (prefix as NSString).length,
                length: selectedLength
            )
        )
    }

    private static func codeBlock(
        text: String,
        selectedRange: NSRange
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        let selectedText = safeRange.length > 0 ? source.substring(with: safeRange) : ""
        let startsLine = safeRange.location == 0
            || source.substring(with: NSRange(location: safeRange.location - 1, length: 1)) == "\n"
        let endLocation = safeRange.location + safeRange.length
        let endsLine = endLocation >= source.length
            || source.substring(with: NSRange(location: endLocation, length: 1)) == "\n"
        let leadingBreak = startsLine ? "" : "\n"
        let trailingBreak = endsLine ? "" : "\n"
        let replacement = "\(leadingBreak)```\n\(selectedText)\n```\(trailingBreak)"
        let nextText = source.replacingCharacters(in: safeRange, with: replacement)
        let selectionLocation = safeRange.location
            + (leadingBreak as NSString).length
            + ("```\n" as NSString).length
        let selectionLength = safeRange.length > 0 ? (selectedText as NSString).length : 0
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(location: selectionLocation, length: selectionLength)
        )
    }

    private static func prefixLines(
        text: String,
        selectedRange: NSRange,
        prefix: (Int) -> String
    ) -> FireMarkdownInsertionResult {
        let source = text as NSString
        let safeRange = boundedRange(selectedRange, in: source)
        if safeRange.length == 0 {
            let lineRange = source.lineRange(for: safeRange)
            let linePrefix = prefix(0)
            let nextText = source.replacingCharacters(
                in: NSRange(location: lineRange.location, length: 0),
                with: linePrefix
            )
            return FireMarkdownInsertionResult(
                text: nextText,
                selectedRange: NSRange(
                    location: safeRange.location + (linePrefix as NSString).length,
                    length: 0
                )
            )
        }

        let lineRange = source.lineRange(for: safeRange)
        let selectedLines = source.substring(with: lineRange)
        let preservesTrailingNewline = selectedLines.hasSuffix("\n")
        let body = preservesTrailingNewline ? String(selectedLines.dropLast()) : selectedLines
        let prefixedBody = body
            .components(separatedBy: "\n")
            .enumerated()
            .map { index, line in "\(prefix(index))\(line)" }
            .joined(separator: "\n")
        let replacement = prefixedBody + (preservesTrailingNewline ? "\n" : "")
        let nextText = source.replacingCharacters(in: lineRange, with: replacement)
        return FireMarkdownInsertionResult(
            text: nextText,
            selectedRange: NSRange(location: lineRange.location, length: (replacement as NSString).length)
        )
    }

    private static func boundedRange(_ range: NSRange, in source: NSString) -> NSRange {
        let location = min(max(range.location, 0), source.length)
        let length = min(max(range.length, 0), max(0, source.length - location))
        return NSRange(location: location, length: length)
    }
}

struct FireMarkdownToolbar: View {
    let onFormat: (FireMarkdownFormatAction) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(FireMarkdownFormatAction.allCases) { action in
                    toolbarButton(action)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .fill(FireTheme.chrome)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FireTheme.smallCornerRadius, style: .continuous)
                .strokeBorder(FireTheme.divider, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func toolbarButton(_ action: FireMarkdownFormatAction) -> some View {
        Button {
            onFormat(action)
        } label: {
            Group {
                if let systemImage = action.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Text(action.title)
                        .font(toolbarFont(for: action))
                        .strikethrough(action == .strikethrough)
                }
            }
            .frame(width: 36, height: 34)
            .foregroundStyle(FireTheme.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityLabel)
    }

    private func toolbarFont(for action: FireMarkdownFormatAction) -> Font {
        switch action {
        case .bold:
            return .system(size: 15, weight: .bold)
        case .italic:
            return .system(size: 15, weight: .medium).italic()
        default:
            return .system(size: 14, weight: .semibold)
        }
    }
}

enum FireComposerValidation {
    struct State: Equatable {
        let canSubmit: Bool
        let message: String?
    }

    static func submitState(
        route: FireComposerRoute,
        canStartAuthenticatedMutation: Bool,
        isSubmitting: Bool,
        trimmedTitle: String,
        trimmedBody: String,
        minimumTitleLength: Int,
        minimumBodyLength: Int,
        selectedCategoryID: UInt64?,
        selectedTagCount: Int,
        minimumRequiredTags: Int,
        recipientCount: Int
    ) -> State {
        guard canStartAuthenticatedMutation else {
            return State(
                canSubmit: false,
                message: "当前登录写入会话未就绪，请先完成登录同步。"
            )
        }
        guard !isSubmitting else {
            return State(canSubmit: false, message: nil)
        }

        switch route.kind {
        case .createTopic:
            guard trimmedTitle.count >= minimumTitleLength else {
                return State(
                    canSubmit: false,
                    message: "标题至少需要 \(minimumTitleLength) 个字"
                )
            }
            guard selectedCategoryID != nil else {
                return State(canSubmit: false, message: "请选择分类")
            }
            guard trimmedBody.count >= minimumBodyLength else {
                return State(
                    canSubmit: false,
                    message: "正文至少需要 \(minimumBodyLength) 个字"
                )
            }
            guard selectedTagCount >= minimumRequiredTags else {
                return State(
                    canSubmit: false,
                    message: "当前分类至少需要 \(minimumRequiredTags) 个标签"
                )
            }
        case .privateMessage:
            guard trimmedTitle.count >= minimumTitleLength else {
                return State(
                    canSubmit: false,
                    message: "标题至少需要 \(minimumTitleLength) 个字"
                )
            }
            guard trimmedBody.count >= minimumBodyLength else {
                return State(
                    canSubmit: false,
                    message: "正文至少需要 \(minimumBodyLength) 个字"
                )
            }
            guard recipientCount > 0 else {
                return State(canSubmit: false, message: "请至少添加一个收件人")
            }
        case .advancedReply:
            guard trimmedBody.count >= minimumBodyLength else {
                return State(
                    canSubmit: false,
                    message: "回复至少需要 \(minimumBodyLength) 个字"
                )
            }
        }

        return State(canSubmit: true, message: nil)
    }

    static func metaStepReady(
        trimmedTitle: String,
        categoryId: UInt64?,
        selectedTagCount: Int,
        category: TopicCategoryState?,
        minimumTitleLength: Int
    ) -> Bool {
        guard trimmedTitle.count >= minimumTitleLength, categoryId != nil, let category else {
            return false
        }
        let minTags = Int(category.minimumRequiredTags)
        return selectedTagCount >= minTags
        // NOTE: required tag groups cannot be validated client-side (no tag list
        // per group in RequiredTagGroupState). Group violations are caught at
        // publish by the server. Step 1 surfaces group requirements as advisory text.
    }
}

enum FireComposerCategoryGuidance {
    static func categorySheetSummary(for category: FireTopicCategoryPresentation) -> String? {
        var parts: [String] = []

        let minimumRequiredTags = Int(category.minimumRequiredTags)
        if minimumRequiredTags > 0 {
            parts.append("至少 \(minimumRequiredTags) 个标签")
        }

        for group in category.requiredTagGroups.prefix(2) {
            let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.isEmpty {
                parts.append("标签组至少 \(group.minCount) 个")
            } else {
                parts.append("\(trimmedName) 至少 \(group.minCount) 个")
            }
        }

        let template = category.topicTemplate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !template.isEmpty {
            parts.append("自带模板")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func suggestedTags(
        category: FireTopicCategoryPresentation?,
        topTags: [String],
        selectedTags: [String],
        limit: Int = 8
    ) -> [String] {
        let selected = Set(
            selectedTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let source = (category?.allowedTags.isEmpty == false)
            ? category?.allowedTags ?? []
            : topTags

        var suggestions: [String] = []
        var seen: Set<String> = []

        for candidate in source {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = trimmed.lowercased()
            guard !trimmed.isEmpty else { continue }
            guard !selected.contains(normalized) else { continue }
            guard !seen.contains(normalized) else { continue }

            seen.insert(normalized)
            suggestions.append(trimmed)

            if suggestions.count >= limit {
                break
            }
        }

        return suggestions
    }
}

@MainActor
final class FireComposerViewController: UIViewController {
    enum Step {
        case meta
        case body
    }

    private let viewModel: FireAppViewModel
    private let route: FireComposerRoute
    private let initialBody: String?
    private let initialBodySelectionLocation: Int?
    private let initialCategoryID: UInt64?
    private let initialTags: [String]
    private let onTopicCreated: ((UInt64) -> Void)?
    private let onReplySubmitted: (() -> Void)?
    private let onPrivateMessageCreated: ((UInt64, String) -> Void)?
    private let onSubmissionNotice: ((String) -> Void)?

    private var titleText = ""
    private var bodyText = ""
    private var selectedCategoryID: UInt64?
    private var selectedTags: [String] = []
    private var selectedRecipients: [String] = []
    private var recipientQuery = ""
    private var recipientResults: [UserMentionUserState] = []
    private var bodySelection = NSRange(location: 0, length: 0)
    private var isLoadingDraft = false
    private var didLoadDraft = false
    private var didCompleteSubmission = false
    private var draftSequence: UInt32 = 0
    private var lastInjectedTemplate: String?
    private var tagInput = ""
    private var tagResults: [TagSearchItemState] = []
    private var mentionContext: FireComposerMentionContext?
    private var mentionUsers: [UserMentionUserState] = []
    private var mentionGroups: [UserMentionGroupState] = []
    private var isSubmitting = false
    private var isUploadingImage = false
    private var previewMode = false
    private var noticeMessage: String?
    private var errorMessage: String?
    private var resolvedUploads: [String: ResolvedUploadUrlState] = [:]
    private var step: Step = .body

    private var autosaveTask: Task<Void, Never>?
    private var tagSearchTask: Task<Void, Never>?
    private var mentionSearchTask: Task<Void, Never>?
    private var recipientSearchTask: Task<Void, Never>?
    private var uploadResolutionTask: Task<Void, Never>?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let noticeBanner = FireComposerBannerView(style: .success)
    private let errorBanner = FireComposerBannerView(style: .error)
    private let replyTargetCard = FireComposerCardView()
    private let replyTargetStack = UIStackView()
    private let topicHeaderStack = UIStackView()
    private let privateHeaderStack = UIStackView()
    private let topicTitleField = UITextField()
    private let privateTitleField = UITextField()
    private let categoryButton = UIButton(type: .system)
    private let requirementsCard = FireComposerCardView()
    private let requirementsStack = UIStackView()
    private let selectedTagsStack = UIStackView()
    private let suggestedTagsStack = UIStackView()
    private let tagResultsStack = UIStackView()
    private let tagField = UITextField()
    private let recipientChipsStack = UIStackView()
    private let recipientField = UITextField()
    private let recipientResultsStack = UIStackView()
    private let toolbarStack = UIStackView()
    private let imageButton = UIButton(type: .system)
    private let previewButton = UIButton(type: .system)
    private let countLabel = UILabel()
    private let markdownToolbarScroll = UIScrollView()
    private let markdownToolbarStack = UIStackView()
    private let editorContainer = FireComposerCardView()
    private let bodyTextView = UITextView()
    private let mentionResultsStack = UIStackView()
    private let bodyRequirementLabel = UILabel()
    private let previewContainer = FireComposerCardView()
    private let previewStack = UIStackView()
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private var bottomBarBottomConstraint: NSLayoutConstraint?
    private let bottomStack = UIStackView()
    private let validationLabel = UILabel()
    private let clearDraftButton = UIButton(type: .system)
    private let submitButton = UIButton(type: .system)
    private var submitButtonConfiguration = UIButton.Configuration.filled()

    init(
        viewModel: FireAppViewModel,
        route: FireComposerRoute,
        initialBody: String? = nil,
        initialBodySelectionLocation: Int? = nil,
        initialCategoryID: UInt64? = nil,
        initialTags: [String] = [],
        onTopicCreated: ((UInt64) -> Void)? = nil,
        onReplySubmitted: (() -> Void)? = nil,
        onPrivateMessageCreated: ((UInt64, String) -> Void)? = nil,
        onSubmissionNotice: ((String) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.route = route
        self.initialBody = initialBody
        self.initialBodySelectionLocation = initialBodySelectionLocation
        self.initialCategoryID = initialCategoryID
        self.initialTags = initialTags
        self.onTopicCreated = onTopicCreated
        self.onReplySubmitted = onReplySubmitted
        self.onPrivateMessageCreated = onPrivateMessageCreated
        self.onSubmissionNotice = onSubmissionNotice
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        step = initialStep(for: route.kind)
        configureChrome()
        configureLayout()
        configureTopicHeader()
        configurePrivateHeader()
        configureReplyTargetCard()
        configureComposerToolbar()
        configureEditor()
        configurePreview()
        configureBottomBar()
        render()
        Task { [weak self] in
            await self?.loadInitialComposerState()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || navigationController?.isBeingDismissed == true else { return }
        cancelAsyncWork()
        guard !didCompleteSubmission else { return }
        Task { [weak self] in
            await self?.persistDraftIfNeeded()
        }
    }

    private var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    private var availableCategories: [FireTopicCategoryPresentation] {
        viewModel.allCategories()
            .filter { ($0.permission ?? 1) <= 1 }
            .sorted { lhs, rhs in
                categoryDisplayName(for: lhs) < categoryDisplayName(for: rhs)
            }
    }

    private var selectedCategory: FireTopicCategoryPresentation? {
        availableCategories.first(where: { $0.id == selectedCategoryID })
    }

    private var trimmedTitle: String {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumTitleLength: Int {
        switch route.kind {
        case .createTopic:
            return Int(max(viewModel.session.bootstrap.minTopicTitleLength, 1))
        case .privateMessage:
            return Int(max(viewModel.session.bootstrap.minPersonalMessageTitleLength, 1))
        case .advancedReply:
            return 0
        }
    }

    private var minimumBodyLength: Int {
        switch route.kind {
        case .createTopic:
            return Int(max(viewModel.session.bootstrap.minFirstPostLength, 1))
        case .advancedReply(_, _, _, _, _, let isPrivateMessage):
            if isPrivateMessage {
                return Int(max(viewModel.session.bootstrap.minPersonalMessagePostLength, 1))
            }
            return Int(max(viewModel.session.bootstrap.minPostLength, 1))
        case .privateMessage:
            return Int(max(viewModel.session.bootstrap.minPersonalMessagePostLength, 1))
        }
    }

    private var selectedCategoryMinimumTags: Int {
        Int(selectedCategory?.minimumRequiredTags ?? 0)
    }

    private var selectedCategoryRequiredTagGroups: [RequiredTagGroupState] {
        selectedCategory?.requiredTagGroups ?? []
    }

    private var suggestedTags: [String] {
        guard selectedCategory != nil else { return [] }
        return FireComposerCategoryGuidance.suggestedTags(
            category: selectedCategory,
            topTags: viewModel.topTags(),
            selectedTags: selectedTags
        )
    }

    private var selectedCategoryHasTemplate: Bool {
        let template = selectedCategory?.topicTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !template.isEmpty
    }

    private var hasDraftContent: Bool {
        switch route.kind {
        case .createTopic, .privateMessage:
            return !trimmedTitle.isEmpty || !trimmedBody.isEmpty
        case .advancedReply:
            return !trimmedBody.isEmpty
        }
    }

    private var submitValidation: FireComposerValidation.State {
        FireComposerValidation.submitState(
            route: route,
            canStartAuthenticatedMutation: viewModel.canStartAuthenticatedMutation,
            isSubmitting: isSubmitting,
            trimmedTitle: trimmedTitle,
            trimmedBody: trimmedBody,
            minimumTitleLength: minimumTitleLength,
            minimumBodyLength: minimumBodyLength,
            selectedCategoryID: selectedCategoryID,
            selectedTagCount: selectedTags.count,
            minimumRequiredTags: selectedCategoryMinimumTags,
            recipientCount: selectedRecipients.count
        )
    }

    private var markdownImages: [FireComposerMarkdownImage] {
        extractMarkdownImages(from: bodyText)
    }

    private var submissionSuccessMessage: String {
        switch route.kind {
        case .createTopic:
            return "帖子已发布。"
        case .privateMessage:
            return "私信已发送。"
        case .advancedReply:
            return "回复已发送。"
        }
    }

    private var pendingReviewMessage: String {
        switch route.kind {
        case .createTopic:
            return "帖子已提交，等待审核。"
        case .privateMessage:
            return "私信已提交，等待审核。"
        case .advancedReply:
            return "回复已提交，等待审核。"
        }
    }

    private func configureChrome() {
        view.backgroundColor = FireComposerPalette.canvas
        navigationItem.largeTitleDisplayMode = .never
        renderNavBar()
    }

    private func renderNavBar() {
        switch route.kind {
        case .createTopic:
            switch step {
            case .meta:
                title = route.navigationTitle
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: "关闭",
                    style: .plain,
                    target: self,
                    action: #selector(closeButtonTapped)
                )
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: "下一步",
                    style: .done,
                    target: self,
                    action: #selector(nextStepButtonTapped)
                )
            case .body:
                title = "编辑正文"
                navigationItem.leftBarButtonItem = UIBarButtonItem(
                    title: "上一步",
                    style: .plain,
                    target: self,
                    action: #selector(backStepButtonTapped)
                )
                navigationItem.rightBarButtonItem = UIBarButtonItem(
                    title: route.submitLabel,
                    style: .done,
                    target: self,
                    action: #selector(submitButtonTapped)
                )
            }
        case .advancedReply, .privateMessage:
            title = route.navigationTitle
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: "关闭",
                style: .plain,
                target: self,
                action: #selector(closeButtonTapped)
            )
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: route.submitLabel,
                style: .done,
                target: self,
                action: #selector(submitButtonTapped)
            )
        }
    }

    private func configureLayout() {
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        contentStack.addArrangedSubview(noticeBanner)
        contentStack.addArrangedSubview(errorBanner)
        contentStack.addArrangedSubview(replyTargetCard)
        contentStack.addArrangedSubview(topicHeaderStack)
        contentStack.addArrangedSubview(privateHeaderStack)
        contentStack.addArrangedSubview(toolbarStack)
        contentStack.addArrangedSubview(markdownToolbarScroll)
        contentStack.addArrangedSubview(editorContainer)
        contentStack.addArrangedSubview(mentionResultsStack)
        contentStack.addArrangedSubview(bodyRequirementLabel)
        contentStack.addArrangedSubview(previewContainer)

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomBar)

        bottomBarBottomConstraint = bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBarBottomConstraint!,

            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(composerKeyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(composerKeyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private func configureTopicHeader() {
        topicHeaderStack.axis = .vertical
        topicHeaderStack.spacing = 14

        configureTitleField(topicTitleField, placeholder: "标题")
        topicTitleField.addTarget(self, action: #selector(titleFieldChanged(_:)), for: .editingChanged)

        categoryButton.contentHorizontalAlignment = .leading
        categoryButton.configuration = makePlainButtonConfiguration(title: "选择分类", systemImage: "folder")
        categoryButton.addTarget(self, action: #selector(categoryButtonTapped), for: .touchUpInside)

        requirementsStack.axis = .vertical
        requirementsStack.spacing = 8
        requirementsCard.embed(requirementsStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))

        configureHorizontalStack(selectedTagsStack)
        configureHorizontalStack(suggestedTagsStack)
        configureVerticalResultsStack(tagResultsStack)

        configureSearchField(tagField, placeholder: "添加标签")
        tagField.addTarget(self, action: #selector(tagFieldChanged(_:)), for: .editingChanged)

        topicHeaderStack.addArrangedSubview(topicTitleField)
        topicHeaderStack.addArrangedSubview(categoryButton)
        topicHeaderStack.addArrangedSubview(requirementsCard)
        topicHeaderStack.addArrangedSubview(selectedTagsStack)
        topicHeaderStack.addArrangedSubview(tagField)
        topicHeaderStack.addArrangedSubview(suggestedTagsStack)
        topicHeaderStack.addArrangedSubview(tagResultsStack)
    }

    private func configurePrivateHeader() {
        privateHeaderStack.axis = .vertical
        privateHeaderStack.spacing = 14

        configureHorizontalStack(recipientChipsStack)
        configureSearchField(recipientField, placeholder: "添加收件人")
        recipientField.textContentType = .username
        recipientField.addTarget(self, action: #selector(recipientFieldChanged(_:)), for: .editingChanged)
        configureVerticalResultsStack(recipientResultsStack)
        configureTitleField(privateTitleField, placeholder: "标题")
        privateTitleField.addTarget(self, action: #selector(titleFieldChanged(_:)), for: .editingChanged)

        privateHeaderStack.addArrangedSubview(recipientChipsStack)
        privateHeaderStack.addArrangedSubview(recipientField)
        privateHeaderStack.addArrangedSubview(recipientResultsStack)
        privateHeaderStack.addArrangedSubview(privateTitleField)
    }

    private func configureReplyTargetCard() {
        replyTargetStack.axis = .vertical
        replyTargetStack.spacing = 6
        replyTargetCard.embed(replyTargetStack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
    }

    private func configureComposerToolbar() {
        toolbarStack.axis = .horizontal
        toolbarStack.alignment = .center
        toolbarStack.spacing = 12

        imageButton.configuration = makePlainButtonConfiguration(title: "图片", systemImage: "photo")
        imageButton.addTarget(self, action: #selector(imageButtonTapped), for: .touchUpInside)
        previewButton.configuration = makePlainButtonConfiguration(title: "预览", systemImage: "eye")
        previewButton.addTarget(self, action: #selector(previewButtonTapped), for: .touchUpInside)

        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .right

        toolbarStack.addArrangedSubview(imageButton)
        toolbarStack.addArrangedSubview(previewButton)
        toolbarStack.addArrangedSubview(UIView())
        toolbarStack.addArrangedSubview(countLabel)

        markdownToolbarScroll.showsHorizontalScrollIndicator = false
        markdownToolbarScroll.backgroundColor = FireComposerPalette.chrome
        markdownToolbarScroll.layer.cornerRadius = FireTheme.smallCornerRadius
        markdownToolbarScroll.layer.borderColor = FireComposerPalette.divider.cgColor
        markdownToolbarScroll.layer.borderWidth = 1
        markdownToolbarScroll.heightAnchor.constraint(equalToConstant: 42).isActive = true

        markdownToolbarStack.axis = .horizontal
        markdownToolbarStack.alignment = .center
        markdownToolbarStack.spacing = 4
        markdownToolbarStack.translatesAutoresizingMaskIntoConstraints = false
        markdownToolbarScroll.addSubview(markdownToolbarStack)

        NSLayoutConstraint.activate([
            markdownToolbarStack.leadingAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.leadingAnchor, constant: 6),
            markdownToolbarStack.trailingAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.trailingAnchor, constant: -6),
            markdownToolbarStack.topAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.topAnchor),
            markdownToolbarStack.bottomAnchor.constraint(equalTo: markdownToolbarScroll.contentLayoutGuide.bottomAnchor),
            markdownToolbarStack.heightAnchor.constraint(equalTo: markdownToolbarScroll.frameLayoutGuide.heightAnchor),
        ])

        for action in FireMarkdownFormatAction.allCases {
            let button = UIButton(type: .system)
            button.tag = action.rawTag
            button.accessibilityLabel = action.accessibilityLabel
            button.configuration = makeToolbarButtonConfiguration(for: action)
            button.addTarget(self, action: #selector(markdownButtonTapped(_:)), for: .touchUpInside)
            markdownToolbarStack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 36),
                button.heightAnchor.constraint(equalToConstant: 34),
            ])
        }
    }

    private func configureEditor() {
        bodyTextView.delegate = self
        bodyTextView.font = .preferredFont(forTextStyle: .body)
        bodyTextView.adjustsFontForContentSizeCategory = true
        bodyTextView.backgroundColor = .clear
        bodyTextView.autocorrectionType = .yes
        bodyTextView.autocapitalizationType = .sentences
        bodyTextView.smartDashesType = .yes
        bodyTextView.smartQuotesType = .yes
        bodyTextView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        editorContainer.embed(bodyTextView, insets: .zero)
        bodyTextView.heightAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true

        configureVerticalResultsStack(mentionResultsStack)

        bodyRequirementLabel.font = .preferredFont(forTextStyle: .caption1)
        bodyRequirementLabel.adjustsFontForContentSizeCategory = true
        bodyRequirementLabel.textColor = .secondaryLabel
        bodyRequirementLabel.numberOfLines = 0
    }

    private func configurePreview() {
        previewStack.axis = .vertical
        previewStack.spacing = 14
        previewContainer.embed(previewStack, insets: UIEdgeInsets(top: 18, left: 18, bottom: 18, right: 18))
    }

    private func configureBottomBar() {
        bottomStack.axis = .vertical
        bottomStack.spacing = 10
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(bottomStack)

        validationLabel.font = .preferredFont(forTextStyle: .caption1)
        validationLabel.adjustsFontForContentSizeCategory = true
        validationLabel.textColor = .secondaryLabel
        validationLabel.numberOfLines = 0

        clearDraftButton.setTitle("清除草稿", for: .normal)
        clearDraftButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        clearDraftButton.addTarget(self, action: #selector(clearDraftButtonTapped), for: .touchUpInside)

        submitButtonConfiguration.cornerStyle = .capsule
        submitButtonConfiguration.baseBackgroundColor = FireTopicListPalette.accent
        submitButtonConfiguration.baseForegroundColor = .white
        submitButtonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        submitButton.configuration = submitButtonConfiguration
        submitButton.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [clearDraftButton, UIView(), submitButton])
        buttonRow.axis = .horizontal
        buttonRow.alignment = .center
        buttonRow.spacing = 12

        bottomStack.addArrangedSubview(validationLabel)
        bottomStack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            bottomStack.leadingAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            bottomStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            bottomStack.bottomAnchor.constraint(equalTo: bottomBar.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            submitButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    private func render() {
        noticeBanner.setMessage(noticeMessage)
        errorBanner.setMessage(errorMessage)

        topicHeaderStack.isHidden = {
            if case .createTopic = route.kind, step == .meta { return false }
            return true
        }()
        privateHeaderStack.isHidden = {
            if case .privateMessage = route.kind { return false }
            return true
        }()
        replyTargetCard.isHidden = {
            if case .advancedReply = route.kind { return false }
            return true
        }()
        toolbarStack.isHidden = isMetaStepForCreateTopic

        renderReplyTarget()
        renderTopicHeader()
        renderPrivateHeader()
        renderToolbar()
        renderEditor()
        renderPreview()
        renderBottomBar()
    }

    private var isMetaStepForCreateTopic: Bool {
        if case .createTopic = route.kind, step == .meta { return true }
        return false
    }

    private func renderReplyTarget() {
        replyTargetStack.removeAllArrangedSubviews()
        guard case .advancedReply = route.kind else { return }
        let titleLabel = makeLabel(route.topicTitle ?? "回复话题", style: .headline, color: .label)
        replyTargetStack.addArrangedSubview(titleLabel)
        if let replyToUsername = route.replyToUsername, !replyToUsername.isEmpty {
            replyTargetStack.addArrangedSubview(makeLabel("回复 @\(replyToUsername)", style: .caption1, color: FireTopicListPalette.accent))
        } else if let replyToPostNumber = route.replyToPostNumber {
            replyTargetStack.addArrangedSubview(makeLabel("回复 #\(replyToPostNumber)", style: .caption1, color: FireTopicListPalette.accent))
        }
    }

    private func renderTopicHeader() {
        guard case .createTopic = route.kind else { return }
        setTextField(topicTitleField, text: titleText)
        categoryButton.configuration = makePlainButtonConfiguration(
            title: selectedCategory.map(categoryDisplayName(for:)) ?? "选择分类",
            systemImage: "folder"
        )

        requirementsStack.removeAllArrangedSubviews()
        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 8
        let icon = UIImageView(image: UIImage(systemName: selectedCategory == nil ? "info.circle.fill" : "checkmark.circle.fill"))
        icon.tintColor = selectedCategory == nil ? .secondaryLabel : FireTopicListPalette.accent
        icon.setContentHuggingPriority(.required, for: .horizontal)
        headerRow.addArrangedSubview(icon)
        headerRow.addArrangedSubview(makeLabel("发布要求", style: .subheadline, color: .label, weight: .semibold))
        requirementsStack.addArrangedSubview(headerRow)

        if let selectedCategory {
            requirementsStack.addArrangedSubview(makeLabel("当前分类：\(categoryDisplayName(for: selectedCategory))", style: .caption1, color: .label))
            if selectedCategoryMinimumTags > 0 {
                let progressColor = selectedTags.count >= selectedCategoryMinimumTags ? FireTopicListPalette.accent : .secondaryLabel
                requirementsStack.addArrangedSubview(makeLabel("标签进度：\(selectedTags.count)/\(selectedCategoryMinimumTags)", style: .caption1, color: progressColor))
            }
            for group in selectedCategoryRequiredTagGroups {
                requirementsStack.addArrangedSubview(makeLabel(requiredTagGroupRequirementText(group), style: .caption1, color: .secondaryLabel))
            }
            if selectedCategoryHasTemplate {
                requirementsStack.addArrangedSubview(makeLabel("该分类会自动带出发帖模板。", style: .caption1, color: .secondaryLabel))
            }
        } else {
            requirementsStack.addArrangedSubview(makeLabel("先选择分类，系统才会显示该分类的模板和标签要求。", style: .caption1, color: .secondaryLabel))
        }

        renderTagChips()
        renderSuggestedTags()
        renderTagResults()
        setTextField(tagField, text: tagInput)
        let canShowTags = viewModel.canTagTopics || selectedCategoryMinimumTags > 0
        selectedTagsStack.isHidden = selectedTags.isEmpty
        suggestedTagsStack.isHidden = !canShowTags || suggestedTags.isEmpty
        tagField.isHidden = !canShowTags
        tagResultsStack.isHidden = tagResults.isEmpty
    }

    private func renderPrivateHeader() {
        guard case .privateMessage = route.kind else { return }
        renderRecipientChips()
        renderRecipientResults()
        setTextField(recipientField, text: recipientQuery)
        setTextField(privateTitleField, text: titleText)
        recipientChipsStack.isHidden = selectedRecipients.isEmpty
        recipientResultsStack.isHidden = recipientResults.isEmpty
    }

    private func renderTagChips() {
        selectedTagsStack.removeAllArrangedSubviews()
        for tag in selectedTags {
            let button = makeChipButton(title: "#\(tag)", systemImage: "xmark")
            button.addAction(UIAction { [weak self] _ in
                self?.selectedTags.removeAll { $0 == tag }
                self?.errorMessage = nil
                self?.scheduleAutosave()
                self?.render()
            }, for: .touchUpInside)
            selectedTagsStack.addArrangedSubview(button)
        }
        selectedTagsStack.addArrangedSubview(UIView())
    }

    private func renderSuggestedTags() {
        suggestedTagsStack.removeAllArrangedSubviews()
        for tag in suggestedTags {
            let button = makeChipButton(title: "#\(tag)", systemImage: "plus", emphasized: false)
            button.addAction(UIAction { [weak self] _ in
                self?.addTag(tag)
            }, for: .touchUpInside)
            suggestedTagsStack.addArrangedSubview(button)
        }
        suggestedTagsStack.addArrangedSubview(UIView())
    }

    private func renderTagResults() {
        tagResultsStack.removeAllArrangedSubviews()
        for item in tagResults {
            let title = item.count > 0 ? "#\(item.name)  \(item.count)" : "#\(item.name)"
            let button = makeResultButton(title: title, subtitle: nil, systemImage: "number")
            button.addAction(UIAction { [weak self] _ in
                self?.addTag(item.name)
            }, for: .touchUpInside)
            tagResultsStack.addArrangedSubview(button)
        }
    }

    private func renderRecipientChips() {
        recipientChipsStack.removeAllArrangedSubviews()
        for username in selectedRecipients {
            let button = makeChipButton(title: "@\(username)", systemImage: "xmark")
            button.addAction(UIAction { [weak self] _ in
                self?.removeRecipient(username)
                self?.render()
            }, for: .touchUpInside)
            recipientChipsStack.addArrangedSubview(button)
        }
        recipientChipsStack.addArrangedSubview(UIView())
    }

    private func renderRecipientResults() {
        recipientResultsStack.removeAllArrangedSubviews()
        for user in recipientResults {
            let subtitle = user.name?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("")
            let button = makeResultButton(
                title: "@\(user.username)",
                subtitle: subtitle?.isEmpty == false ? subtitle : nil,
                systemImage: nil,
                monogram: monogramForUsername(username: user.username)
            )
            button.addAction(UIAction { [weak self] _ in
                self?.addRecipient(user)
            }, for: .touchUpInside)
            recipientResultsStack.addArrangedSubview(button)
        }
    }

    private func renderToolbar() {
        imageButton.configuration = makePlainButtonConfiguration(
            title: isUploadingImage ? "上传中" : "图片",
            systemImage: "photo"
        )
        imageButton.isEnabled = !isUploadingImage && !isSubmitting
        previewButton.configuration = makePlainButtonConfiguration(
            title: previewMode ? "继续编辑" : "预览",
            systemImage: previewMode ? "pencil" : "eye"
        )
        let countText: String
        switch route.kind {
        case .createTopic, .privateMessage:
            countText = "\(titleText.count)/\(minimumTitleLength)+"
        case .advancedReply:
            countText = "\(trimmedBody.count)/\(minimumBodyLength)+"
        }
        countLabel.text = countText
    }

    private func renderEditor() {
        if isMetaStepForCreateTopic {
            markdownToolbarScroll.isHidden = true
            editorContainer.isHidden = true
            mentionResultsStack.isHidden = true
            bodyRequirementLabel.isHidden = true
            return
        }
        markdownToolbarScroll.isHidden = previewMode
        editorContainer.isHidden = previewMode
        mentionResultsStack.isHidden = previewMode || (mentionUsers.isEmpty && mentionGroups.isEmpty)
        bodyRequirementLabel.isHidden = previewMode || trimmedBody.isEmpty || trimmedBody.count >= minimumBodyLength
        bodyRequirementLabel.text = "正文至少需要 \(minimumBodyLength) 个字"
        if bodyTextView.text != bodyText {
            bodyTextView.text = bodyText
        }
        if bodyTextView.selectedRange != bodySelection {
            bodyTextView.selectedRange = bodySelection
        }
        renderMentionResults()
    }

    private func renderMentionResults() {
        mentionResultsStack.removeAllArrangedSubviews()
        for user in mentionUsers {
            let button = makeResultButton(
                title: "@\(user.username)",
                subtitle: user.name?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(""),
                systemImage: nil,
                monogram: monogramForUsername(username: user.username)
            )
            button.addAction(UIAction { [weak self] _ in
                self?.insertMention("@\(user.username)")
            }, for: .touchUpInside)
            mentionResultsStack.addArrangedSubview(button)
        }
        for group in mentionGroups {
            let button = makeResultButton(
                title: "@\(group.name)",
                subtitle: group.fullName?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty(""),
                systemImage: "person.3.fill"
            )
            button.addAction(UIAction { [weak self] _ in
                self?.insertMention("@\(group.name)")
            }, for: .touchUpInside)
            mentionResultsStack.addArrangedSubview(button)
        }
    }

    private func renderPreview() {
        previewContainer.isHidden = isMetaStepForCreateTopic ? true : !previewMode
        previewStack.removeAllArrangedSubviews()
        guard previewMode, !isMetaStepForCreateTopic else { return }

        switch route.kind {
        case .createTopic, .privateMessage:
            previewStack.addArrangedSubview(makeLabel(trimmedTitle.isEmpty ? "（无标题）" : trimmedTitle, style: .title2, color: .label, weight: .bold))
        case .advancedReply:
            break
        }

        if case .privateMessage = route.kind, !selectedRecipients.isEmpty {
            previewStack.addArrangedSubview(makeLabel(selectedRecipients.map { "@\($0)" }.joined(separator: "、"), style: .caption1, color: FireTopicListPalette.accent, weight: .semibold))
        }
        if let selectedCategory, case .createTopic = route.kind {
            previewStack.addArrangedSubview(makeLabel(categoryDisplayName(for: selectedCategory), style: .caption1, color: FireTopicListPalette.accent, weight: .semibold))
        }
        if !selectedTags.isEmpty, case .createTopic = route.kind {
            previewStack.addArrangedSubview(makeLabel(selectedTags.map { "#\($0)" }.joined(separator: "  "), style: .caption1, color: FireTopicListPalette.accent, weight: .medium))
        }

        let bodyLabel = makeLabel(trimmedBody.isEmpty ? "暂无内容" : bodyText, style: .body, color: trimmedBody.isEmpty ? .secondaryLabel : .label)
        bodyLabel.numberOfLines = 0
        previewStack.addArrangedSubview(bodyLabel)

        if !markdownImages.isEmpty {
            previewStack.addArrangedSubview(makeLabel("图片预览", style: .subheadline, color: .label, weight: .semibold))
            for image in markdownImages {
                let label = image.altText ?? image.urlString
                let resolved = resolvedURL(for: image.urlString)?.absoluteString ?? image.urlString
                previewStack.addArrangedSubview(makeLabel("\(label)\n\(resolved)", style: .caption1, color: .secondaryLabel))
            }
        }
    }

    private func renderBottomBar() {
        let validation = submitValidation
        validationLabel.text = validation.canSubmit ? nil : validation.message
        validationLabel.isHidden = validation.canSubmit || validation.message?.isEmpty != false
        clearDraftButton.isHidden = draftSequence == 0

        let isMetaStep: Bool = {
            if case .createTopic = route.kind, step == .meta { return true }
            return false
        }()
        navigationItem.rightBarButtonItem?.isEnabled = isMetaStep ? true : validation.canSubmit
        submitButton.isEnabled = validation.canSubmit

        var configuration = submitButtonConfiguration
        configuration.title = isSubmitting ? "提交中" : route.submitLabel
        configuration.showsActivityIndicator = isSubmitting
        configuration.baseBackgroundColor = validation.canSubmit ? FireTopicListPalette.accent : .tertiaryLabel
        submitButton.configuration = configuration

        if case .createTopic = route.kind, step == .body {
            navigationItem.leftBarButtonItem?.isEnabled = true
        } else {
            navigationItem.leftBarButtonItem?.isEnabled = !isSubmitting
        }
    }

    @objc private func composerKeyboardWillChangeFrame(_ notification: Notification) {
        guard let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let converted = view.convert(frameEnd, from: nil)
        let overlap = max(0, view.bounds.maxY - converted.minY)
        applyKeyboardInset(overlap, notification: notification)
    }

    @objc private func composerKeyboardWillHide(_ notification: Notification) {
        applyKeyboardInset(0, notification: notification)
    }

    private func applyKeyboardInset(_ overlap: CGFloat, notification: Notification) {
        scrollView.contentInset.bottom = overlap
        scrollView.verticalScrollIndicatorInsets.bottom = overlap
        bottomBarBottomConstraint?.constant = overlap > 0 ? -overlap : 0
        let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? UInt(UIView.AnimationCurve.easeInOut.rawValue)
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [UIView.AnimationOptions(rawValue: curveRaw << 16), .beginFromCurrentState]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    private func initialStep(for kind: FireComposerRoute.Kind) -> Step {
        switch kind {
        case .createTopic:
            return .meta
        case .advancedReply, .privateMessage:
            return .body
        }
    }

    private func goToMetaStep() {
        guard case .createTopic = route.kind else { return }
        step = .meta
        errorMessage = nil
        renderNavBar()
        render()
    }

    private func goToBodyStep() {
        guard case .createTopic = route.kind else {
            step = .body
            renderNavBar()
            render()
            return
        }
        guard FireComposerValidation.metaStepReady(
            trimmedTitle: trimmedTitle,
            categoryId: selectedCategoryID,
            selectedTagCount: selectedTags.count,
            category: selectedCategory,
            minimumTitleLength: minimumTitleLength
        ) else {
            showSubmissionError("请先完善标题、分类和标签。")
            return
        }
        applyCategoryTemplateIfNeeded()
        step = .body
        renderNavBar()
        render()
    }

    @objc private func nextStepButtonTapped() {
        goToBodyStep()
    }

    @objc private func backStepButtonTapped() {
        goToMetaStep()
    }

    @objc private func closeButtonTapped() {
        guard !isSubmitting else { return }
        dismiss(animated: true)
    }

    @objc private func submitButtonTapped() {
        submitComposer()
    }

    @objc private func titleFieldChanged(_ sender: UITextField) {
        titleText = sender.text ?? ""
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    @objc private func tagFieldChanged(_ sender: UITextField) {
        tagInput = sender.text ?? ""
        performTagSearch(query: tagInput)
        render()
    }

    @objc private func recipientFieldChanged(_ sender: UITextField) {
        recipientQuery = sender.text ?? ""
        performRecipientSearch(query: recipientQuery)
        render()
    }

    @objc private func categoryButtonTapped() {
        let alert = UIAlertController(title: "选择分类", message: nil, preferredStyle: .actionSheet)
        for category in availableCategories {
            let title = categoryDisplayName(for: category)
            let summary = FireComposerCategoryGuidance.categorySheetSummary(for: category)
            let action = UIAlertAction(title: summary == nil ? title : "\(title) · \(summary ?? "")", style: .default) { [weak self] _ in
                guard let self else { return }
                selectedCategoryID = category.id
                applyCategoryTemplateIfNeeded()
                if tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tagResults = []
                } else {
                    performTagSearch(query: tagInput)
                }
                errorMessage = nil
                scheduleAutosave()
                render()
            }
            alert.addAction(action)
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = categoryButton
            popover.sourceRect = categoryButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func previewButtonTapped() {
        previewMode.toggle()
        render()
    }

    @objc private func imageButtonTapped() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    @objc private func markdownButtonTapped(_ sender: UIButton) {
        guard let action = FireMarkdownFormatAction(rawTag: sender.tag) else { return }
        applyMarkdownFormat(action)
    }

    @objc private func clearDraftButtonTapped() {
        Task { [weak self] in
            guard let self else { return }
            try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
            draftSequence = 0
            noticeMessage = "草稿已清除"
            render()
        }
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedTags.contains(trimmed) else { return }
        selectedTags.append(trimmed)
        tagInput = ""
        tagResults = []
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    private func addRecipient(_ user: UserMentionUserState) {
        let trimmed = user.username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedRecipients.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            recipientQuery = ""
            recipientResults = []
            render()
            return
        }
        selectedRecipients.append(trimmed)
        recipientQuery = ""
        recipientResults = []
        errorMessage = nil
        scheduleAutosave()
        render()
    }

    private func removeRecipient(_ username: String) {
        selectedRecipients.removeAll { $0.caseInsensitiveCompare(username) == .orderedSame }
        scheduleAutosave()
    }

    private func updateMentionSearch() {
        mentionSearchTask?.cancel()
        mentionContext = mentionContext(in: bodyText, selection: bodySelection)
        guard let mentionContext, !mentionContext.term.isEmpty else {
            mentionUsers = []
            mentionGroups = []
            render()
            return
        }

        mentionSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchUsers(
                    term: mentionContext.term,
                    includeGroups: !route.isPrivateMessage,
                    limit: 8,
                    topicID: route.topicID,
                    categoryID: selectedCategoryID ?? route.fallbackCategoryID
                )
                guard !Task.isCancelled else { return }
                mentionUsers = result.users
                mentionGroups = result.groups
                render()
            } catch {
                guard !Task.isCancelled else { return }
                mentionUsers = []
                mentionGroups = []
                render()
            }
        }
    }

    private func performRecipientSearch(query: String) {
        recipientSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            recipientResults = []
            render()
            return
        }

        recipientSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchUsers(
                    term: trimmed,
                    includeGroups: false,
                    limit: 8,
                    topicID: nil,
                    categoryID: nil
                )
                guard !Task.isCancelled else { return }
                recipientResults = result.users.filter { user in
                    !selectedRecipients.contains {
                        $0.caseInsensitiveCompare(user.username) == .orderedSame
                    }
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
                recipientResults = []
                render()
            }
        }
    }

    private func performTagSearch(query: String) {
        tagSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tagResults = []
            render()
            return
        }

        tagSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchService.searchTags(
                    query: trimmed,
                    filterForInput: true,
                    limit: 12,
                    categoryID: selectedCategoryID,
                    selectedTags: selectedTags
                )
                guard !Task.isCancelled else { return }
                let allowedTags = Set(selectedCategory?.allowedTags ?? [])
                if allowedTags.isEmpty {
                    tagResults = result.results
                } else {
                    tagResults = result.results.filter { allowedTags.contains($0.name) }
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
                tagResults = []
                render()
            }
        }
    }

    private func loadInitialComposerState() async {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        if case .createTopic = route.kind {
            selectedCategoryID = initialCategoryID
            if selectedTags.isEmpty {
                selectedTags = initialTags
            }
            applyDefaultCategoryIfNeeded()
        } else if case .privateMessage(let recipients, let initialTitle) = route.kind {
            selectedRecipients = recipients
            titleText = initialTitle ?? titleText
            if let initialBody, bodyText.isEmpty {
                bodyText = initialBody
            }
        } else if let initialBody, bodyText.isEmpty {
            bodyText = initialBody
        }

        isLoadingDraft = true
        render()
        defer {
            isLoadingDraft = false
            bodyTextView.becomeFirstResponder()
            render()
        }

        do {
            if let draft = try await viewModel.fetchDraft(draftKey: route.draftKey) {
                if case .createTopic = route.kind {
                    draftSequence = draft.sequence
                    titleText = draft.data.title ?? titleText
                    bodyText = draft.data.reply ?? bodyText
                    selectedCategoryID = draft.data.categoryId ?? selectedCategoryID
                    selectedTags = draft.data.tags
                } else if case .privateMessage = route.kind {
                    if shouldRestorePrivateMessageDraft(
                        explicitRecipients: route.recipients,
                        draftRecipients: draft.data.recipients
                    ) {
                        draftSequence = draft.sequence
                        titleText = draft.data.title ?? titleText
                        bodyText = draft.data.reply ?? bodyText
                        if !draft.data.recipients.isEmpty {
                            selectedRecipients = draft.data.recipients
                        }
                    }
                } else {
                    draftSequence = draft.sequence
                    bodyText = draft.data.reply ?? bodyText
                }
                if draftSequence > 0, draft.data.reply != nil || draft.data.title != nil {
                    noticeMessage = "已恢复草稿"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        applyInitialBodyIfNeeded()

        if case .createTopic = route.kind {
            applyDefaultCategoryIfNeeded()
            applyCategoryTemplateIfNeeded()
        }
        resolveShortUploadsIfNeeded()
        render()
    }

    private func applyDefaultCategoryIfNeeded() {
        guard case .createTopic = route.kind else { return }
        guard selectedCategoryID == nil else { return }
        if let defaultID = viewModel.session.bootstrap.defaultComposerCategory,
           availableCategories.contains(where: { $0.id == defaultID }) {
            selectedCategoryID = defaultID
            return
        }
        selectedCategoryID = availableCategories.first?.id
    }

    private func applyCategoryTemplateIfNeeded() {
        guard case .createTopic = route.kind else { return }
        let template = selectedCategory?.topicTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let template, !template.isEmpty else {
            lastInjectedTemplate = nil
            return
        }

        if trimmedBody.isEmpty || bodyText == lastInjectedTemplate {
            bodyText = template
            lastInjectedTemplate = template
            bodySelection = NSRange(location: (template as NSString).length, length: 0)
        }
    }

    private func applyInitialBodyIfNeeded() {
        guard let initialBody else { return }
        let result = FireComposerInitialBody.merge(
            initialBody: initialBody,
            currentBody: bodyText,
            preferredSelectionLocation: initialBodySelectionLocation
        )
        bodyText = result.text
        bodySelection = result.selectedRange
    }

    private func scheduleAutosave() {
        guard didLoadDraft else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await persistDraftIfNeeded()
        }
    }

    private func persistDraftIfNeeded() async {
        guard !isSubmitting else { return }
        guard !didCompleteSubmission else { return }

        if !hasDraftContent {
            guard draftSequence > 0 else { return }
            do {
                try await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                draftSequence = 0
                render()
            } catch {
                errorMessage = error.localizedDescription
                render()
            }
            return
        }

        let draftData = DraftDataState(
            reply: bodyText,
            title: {
                switch route.kind {
                case .createTopic, .privateMessage:
                    return titleText
                case .advancedReply:
                    return nil
                }
            }(),
            categoryId: {
                if case .createTopic = route.kind {
                    return selectedCategoryID
                }
                return nil
            }(),
            tags: {
                if case .createTopic = route.kind {
                    return selectedTags
                }
                return []
            }(),
            replyToPostNumber: route.replyToPostNumber,
            action: {
                switch route.kind {
                case .createTopic:
                    return "create_topic"
                case .privateMessage:
                    return "private_message"
                case .advancedReply:
                    return "reply"
                }
            }(),
            recipients: route.isPrivateMessage ? selectedRecipients : [],
            archetypeId: route.isPrivateMessage ? "private_message" : "regular",
            composerTime: nil,
            typingTime: nil
        )

        do {
            draftSequence = try await viewModel.saveDraft(
                draftKey: route.draftKey,
                data: draftData,
                sequence: draftSequence
            )
            render()
        } catch {
            errorMessage = error.localizedDescription
            render()
        }
    }

    private func submitComposer() {
        guard !isSubmitting else { return }
        errorMessage = nil
        noticeMessage = nil

        switch route.kind {
        case .createTopic:
            guard !trimmedTitle.isEmpty else {
                showSubmissionError("标题不能为空。")
                return
            }
            guard trimmedTitle.count >= minimumTitleLength else {
                showSubmissionError("标题至少需要 \(minimumTitleLength) 个字。")
                return
            }
            guard let selectedCategoryID else {
                showSubmissionError("请选择分类。")
                return
            }
            guard !trimmedBody.isEmpty else {
                showSubmissionError("正文不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("正文至少需要 \(minimumBodyLength) 个字。")
                return
            }
            guard selectedTags.count >= selectedCategoryMinimumTags else {
                showSubmissionError("当前分类至少需要 \(selectedCategoryMinimumTags) 个标签。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    let topicID = try await viewModel.createTopic(
                        title: trimmedTitle,
                        raw: trimmedBody,
                        categoryID: selectedCategoryID,
                        tags: selectedTags
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onTopicCreated?(topicID)
                    }
                } catch {
                    handleSubmissionError(error)
                }
            }

        case .privateMessage:
            guard !trimmedTitle.isEmpty else {
                showSubmissionError("标题不能为空。")
                return
            }
            guard trimmedTitle.count >= minimumTitleLength else {
                showSubmissionError("标题至少需要 \(minimumTitleLength) 个字。")
                return
            }
            guard !trimmedBody.isEmpty else {
                showSubmissionError("正文不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("正文至少需要 \(minimumBodyLength) 个字。")
                return
            }
            guard !selectedRecipients.isEmpty else {
                showSubmissionError("请至少添加一个收件人。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    let topicID = try await viewModel.createPrivateMessage(
                        title: trimmedTitle,
                        raw: trimmedBody,
                        targetRecipients: selectedRecipients
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    let submittedTitle = trimmedTitle
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onPrivateMessageCreated?(topicID, submittedTitle)
                    }
                } catch {
                    handleSubmissionError(error)
                }
            }

        case .advancedReply(let topicID, _, _, let replyToPostNumber, _, _):
            guard !trimmedBody.isEmpty else {
                showSubmissionError("回复内容不能为空。")
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                showSubmissionError("回复至少需要 \(minimumBodyLength) 个字。")
                return
            }

            beginSubmitting()
            Task { [weak self] in
                guard let self else { return }
                defer { endSubmitting() }
                do {
                    try await viewModel.submitReply(
                        topicId: topicID,
                        raw: trimmedBody,
                        replyToPostNumber: replyToPostNumber
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    finishSubmission(message: submissionSuccessMessage) { [weak self] in
                        self?.onReplySubmitted?()
                    }
                } catch {
                    handleSubmissionError(error) { [weak self] in
                        self?.onReplySubmitted?()
                    }
                }
            }
        }
    }

    private func beginSubmitting() {
        isSubmitting = true
        view.endEditing(true)
        render()
    }

    private func endSubmitting() {
        isSubmitting = false
        render()
    }

    private func handleSubmissionError(_ error: Error, pendingReviewCompletion: (() -> Void)? = nil) {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("pending review") {
            Task { [weak self] in
                guard let self else { return }
                try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                draftSequence = 0
                finishSubmission(message: pendingReviewMessage) {
                    pendingReviewCompletion?()
                }
            }
            return
        }
        showSubmissionError(message)
    }

    private func finishSubmission(message: String, completion: (() -> Void)? = nil) {
        didCompleteSubmission = true
        autosaveTask?.cancel()
        onSubmissionNotice?(message)
        dismiss(animated: true) {
            completion?()
        }
    }

    private func showSubmissionError(_ message: String) {
        errorMessage = message
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        render()
    }

    private func insertMention(_ mention: String) {
        replaceText(in: mentionContext?.replacementRange ?? bodySelection, with: "\(mention) ")
        mentionContext = nil
        mentionUsers = []
        mentionGroups = []
        render()
    }

    private func applyMarkdownFormat(_ action: FireMarkdownFormatAction) {
        let result = FireMarkdownInsertion.apply(
            action,
            text: bodyText,
            selectedRange: bodySelection
        )
        bodyText = result.text
        bodySelection = result.selectedRange
        updateTextViewSelection()
        bodyTextView.becomeFirstResponder()
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
        render()
    }

    private func replaceText(in range: NSRange, with replacement: String) {
        let source = bodyText as NSString
        let safeRange = NSRange(
            location: min(max(range.location, 0), source.length),
            length: min(max(range.length, 0), max(0, source.length - range.location))
        )
        bodyText = source.replacingCharacters(in: safeRange, with: replacement)
        bodySelection = NSRange(
            location: safeRange.location + (replacement as NSString).length,
            length: 0
        )
        updateTextViewSelection()
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
    }

    private func updateTextViewSelection() {
        if bodyTextView.text != bodyText {
            bodyTextView.text = bodyText
        }
        bodyTextView.selectedRange = bodySelection
    }

    private func uploadImageData(_ bytes: Data, fileExtension: String, mimeType: String) {
        Task { [weak self] in
            guard let self else { return }
            isUploadingImage = true
            render()
            defer {
                isUploadingImage = false
                render()
            }
            do {
                let fileName = "fire-\(UUID().uuidString).\(fileExtension)"
                let result = try await viewModel.uploadImage(
                    fileName: fileName,
                    mimeType: mimeType,
                    bytes: bytes
                )
                let markdown = markdownForUpload(result)
                let prefix = bodySelection.location == 0 ? "" : "\n"
                replaceText(in: bodySelection, with: "\(prefix)\(markdown)\n")
                resolveShortUploadsIfNeeded()
                render()
            } catch {
                errorMessage = error.localizedDescription
                render()
            }
        }
    }

    private func markdownForUpload(_ result: UploadResultState) -> String {
        let alt = result.originalFilename ?? "image"
        let width = result.thumbnailWidth ?? result.width
        let height = result.thumbnailHeight ?? result.height
        if let width, let height {
            return "![\(alt)|\(width)x\(height)](\(result.shortUrl))"
        }
        return "![\(alt)](\(result.shortUrl))"
    }

    private func resolveShortUploadsIfNeeded() {
        uploadResolutionTask?.cancel()
        let missing = Array(
            Set(
                markdownImages
                    .map(\.urlString)
                    .filter { $0.hasPrefix("upload://") && resolvedUploads[$0] == nil }
            )
        )
        guard !missing.isEmpty else { return }

        uploadResolutionTask = Task {
            do {
                let resolved = try await viewModel.lookupUploadUrls(shortUrls: missing)
                guard !Task.isCancelled else { return }
                for item in resolved {
                    resolvedUploads[item.shortUrl] = item
                }
                render()
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func resolvedURL(for rawValue: String) -> URL? {
        let resolvedValue: String
        if rawValue.hasPrefix("upload://") {
            guard let resolved = resolvedUploads[rawValue]?.url else {
                return nil
            }
            resolvedValue = resolved
        } else {
            resolvedValue = rawValue
        }

        if resolvedValue.hasPrefix("/") {
            return URL(string: "\(baseURLString)\(resolvedValue)")
        }
        return URL(string: resolvedValue)
    }

    private func mentionContext(in text: String, selection: NSRange) -> FireComposerMentionContext? {
        guard selection.length == 0 else { return nil }
        let source = text as NSString
        guard selection.location <= source.length else { return nil }
        let prefix = source.substring(to: selection.location)
        let regex = try? NSRegularExpression(pattern: "(?:^|\\s)@([A-Za-z0-9_-]{1,32})$")
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        guard let match = regex?.firstMatch(in: prefix, range: range) else { return nil }
        let termRange = match.range(at: 1)
        guard termRange.location != NSNotFound else { return nil }
        let term = (prefix as NSString).substring(with: termRange)
        let replacementRange = NSRange(
            location: termRange.location - 1,
            length: selection.location - termRange.location + 1
        )
        return FireComposerMentionContext(replacementRange: replacementRange, term: term)
    }

    private func categoryDisplayName(for category: FireTopicCategoryPresentation) -> String {
        guard let parentID = category.parentCategoryId,
              let parent = viewModel.allCategories().first(where: { $0.id == parentID })
        else {
            return category.displayName
        }
        return "\(parent.displayName) / \(category.displayName)"
    }

    private func requiredTagGroupRequirementText(_ group: RequiredTagGroupState) -> String {
        let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "需要从一个标签组里至少选择 \(group.minCount) 个标签。"
        }
        return "标签组「\(trimmedName)」至少需要 \(group.minCount) 个标签。"
    }

    private func cancelAsyncWork() {
        autosaveTask?.cancel()
        tagSearchTask?.cancel()
        mentionSearchTask?.cancel()
        recipientSearchTask?.cancel()
        uploadResolutionTask?.cancel()
    }

    private func configureTitleField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .next
        field.clearButtonMode = .whileEditing
    }

    private func configureSearchField(_ field: UITextField, placeholder: String) {
        field.borderStyle = .roundedRect
        field.placeholder = placeholder
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.clearButtonMode = .whileEditing
    }

    private func configureHorizontalStack(_ stack: UIStackView) {
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
    }

    private func configureVerticalResultsStack(_ stack: UIStackView) {
        stack.axis = .vertical
        stack.spacing = 0
        stack.backgroundColor = FireComposerPalette.surface
        stack.layer.cornerRadius = FireTheme.mediumCornerRadius
        stack.clipsToBounds = true
    }

    private func makePlainButtonConfiguration(title: String, systemImage: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 8
        configuration.baseForegroundColor = FireTopicListPalette.accent
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
        return configuration
    }

    private func makeToolbarButtonConfiguration(for action: FireMarkdownFormatAction) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        if let systemImage = action.systemImage {
            configuration.image = UIImage(systemName: systemImage)
        } else {
            configuration.title = action.title
        }
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        return configuration
    }

    private func makeChipButton(title: String, systemImage: String, emphasized: Bool = true) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 6
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = emphasized
            ? FireTopicListPalette.accent.withAlphaComponent(0.12)
            : UIColor.tertiarySystemFill
        configuration.baseForegroundColor = emphasized ? FireTopicListPalette.accent : .secondaryLabel
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        return button
    }

    private func makeResultButton(
        title: String,
        subtitle: String?,
        systemImage: String?,
        monogram: String? = nil
    ) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.subtitle = subtitle
        configuration.imagePadding = 10
        configuration.baseForegroundColor = .label
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        if let systemImage {
            configuration.image = UIImage(systemName: systemImage)
        } else if let monogram {
            configuration.image = FireComposerMonogramRenderer.image(text: monogram)
        }
        let button = UIButton(type: .system)
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        return button
    }

    private func makeLabel(
        _ text: String,
        style: UIFont.TextStyle,
        color: UIColor,
        weight: UIFont.Weight? = nil
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = weight.map { UIFont.preferredFont(forTextStyle: style).withComposerWeight($0) }
            ?? .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func setTextField(_ field: UITextField, text: String) {
        guard field.text != text, !field.isFirstResponder else { return }
        field.text = text
    }
}

extension FireComposerViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        bodyText = textView.text ?? ""
        bodySelection = textView.selectedRange
        errorMessage = nil
        updateMentionSearch()
        scheduleAutosave()
        resolveShortUploadsIfNeeded()
        render()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        bodySelection = textView.selectedRange
        updateMentionSearch()
    }
}

extension FireComposerViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let type = provider.registeredTypeIdentifiers
            .compactMap(UTType.init)
            .first(where: { $0.conforms(to: .image) }) ?? .jpeg
        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.render()
                    return
                }
                guard let data else {
                    self.errorMessage = "读取图片失败。"
                    self.render()
                    return
                }
                self.uploadImageData(
                    data,
                    fileExtension: type.preferredFilenameExtension ?? "jpg",
                    mimeType: type.preferredMIMEType ?? "image/jpeg"
                )
            }
        }
    }
}

private enum FireComposerPalette {
    static var canvas: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode ? .black : UIColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)
            }
            return UIColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1)
        }
    }

    static var surface: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode
                    ? UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
                    : .secondarySystemBackground
            }
            return .secondarySystemBackground
        }
    }

    static var chrome: UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return FireTheme.isOledMode
                    ? UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.92)
                    : UIColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 0.90)
            }
            return UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 0.78)
        }
    }

    static var divider: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1, alpha: 0.08)
                : UIColor(white: 0, alpha: 0.08)
        }
    }
}

private final class FireComposerCardView: UIView {
    private var embeddedView: UIView?

    init() {
        super.init(frame: .zero)
        backgroundColor = FireComposerPalette.surface
        layer.cornerRadius = FireTheme.cornerRadius
        layer.borderColor = FireComposerPalette.divider.cgColor
        layer.borderWidth = 1
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func embed(_ view: UIView, insets: UIEdgeInsets) {
        embeddedView?.removeFromSuperview()
        embeddedView = view
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        backgroundColor = FireComposerPalette.surface
        layer.borderColor = FireComposerPalette.divider.cgColor
    }
}

private final class FireComposerBannerView: UIView {
    enum Style {
        case success
        case error
    }

    private let style: Style
    private let iconView = UIImageView()
    private let label = UILabel()

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMessage(_ message: String?) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        label.text = trimmed
        isHidden = trimmed.isEmpty
        accessibilityLabel = trimmed
    }

    private func configure() {
        isHidden = true
        backgroundColor = tint.withAlphaComponent(0.12)
        layer.cornerRadius = FireTheme.mediumCornerRadius

        iconView.image = UIImage(systemName: style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
        iconView.tintColor = tint
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [iconView, label])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    private var tint: UIColor {
        switch style {
        case .success:
            return .systemGreen
        case .error:
            return .systemRed
        }
    }
}

private enum FireComposerMonogramRenderer {
    static func image(text: String) -> UIImage? {
        let size = CGSize(width: 28, height: 28)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            FireTopicListPalette.accent.setFill()
            context.cgContext.fillEllipse(in: rect)

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.preferredFont(forTextStyle: .caption1).withComposerWeight(.bold),
                .foregroundColor: UIColor(red: 1, green: 1, blue: 1, alpha: 1),
                .paragraphStyle: paragraph,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textHeight = attributed.size().height
            attributed.draw(
                in: CGRect(
                    x: 0,
                    y: (size.height - textHeight) / 2,
                    width: size.width,
                    height: textHeight
                )
            )
        }
    }
}

private extension UIStackView {
    func removeAllArrangedSubviews() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
}

private extension UIFont {
    func withComposerWeight(_ weight: Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight],
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

struct FireComposerControllerHost: UIViewControllerRepresentable {
    let viewModel: FireAppViewModel
    let route: FireComposerRoute
    var initialBody: String? = nil
    var initialBodySelectionLocation: Int? = nil
    var initialCategoryID: UInt64? = nil
    var initialTags: [String] = []
    var onTopicCreated: ((UInt64) -> Void)?
    var onReplySubmitted: (() -> Void)?
    var onPrivateMessageCreated: ((UInt64, String) -> Void)?
    var onSubmissionNotice: ((String) -> Void)?

    func makeUIViewController(context: Context) -> UINavigationController {
        let composer = FireComposerViewController(
            viewModel: viewModel,
            route: route,
            initialBody: initialBody,
            initialBodySelectionLocation: initialBodySelectionLocation,
            initialCategoryID: initialCategoryID,
            initialTags: initialTags,
            onTopicCreated: onTopicCreated,
            onReplySubmitted: onReplySubmitted,
            onPrivateMessageCreated: onPrivateMessageCreated,
            onSubmissionNotice: onSubmissionNotice
        )
        let navigationController = UINavigationController(rootViewController: composer)
        navigationController.modalPresentationStyle = .fullScreen
        return navigationController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

struct FireComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var isFirstResponder: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, selectedRange: $selectedRange, isFirstResponder: $isFirstResponder)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .yes
        textView.smartQuotesType = .yes
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if uiView.selectedRange != selectedRange {
            uiView.selectedRange = selectedRange
        }
        if isFirstResponder, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var selectedRange: NSRange
        @Binding private var isFirstResponder: Bool

        init(
            text: Binding<String>,
            selectedRange: Binding<NSRange>,
            isFirstResponder: Binding<Bool>
        ) {
            _text = text
            _selectedRange = selectedRange
            _isFirstResponder = isFirstResponder
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text ?? ""
            selectedRange = textView.selectedRange
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            selectedRange = textView.selectedRange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFirstResponder = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFirstResponder = false
        }
    }
}

private func extractMarkdownImages(from text: String) -> [FireComposerMarkdownImage] {
    guard let regex = try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)") else {
        return []
    }
    let range = NSRange(location: 0, length: (text as NSString).length)
    return regex.matches(in: text, range: range).compactMap { match in
        guard match.numberOfRanges >= 3 else { return nil }
        let nsText = text as NSString
        let altText = match.range(at: 1).location != NSNotFound
            ? nsText.substring(with: match.range(at: 1)).split(separator: "|").first.map(String.init)
            : nil
        let urlString = nsText.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty else { return nil }
        return FireComposerMarkdownImage(urlString: urlString, altText: altText)
    }
}
