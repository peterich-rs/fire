import SwiftUI
import UIKit

struct FireTopicEditorView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let topicID: UInt64
    let initialTitle: String
    let initialCategoryID: UInt64?
    let initialTags: [String]
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var selectedCategoryID: UInt64?
    @State private var selectedTags: [String]
    @State private var tagInput = ""
    @State private var tagResults: [TagSearchItemState] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        viewModel: FireAppViewModel,
        topicID: UInt64,
        initialTitle: String,
        initialCategoryID: UInt64?,
        initialTags: [String],
        onSaved: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.topicID = topicID
        self.initialTitle = initialTitle
        self.initialCategoryID = initialCategoryID
        self.initialTags = initialTags
        self.onSaved = onSaved
        _title = State(initialValue: initialTitle)
        _selectedCategoryID = State(initialValue: initialCategoryID)
        _selectedTags = State(initialValue: initialTags)
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

    private var minimumRequiredTags: Int {
        Int(selectedCategory?.minimumRequiredTags ?? 0)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategoryID != nil
            && selectedTags.count >= minimumRequiredTags
            && !isSaving
    }

    var body: some View {
        Form {
            if let errorMessage, !errorMessage.isEmpty {
                Section {
                    FireErrorBanner(
                        message: errorMessage,
                        copied: false,
                        onCopy: {},
                        onDismiss: {
                            self.errorMessage = nil
                        }
                    )
                }
            }

            Section("话题信息") {
                TextField("标题", text: $title)

                Picker("分类", selection: $selectedCategoryID) {
                    Text("选择分类").tag(Optional<UInt64>.none)
                    ForEach(availableCategories, id: \.id) { category in
                        Text(categoryDisplayName(for: category)).tag(Optional(category.id))
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if !selectedTags.isEmpty {
                        FlowLayout(spacing: 8, fallbackWidth: max(UIScreen.main.bounds.width - 48, 220)) {
                            ForEach(selectedTags, id: \.self) { tag in
                                Button {
                                    selectedTags.removeAll { $0 == tag }
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("#\(tag)")
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(FireTheme.accent)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(FireTheme.accent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    TextField("添加标签", text: $tagInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if minimumRequiredTags > 0 {
                    Text("当前分类至少需要 \(minimumRequiredTags) 个标签。")
                        .font(.caption)
                        .foregroundStyle(FireTheme.subtleInk)
                }
            }

            if !tagResults.isEmpty {
                Section("标签建议") {
                    ForEach(tagResults, id: \.name) { item in
                        Button {
                            addTag(item.name)
                        } label: {
                            HStack {
                                Text("#\(item.name)")
                                Spacer()
                                if selectedTags.contains(item.name) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(FireTheme.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("编辑话题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    Task { await save() }
                }
                .disabled(!canSubmit)
            }
        }
        .onChange(of: tagInput) { _, newValue in
            searchTags(query: newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func save() async {
        guard let categoryID = selectedCategoryID else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.updateTopic(
                topicID: topicID,
                title: title,
                categoryID: categoryID,
                tags: selectedTags
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addTag(_ tag: String) {
        guard !selectedTags.contains(tag) else {
            tagInput = ""
            tagResults = []
            return
        }
        selectedTags.append(tag)
        tagInput = ""
        tagResults = []
    }

    private func searchTags(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tagResults = []
            return
        }

        searchTask = Task {
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

    private func categoryDisplayName(for category: FireTopicCategoryPresentation) -> String {
        category.displayName
    }
}
