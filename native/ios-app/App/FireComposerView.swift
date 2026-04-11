import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FireComposerRoute: Identifiable, Equatable {
    enum Kind: Equatable {
        case createTopic
        case advancedReply(
            topicID: UInt64,
            topicTitle: String,
            categoryID: UInt64?,
            replyToPostNumber: UInt32?,
            replyToUsername: String?
        )
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .createTopic:
            return "create-topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _):
            return "reply-\(topicID)-\(replyToPostNumber ?? 0)"
        }
    }

    var navigationTitle: String {
        switch kind {
        case .createTopic:
            return "新建话题"
        case .advancedReply:
            return "完整回复"
        }
    }

    var submitLabel: String {
        switch kind {
        case .createTopic:
            return "发布"
        case .advancedReply:
            return "发送"
        }
    }

    var topicID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(let topicID, _, _, _, _):
            return topicID
        }
    }

    var topicTitle: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, let topicTitle, _, _, _):
            return topicTitle
        }
    }

    var replyToPostNumber: UInt32? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, let replyToPostNumber, _):
            return replyToPostNumber
        }
    }

    var replyToUsername: String? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, _, _, let replyToUsername):
            return replyToUsername
        }
    }

    var fallbackCategoryID: UInt64? {
        switch kind {
        case .createTopic:
            return nil
        case .advancedReply(_, _, let categoryID, _, _):
            return categoryID
        }
    }

    var draftKey: String {
        switch kind {
        case .createTopic:
            return "new_topic"
        case .advancedReply(let topicID, _, _, let replyToPostNumber, _):
            if let replyToPostNumber, replyToPostNumber > 0 {
                return "topic_\(topicID)_post_\(replyToPostNumber)"
            }
            return "topic_\(topicID)"
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

struct FireComposerView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let route: FireComposerRoute
    var initialBody: String? = nil
    var initialCategoryID: UInt64? = nil
    var initialTags: [String] = []
    var onTopicCreated: ((UInt64) -> Void)?
    var onReplySubmitted: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var selectedCategoryID: UInt64?
    @State private var selectedTags: [String] = []
    @State private var bodySelection = NSRange(location: 0, length: 0)
    @State private var isBodyFocused = false
    @State private var isLoadingDraft = false
    @State private var didLoadDraft = false
    @State private var draftSequence: UInt32 = 0
    @State private var lastInjectedTemplate: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var tagSearchTask: Task<Void, Never>?
    @State private var mentionSearchTask: Task<Void, Never>?
    @State private var uploadResolutionTask: Task<Void, Never>?
    @State private var tagInput = ""
    @State private var tagResults: [TagSearchItemState] = []
    @State private var mentionContext: FireComposerMentionContext?
    @State private var mentionUsers: [UserMentionUserState] = []
    @State private var mentionGroups: [UserMentionGroupState] = []
    @State private var showCategorySheet = false
    @State private var isSubmitting = false
    @State private var isUploadingImage = false
    @State private var previewMode = false
    @State private var noticeMessage: String?
    @State private var errorMessage: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var resolvedUploads: [String: ResolvedUploadUrlState] = [:]

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
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumTitleLength: Int {
        Int(max(viewModel.session.bootstrap.minTopicTitleLength, 1))
    }

    private var minimumBodyLength: Int {
        switch route.kind {
        case .createTopic:
            return Int(max(viewModel.session.bootstrap.minFirstPostLength, 1))
        case .advancedReply:
            return Int(max(viewModel.session.bootstrap.minPostLength, 1))
        }
    }

    private var canTagTopics: Bool {
        viewModel.canTagTopics
    }

    private var selectedCategoryMinimumTags: Int {
        Int(selectedCategory?.minimumRequiredTags ?? 0)
    }

    private var hasDraftContent: Bool {
        switch route.kind {
        case .createTopic:
            return !trimmedTitle.isEmpty || !trimmedBody.isEmpty
        case .advancedReply:
            return !trimmedBody.isEmpty
        }
    }

    private var canSubmit: Bool {
        guard viewModel.session.readiness.canWriteAuthenticatedApi else {
            return false
        }
        guard !isSubmitting else {
            return false
        }

        switch route.kind {
        case .createTopic:
            return !trimmedTitle.isEmpty
                && !trimmedBody.isEmpty
                && selectedCategoryID != nil
                && selectedTags.count >= selectedCategoryMinimumTags
        case .advancedReply:
            return !trimmedBody.isEmpty
        }
    }

    private var markdownImages: [FireComposerMarkdownImage] {
        extractMarkdownImages(from: bodyText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let noticeMessage, !noticeMessage.isEmpty {
                    noticeBanner(noticeMessage, tint: .green)
                }
                if let errorMessage, !errorMessage.isEmpty {
                    noticeBanner(errorMessage, tint: .red)
                }

                if case .advancedReply = route.kind {
                    replyTargetCard
                }

                if case .createTopic = route.kind {
                    createTopicHeader
                }

                composerToolbar

                if previewMode {
                    previewContent
                } else {
                    editorContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(route.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    dismiss()
                }
                .disabled(isSubmitting)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(route.submitLabel) {
                    submitComposer()
                }
                .disabled(!canSubmit)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .safeAreaInset(edge: .bottom) {
            bottomActionBar
        }
        .sheet(isPresented: $showCategorySheet) {
            NavigationStack {
                FireComposerCategorySheet(
                    categories: availableCategories,
                    selectedCategoryID: selectedCategoryID,
                    categoryLabel: categoryDisplayName(for:)
                ) { categoryID in
                    selectedCategoryID = categoryID
                    applyCategoryTemplateIfNeeded()
                    scheduleAutosave()
                }
            }
        }
        .task {
            await loadInitialComposerState()
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            handleSelectedPhoto(item)
        }
        .onChange(of: title) { _, _ in
            errorMessage = nil
            scheduleAutosave()
        }
        .onChange(of: bodyText) { _, _ in
            errorMessage = nil
            updateMentionSearch()
            scheduleAutosave()
            resolveShortUploadsIfNeeded()
        }
        .onChange(of: selectedCategoryID) { _, _ in
            errorMessage = nil
            if tagInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                tagResults = []
            } else {
                performTagSearch(query: tagInput)
            }
            scheduleAutosave()
        }
        .onChange(of: selectedTags) { _, _ in
            errorMessage = nil
            scheduleAutosave()
        }
        .onChange(of: tagInput) { _, newValue in
            performTagSearch(query: newValue)
        }
        .onDisappear {
            autosaveTask?.cancel()
            tagSearchTask?.cancel()
            mentionSearchTask?.cancel()
            uploadResolutionTask?.cancel()
            Task {
                await persistDraftIfNeeded()
            }
        }
    }

    private var createTopicHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)
                .font(.title3.weight(.semibold))

            HStack(spacing: 10) {
                Button {
                    showCategorySheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(FireTheme.accent)
                        Text(selectedCategory.map(categoryDisplayName(for:)) ?? "选择分类")
                            .foregroundStyle(selectedCategory == nil ? .secondary : .primary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            if canTagTopics {
                VStack(alignment: .leading, spacing: 10) {
                    if !selectedTags.isEmpty {
                        FlowLayout(spacing: 8, fallbackWidth: max(UIScreen.main.bounds.width - 32, 200)) {
                            ForEach(selectedTags, id: \.self) { tag in
                                selectedTagChip(tag)
                            }
                        }
                    }

                    TextField("添加标签", text: $tagInput)
                        .textFieldStyle(.roundedBorder)

                    if !tagResults.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(tagResults, id: \.name) { item in
                                Button {
                                    addTag(item.name)
                                } label: {
                                    HStack {
                                        Text("#\(item.name)")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if item.count > 0 {
                                            Text("\(item.count)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.plain)

                                if item.name != tagResults.last?.name {
                                    Divider()
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }

                    if selectedCategoryMinimumTags > 0 {
                        Text("当前分类至少需要 \(selectedCategoryMinimumTags) 个标签")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var replyTargetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.topicTitle ?? "回复话题")
                .font(.headline)
            if let replyToUsername = route.replyToUsername, !replyToUsername.isEmpty {
                Text("回复 @\(replyToUsername)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
            } else if let replyToPostNumber = route.replyToPostNumber {
                Text("回复 #\(replyToPostNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var composerToolbar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label(isUploadingImage ? "上传中" : "图片", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(isUploadingImage || isSubmitting)

            Button {
                previewMode.toggle()
            } label: {
                Label(previewMode ? "继续编辑" : "预览", systemImage: previewMode ? "pencil" : "eye")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)

            Spacer()

            if route.kind == .createTopic {
                Text("\(title.count)/\(minimumTitleLength)+")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(trimmedBody.count)/\(minimumBodyLength)+")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            FireComposerTextView(
                text: $bodyText,
                selectedRange: $bodySelection,
                isFirstResponder: $isBodyFocused
            )
            .frame(minHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )

            if let mentionContext, (!mentionUsers.isEmpty || !mentionGroups.isEmpty) {
                mentionResultsList(mentionContext: mentionContext)
            }

            if trimmedBody.count > 0 && trimmedBody.count < minimumBodyLength {
                Text("正文至少需要 \(minimumBodyLength) 个字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if case .createTopic = route.kind {
                Text(trimmedTitle.isEmpty ? "（无标题）" : trimmedTitle)
                    .font(.title2.weight(.bold))
            }

            if let selectedCategory {
                Text(categoryDisplayName(for: selectedCategory))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FireTheme.accent)
            }

            if !selectedTags.isEmpty {
                FlowLayout(spacing: 8, fallbackWidth: max(UIScreen.main.bounds.width - 32, 200)) {
                    ForEach(selectedTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(FireTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(FireTheme.accent.opacity(0.12))
                            )
                    }
                }
            }

            if let attributed = previewAttributedText {
                Text(attributed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("暂无内容")
                    .foregroundStyle(.secondary)
            }

            if !markdownImages.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("图片预览")
                        .font(.subheadline.weight(.semibold))
                    ForEach(markdownImages) { image in
                        if let url = resolvedURL(for: image.urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 20)
                                case .success(let loaded):
                                    loaded
                                        .resizable()
                                        .scaledToFit()
                                        .clipShape(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        )
                                case .failure:
                                    previewImageFallback(label: image.altText ?? image.urlString)
                                @unknown default:
                                    previewImageFallback(label: image.altText ?? image.urlString)
                                }
                            }
                        } else {
                            previewImageFallback(label: image.altText ?? image.urlString)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var bottomActionBar: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 12) {
                if draftSequence > 0 {
                    Button("清除草稿") {
                        Task {
                            try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                            draftSequence = 0
                            noticeMessage = "草稿已清除"
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                Spacer()

                Button {
                    submitComposer()
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(route.submitLabel)
                            .font(.headline)
                    }
                    .frame(minWidth: 120)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(canSubmit ? FireTheme.accent : Color(.tertiaryLabel))
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func noticeBanner(_ message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tint == .red ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func selectedTagChip(_ tag: String) -> some View {
        Button {
            selectedTags.removeAll { $0 == tag }
        } label: {
            HStack(spacing: 6) {
                Text("#\(tag)")
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

    private func mentionResultsList(mentionContext: FireComposerMentionContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(mentionUsers, id: \.username) { user in
                Button {
                    insertMention("@\(user.username)")
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

                if user.username != mentionUsers.last?.username || !mentionGroups.isEmpty {
                    Divider()
                }
            }

            ForEach(mentionGroups, id: \.name) { group in
                Button {
                    insertMention("@\(group.name)")
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(FireTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("@\(group.name)")
                                .foregroundStyle(.primary)
                            if let fullName = group.fullName, !fullName.isEmpty {
                                Text(fullName)
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

                if group.name != mentionGroups.last?.name {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func previewImageFallback(label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    private var previewAttributedText: AttributedString? {
        guard !trimmedBody.isEmpty else {
            return nil
        }
        if let attributed = try? AttributedString(markdown: bodyText) {
            return attributed
        }
        return AttributedString(bodyText)
    }

    private func categoryDisplayName(for category: FireTopicCategoryPresentation) -> String {
        guard let parentID = category.parentCategoryId,
              let parent = viewModel.allCategories().first(where: { $0.id == parentID })
        else {
            return category.displayName
        }
        return "\(parent.displayName) / \(category.displayName)"
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !selectedTags.contains(trimmed) else { return }
        selectedTags.append(trimmed)
        tagInput = ""
        tagResults = []
    }

    private func updateMentionSearch() {
        mentionSearchTask?.cancel()
        mentionContext = mentionContext(in: bodyText, selection: bodySelection)
        guard let mentionContext, !mentionContext.term.isEmpty else {
            mentionUsers = []
            mentionGroups = []
            return
        }

        mentionSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchUsers(
                    term: mentionContext.term,
                    includeGroups: true,
                    limit: 8,
                    topicID: route.topicID,
                    categoryID: selectedCategoryID ?? route.fallbackCategoryID
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    mentionUsers = result.users
                    mentionGroups = result.groups
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    mentionUsers = []
                    mentionGroups = []
                }
            }
        }
    }

    private func performTagSearch(query: String) {
        tagSearchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tagResults = []
            return
        }

        tagSearchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                let result = try await viewModel.searchTags(
                    query: trimmed,
                    filterForInput: true,
                    limit: 12,
                    categoryID: selectedCategoryID,
                    selectedTags: selectedTags
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let allowedTags = Set(selectedCategory?.allowedTags ?? [])
                    if allowedTags.isEmpty {
                        tagResults = result.results
                    } else {
                        tagResults = result.results.filter { allowedTags.contains($0.name) }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    tagResults = []
                }
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
        } else if let initialBody, bodyText.isEmpty {
            bodyText = initialBody
        }

        isLoadingDraft = true
        defer {
            isLoadingDraft = false
            isBodyFocused = true
        }

        do {
            if let draft = try await viewModel.fetchDraft(draftKey: route.draftKey) {
                draftSequence = draft.sequence
                if case .createTopic = route.kind {
                    title = draft.data.title ?? title
                    bodyText = draft.data.reply ?? bodyText
                    selectedCategoryID = draft.data.categoryId ?? selectedCategoryID
                    selectedTags = draft.data.tags
                } else {
                    bodyText = draft.data.reply ?? bodyText
                }
                if draft.data.reply != nil || draft.data.title != nil {
                    noticeMessage = "已恢复草稿"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        if case .createTopic = route.kind {
            applyDefaultCategoryIfNeeded()
            applyCategoryTemplateIfNeeded()
        }
        resolveShortUploadsIfNeeded()
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

    private func scheduleAutosave() {
        guard didLoadDraft else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await persistDraftIfNeeded()
        }
    }

    @MainActor
    private func persistDraftIfNeeded() async {
        guard !isSubmitting else { return }

        if !hasDraftContent {
            guard draftSequence > 0 else { return }
            do {
                try await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                draftSequence = 0
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let draftData = DraftDataState(
            reply: bodyText,
            title: route.kind == .createTopic ? title : nil,
            categoryId: route.kind == .createTopic ? selectedCategoryID : nil,
            tags: route.kind == .createTopic ? selectedTags : [],
            replyToPostNumber: route.replyToPostNumber,
            action: route.kind == .createTopic ? "create_topic" : "reply",
            recipients: [],
            archetypeId: "regular",
            composerTime: nil,
            typingTime: nil
        )

        do {
            draftSequence = try await viewModel.saveDraft(
                draftKey: route.draftKey,
                data: draftData,
                sequence: draftSequence
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitComposer() {
        errorMessage = nil
        noticeMessage = nil

        switch route.kind {
        case .createTopic:
            guard !trimmedTitle.isEmpty else {
                errorMessage = "标题不能为空。"
                return
            }
            guard trimmedTitle.count >= minimumTitleLength else {
                errorMessage = "标题至少需要 \(minimumTitleLength) 个字。"
                return
            }
            guard let selectedCategoryID else {
                errorMessage = "请选择分类。"
                return
            }
            guard !trimmedBody.isEmpty else {
                errorMessage = "正文不能为空。"
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                errorMessage = "正文至少需要 \(minimumBodyLength) 个字。"
                return
            }
            guard selectedTags.count >= selectedCategoryMinimumTags else {
                errorMessage = "当前分类至少需要 \(selectedCategoryMinimumTags) 个标签。"
                return
            }

            isSubmitting = true
            Task { @MainActor in
                defer { isSubmitting = false }
                do {
                    let topicID = try await viewModel.createTopic(
                        title: trimmedTitle,
                        raw: trimmedBody,
                        categoryID: selectedCategoryID,
                        tags: selectedTags
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    onTopicCreated?(topicID)
                    dismiss()
                } catch {
                    let message = error.localizedDescription
                    if message.localizedCaseInsensitiveContains("pending review") {
                        try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                        draftSequence = 0
                        noticeMessage = "帖子已提交，等待审核。"
                        dismiss()
                        return
                    }
                    errorMessage = message
                }
            }

        case .advancedReply(let topicID, _, _, let replyToPostNumber, _):
            guard !trimmedBody.isEmpty else {
                errorMessage = "回复内容不能为空。"
                return
            }
            guard trimmedBody.count >= minimumBodyLength else {
                errorMessage = "回复至少需要 \(minimumBodyLength) 个字。"
                return
            }

            isSubmitting = true
            Task { @MainActor in
                defer { isSubmitting = false }
                do {
                    try await viewModel.submitReply(
                        topicId: topicID,
                        raw: trimmedBody,
                        replyToPostNumber: replyToPostNumber
                    )
                    try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                    draftSequence = 0
                    onReplySubmitted?()
                    dismiss()
                } catch {
                    let message = error.localizedDescription
                    if message.localizedCaseInsensitiveContains("pending review") {
                        try? await viewModel.deleteDraft(draftKey: route.draftKey, sequence: draftSequence)
                        draftSequence = 0
                        noticeMessage = "回复已提交，等待审核。"
                        onReplySubmitted?()
                        dismiss()
                        return
                    }
                    errorMessage = message
                }
            }
        }
    }

    private func insertMention(_ mention: String) {
        replaceText(in: mentionContext?.replacementRange ?? bodySelection, with: "\(mention) ")
        mentionContext = nil
        mentionUsers = []
        mentionGroups = []
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
    }

    private func handleSelectedPhoto(_ item: PhotosPickerItem) {
        Task { @MainActor in
            defer { selectedPhoto = nil }
            do {
                isUploadingImage = true
                let bytes = try await item.loadTransferable(type: Data.self)
                guard let bytes else {
                    isUploadingImage = false
                    errorMessage = "读取图片失败。"
                    return
                }
                let type = item.supportedContentTypes.first
                let ext = type?.preferredFilenameExtension ?? "jpg"
                let mimeType = type?.preferredMIMEType ?? "image/jpeg"
                let fileName = "fire-\(UUID().uuidString).\(ext)"
                let result = try await viewModel.uploadImage(
                    fileName: fileName,
                    mimeType: mimeType,
                    bytes: Array(bytes)
                )
                let markdown = markdownForUpload(result)
                let prefix = bodySelection.location == 0 ? "" : "\n"
                replaceText(in: bodySelection, with: "\(prefix)\(markdown)\n")
                resolveShortUploadsIfNeeded()
            } catch {
                errorMessage = error.localizedDescription
            }
            isUploadingImage = false
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
                await MainActor.run {
                    for item in resolved {
                        resolvedUploads[item.shortUrl] = item
                    }
                }
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
}

private struct FireComposerCategorySheet: View {
    let categories: [FireTopicCategoryPresentation]
    let selectedCategoryID: UInt64?
    let categoryLabel: (FireTopicCategoryPresentation) -> String
    let onSelect: (UInt64) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(categories, id: \.id) { category in
            Button {
                onSelect(category.id)
                dismiss()
            } label: {
                HStack {
                    Text(categoryLabel(category))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedCategoryID == category.id {
                        Image(systemName: "checkmark")
                            .foregroundStyle(FireTheme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("选择分类")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FireComposerTextView: UIViewRepresentable {
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
