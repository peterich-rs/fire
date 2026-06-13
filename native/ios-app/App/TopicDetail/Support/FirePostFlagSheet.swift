import SwiftUI

// MARK: - Post Flag Option Model

struct FirePostFlagOption: Identifiable, Equatable, Hashable {
    let id: UInt32
    let nameKey: String
    let title: String
    let detail: String
    let requireMessage: Bool
    let position: Int32

    static let fallbackOptions: [Self] = [
        .init(
            id: 3,
            nameKey: "off_topic",
            title: "偏离主题",
            detail: "这个回复明显偏离当前话题。",
            requireMessage: false,
            position: 1
        ),
        .init(
            id: 4,
            nameKey: "inappropriate",
            title: "不当内容",
            detail: "这个回复包含不适合社区的内容。",
            requireMessage: false,
            position: 2
        ),
        .init(
            id: 8,
            nameKey: "spam",
            title: "垃圾信息",
            detail: "这个回复像广告、灌水或重复垃圾信息。",
            requireMessage: false,
            position: 3
        ),
        .init(
            id: 7,
            nameKey: "notify_moderators",
            title: "通知版主",
            detail: "需要版主人工判断，请补充说明。",
            requireMessage: true,
            position: 4
        )
    ]

    init(type: PostActionTypeState) {
        self.id = type.id
        self.nameKey = type.nameKey
        self.title = Self.displayTitle(for: type)
        self.detail = Self.displayDetail(for: type)
        self.requireMessage = type.requireMessage
        self.position = type.position
    }

    private init(
        id: UInt32,
        nameKey: String,
        title: String,
        detail: String,
        requireMessage: Bool,
        position: Int32
    ) {
        self.id = id
        self.nameKey = nameKey
        self.title = title
        self.detail = detail
        self.requireMessage = requireMessage
        self.position = position
    }

    static func options(from actionTypes: [PostActionTypeState]) -> [Self] {
        let options = actionTypes
            .filter { type in
                type.isFlag
                    && type.enabled
                    && (type.appliesTo.isEmpty || type.appliesTo.contains("Post"))
            }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position {
                    return lhs.position < rhs.position
                }
                return lhs.id < rhs.id
            }
            .map(Self.init(type:))
        return options.isEmpty ? fallbackOptions : options
    }

    static func displayTitle(for type: PostActionTypeState) -> String {
        let fallback = fallbackTitle(nameKey: type.nameKey, id: type.id)
        return type.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty(fallback)
    }

    static func displayDetail(for type: PostActionTypeState) -> String {
        let raw = (type.description.ifEmpty(type.shortDescription ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            return plainTextFromHtml(rawHtml: raw)
        }
        return fallbackDetail(nameKey: type.nameKey, id: type.id)
    }

    static func fallbackTitle(nameKey: String, id: UInt32) -> String {
        switch nameKey {
        case "off_topic": "偏离主题"
        case "inappropriate": "不当内容"
        case "spam": "垃圾信息"
        case "notify_moderators": "通知版主"
        case "notify_user": "私信提醒作者"
        default:
            switch id {
            case 3: "偏离主题"
            case 4: "不当内容"
            case 7: "通知版主"
            case 8: "垃圾信息"
            default: "举报"
            }
        }
    }

    static func fallbackDetail(nameKey: String, id: UInt32) -> String {
        switch nameKey {
        case "off_topic": "这个回复明显偏离当前话题。"
        case "inappropriate": "这个回复包含不适合社区的内容。"
        case "spam": "这个回复像广告、灌水或重复垃圾信息。"
        case "notify_moderators": "需要版主人工判断，请补充说明。"
        case "notify_user": "向作者发送提醒。"
        default:
            switch id {
            case 3: "这个回复明显偏离当前话题。"
            case 4: "这个回复包含不适合社区的内容。"
            case 7: "需要版主人工判断，请补充说明。"
            case 8: "这个回复像广告、灌水或重复垃圾信息。"
            default: "向社区管理人员报告这个回复。"
            }
        }
    }
}

// MARK: - Post Flag Sheet

struct FirePostFlagSheet: View {
    @Environment(\.dismiss) private var dismiss
    let context: FirePostManagementContext
    let options: [FirePostFlagOption]
    let isLoadingOptions: Bool
    let onSubmit: (FirePostFlagOption, String?) async throws -> Void

    @State private var selectedOptionID: FirePostFlagOption.ID?
    @State private var message = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var resolvedOptions: [FirePostFlagOption] {
        options.isEmpty ? FirePostFlagOption.fallbackOptions : options
    }

    private var selectedOption: FirePostFlagOption? {
        if let selectedOptionID,
           let selected = resolvedOptions.first(where: { $0.id == selectedOptionID }) {
            return selected
        }
        return resolvedOptions.first
    }

    var body: some View {
        NavigationStack {
            flagForm
            .navigationTitle("举报 #\(context.postNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { flagToolbar }
        }
        .onAppear {
            syncSelectedOptionID()
        }
        .onChange(of: options) { _ in
            syncSelectedOptionID()
        }
    }

    private var flagForm: some View {
        Form {
            loadingSection
            optionSection
            messageSection
            errorSection
        }
    }

    @ViewBuilder
    private var loadingSection: some View {
        if isLoadingOptions {
            Section {
                ProgressView("加载举报类型…")
            }
        }
    }

    private var optionSection: some View {
        Section("举报类型") {
            ForEach(resolvedOptions) { option in
                FirePostFlagOptionRow(
                    option: option,
                    isSelected: selectedOption?.id == option.id,
                    description: description(for: option)
                ) {
                    selectedOptionID = option.id
                }
            }
        }
    }

    private var messageSection: some View {
        Section(selectedOption?.requireMessage == true ? "补充说明（必填）" : "补充说明") {
            TextEditor(text: $message)
                .frame(minHeight: 110)
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ToolbarContentBuilder
    private var flagToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("取消") {
                dismiss()
            }
            .disabled(isSubmitting)
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(isSubmitting ? "提交中" : "提交") {
                submit()
            }
            .disabled(isSubmitting || selectedOption == nil)
        }
    }

    private func submit() {
        guard !isSubmitting, let selectedOption else { return }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if selectedOption.requireMessage && trimmedMessage.isEmpty {
            errorMessage = "请补充举报说明。"
            return
        }
        isSubmitting = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await onSubmit(
                    selectedOption,
                    trimmedMessage.isEmpty ? nil : trimmedMessage
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }

    private func description(for option: FirePostFlagOption) -> String {
        let username = context.username?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifEmpty("该用户") ?? "该用户"
        return option.detail
            .replacingOccurrences(of: "%{username}", with: username)
            .replacingOccurrences(of: "@%{username}", with: "@\(username)")
    }

    private func syncSelectedOptionID() {
        selectedOptionID = selectedOption?.id
    }
}

// MARK: - Post Flag Option Row

struct FirePostFlagOptionRow: View {
    let option: FirePostFlagOption
    let isSelected: Bool
    let description: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? FireTheme.accent : FireTheme.tertiaryInk)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .foregroundStyle(FireTheme.ink)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(FireTheme.subtleInk)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
