import SwiftUI

struct FirePostEditorView: View {
    @ObservedObject var viewModel: FireAppViewModel
    let topicID: UInt64
    let postID: UInt64
    let postNumber: UInt32
    var onSaved: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var rawText = ""
    @State private var editReason = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

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
                    TextEditor(text: $rawText)
                        .frame(minHeight: 280)
                        .font(.body)
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
            }
        }
        .task {
            await loadPost()
        }
    }

    private func loadPost() async {
        guard rawText.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let post = try await viewModel.fetchPost(postID: postID)
            rawText = post.raw ?? plainTextFromHtml(rawHtml: post.cooked)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
