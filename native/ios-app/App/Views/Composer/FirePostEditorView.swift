import SwiftUI

struct FirePostEditorView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let topicID: UInt64
    let postID: UInt64
    let postNumber: UInt32
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var rawText = ""
    @State private var rawTextSelection = NSRange(location: 0, length: 0)
    @State private var isRawTextFocused = false
    @State private var editReason = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saveCompletionPulse: Int = 0
    @State private var errorFeedbackPulse: Int = 0

    private var canSubmit: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isLoading
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

            Section("正文") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    FireMarkdownToolbar(onFormat: applyMarkdownFormat)

                    FireComposerTextView(
                        text: $rawText,
                        selectedRange: $rawTextSelection,
                        isFirstResponder: $isRawTextFocused
                    )
                        .frame(minHeight: 280)
                        .background(
                            RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                                .fill(FireTheme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: FireTheme.cornerRadius, style: .continuous)
                                .strokeBorder(FireTheme.divider, lineWidth: 1)
                        )
                }
            }

            Section("编辑原因") {
                TextField("可选，告诉大家你改了什么", text: $editReason)
            }
        }
        .navigationTitle("编辑 #\(postNumber)")
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
                .fireCTAPress()
                .fireSuccessFeedback(trigger: saveCompletionPulse)
            }
        }
        .task {
            await loadPost()
        }
        .fireErrorFeedback(trigger: errorFeedbackPulse)
    }

    private func loadPost() async {
        guard rawText.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let post = try await viewModel.fetchPost(postID: postID)
            if let raw = post.raw,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rawText = raw
                rawTextSelection = NSRange(location: (raw as NSString).length, length: 0)
                errorMessage = nil
            } else {
                showError("服务端未返回可编辑原文，无法打开编辑器")
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func applyMarkdownFormat(_ action: FireMarkdownFormatAction) {
        let result = FireMarkdownInsertion.apply(
            action,
            text: rawText,
            selectedRange: rawTextSelection
        )
        rawText = result.text
        rawTextSelection = result.selectedRange
        isRawTextFocused = true
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await viewModel.updatePost(
                topicID: topicID,
                postID: postID,
                raw: rawText,
                editReason: editReason.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("")
            )
            saveCompletionPulse += 1
            onSaved?()
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorFeedbackPulse += 1
    }
}
