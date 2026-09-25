import UIKit

@MainActor
final class FireComposerViewController: UIViewController {
    let viewModel: FireAppViewModel
    let route: FireComposerRoute
    let initialBody: String?
    let initialBodySelectionLocation: Int?
    let initialCategoryID: UInt64?
    let initialTags: [String]
    let onTopicCreated: ((UInt64) -> Void)?
    let onReplySubmitted: (() -> Void)?
    let scrollToCreatedReply: Bool
    let onPrivateMessageCreated: ((UInt64, String) -> Void)?
    let onSubmissionNotice: ((String) -> Void)?

    var titleText = ""
    var bodyText = ""
    var selectedCategoryID: UInt64?
    var selectedTags: [String] = []
    var selectedRecipients: [String] = []
    var recipientQuery = ""
    var recipientResults: [UserMentionUserState] = []
    var bodySelection = NSRange(location: 0, length: 0)
    var isLoadingDraft = false
    var didLoadDraft = false
    var didCompleteSubmission = false
    var draftSequence: UInt32 = 0
    var lastInjectedTemplate: String?
    var tagInput = ""
    var tagResults: [TagSearchItemState] = []
    var mentionContext: FireComposerMentionContext?
    var mentionUsers: [UserMentionUserState] = []
    var mentionGroups: [UserMentionGroupState] = []
    var isSubmitting = false
    var isUploadingImage = false
    var previewMode = false
    var noticeMessage: String?
    var errorMessage: String?
    var resolvedUploads: [String: ResolvedUploadUrlState] = [:]

    var autosaveTask: Task<Void, Never>?
    var tagSearchTask: Task<Void, Never>?
    var mentionSearchTask: Task<Void, Never>?
    var recipientSearchTask: Task<Void, Never>?
    var uploadResolutionTask: Task<Void, Never>?

    let scrollView = UIScrollView()
    let contentStack = UIStackView()
    let noticeBanner = FireComposerBannerView(style: .success)
    let errorBanner = FireComposerBannerView(style: .error)
    let replyTargetCard = FireComposerCardView()
    let replyTargetStack = UIStackView()
    let topicHeaderStack = UIStackView()
    let privateHeaderStack = UIStackView()
    let topicTitleField = UITextField()
    let privateTitleField = UITextField()
    let categoryButton = UIButton(type: .system)
    let requirementsCard = FireComposerCardView()
    let requirementsStack = UIStackView()
    let selectedTagsStack = UIStackView()
    let suggestedTagsStack = UIStackView()
    let tagResultsStack = UIStackView()
    let tagField = UITextField()
    let recipientChipsStack = UIStackView()
    let recipientField = UITextField()
    let recipientResultsStack = UIStackView()
    let toolbarStack = UIStackView()
    let imageButton = UIButton(type: .system)
    let previewButton = UIButton(type: .system)
    let countLabel = UILabel()
    let markdownToolbarScroll = UIScrollView()
    let markdownToolbarStack = UIStackView()
    let editorContainer = FireComposerCardView()
    let bodyTextView = UITextView()
    let mentionResultsStack = UIStackView()
    let bodyRequirementLabel = UILabel()
    let previewContainer = FireComposerCardView()
    let previewStack = UIStackView()
    let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    let bottomStack = UIStackView()
    let validationLabel = UILabel()
    let clearDraftButton = UIButton(type: .system)
    let submitButton = UIButton(type: .system)
    var submitButtonConfiguration = UIButton.Configuration.filled()

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
        onSubmissionNotice: ((String) -> Void)? = nil,
        scrollToCreatedReply: Bool = false
    ) {
        self.viewModel = viewModel
        self.route = route
        self.initialBody = initialBody
        self.initialBodySelectionLocation = initialBodySelectionLocation
        self.initialCategoryID = initialCategoryID
        self.initialTags = initialTags
        self.onTopicCreated = onTopicCreated
        self.onReplySubmitted = onReplySubmitted
        self.scrollToCreatedReply = scrollToCreatedReply
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

    var baseURLString: String {
        let trimmed = viewModel.session.bootstrap.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "https://linux.do" : trimmed
    }

    var availableCategories: [FireTopicCategoryPresentation] {
        viewModel.allCategories()
            .filter { ($0.permission ?? 1) <= 1 }
            .sorted { lhs, rhs in
                categoryDisplayName(for: lhs) < categoryDisplayName(for: rhs)
            }
    }

    var selectedCategory: FireTopicCategoryPresentation? {
        availableCategories.first(where: { $0.id == selectedCategoryID })
    }

    var trimmedTitle: String {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var minimumTitleLength: Int {
        switch route.kind {
        case .createTopic:
            return Int(max(viewModel.session.bootstrap.minTopicTitleLength, 1))
        case .privateMessage:
            return Int(max(viewModel.session.bootstrap.minPersonalMessageTitleLength, 1))
        case .advancedReply:
            return 0
        }
    }

    var minimumBodyLength: Int {
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

    var selectedCategoryMinimumTags: Int {
        Int(selectedCategory?.minimumRequiredTags ?? 0)
    }

    var selectedCategoryRequiredTagGroups: [RequiredTagGroupState] {
        selectedCategory?.requiredTagGroups ?? []
    }

    var suggestedTags: [String] {
        guard selectedCategory != nil else { return [] }
        return FireComposerCategoryGuidance.suggestedTags(
            category: selectedCategory,
            topTags: viewModel.topTags(),
            selectedTags: selectedTags
        )
    }

    var selectedCategoryHasTemplate: Bool {
        let template = selectedCategory?.topicTemplate?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !template.isEmpty
    }

    var hasDraftContent: Bool {
        switch route.kind {
        case .createTopic, .privateMessage:
            return !trimmedTitle.isEmpty || !trimmedBody.isEmpty
        case .advancedReply:
            return !trimmedBody.isEmpty
        }
    }

    var submitValidation: FireComposerValidation.State {
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

    var markdownImages: [FireComposerMarkdownImage] {
        extractMarkdownImages(from: bodyText)
    }

    var submissionSuccessMessage: String {
        switch route.kind {
        case .createTopic:
            return "帖子已发布。"
        case .privateMessage:
            return "私信已发送。"
        case .advancedReply:
            return "回复已发送。"
        }
    }

    var pendingReviewMessage: String {
        switch route.kind {
        case .createTopic:
            return "帖子已提交，等待审核。"
        case .privateMessage:
            return "私信已提交，等待审核。"
        case .advancedReply:
            return "回复已提交，等待审核。"
        }
    }


    func cancelAsyncWork() {
        autosaveTask?.cancel()
        tagSearchTask?.cancel()
        mentionSearchTask?.cancel()
        recipientSearchTask?.cancel()
        uploadResolutionTask?.cancel()
    }

    func categoryDisplayName(for category: FireTopicCategoryPresentation) -> String {
        guard let parentID = category.parentCategoryId,
              let parent = viewModel.allCategories().first(where: { $0.id == parentID })
        else {
            return category.displayName
        }
        return "\(parent.displayName) / \(category.displayName)"
    }

    func requiredTagGroupRequirementText(_ group: RequiredTagGroupState) -> String {
        let trimmedName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            return "需要从一个标签组里至少选择 \(group.minCount) 个标签。"
        }
        return "标签组「\(trimmedName)」至少需要 \(group.minCount) 个标签。"
    }

}
