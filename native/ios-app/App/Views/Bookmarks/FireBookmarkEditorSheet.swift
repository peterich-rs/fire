import SwiftUI
import UIKit

struct FireBookmarkEditorContext: Identifiable, Equatable {
    let bookmarkID: UInt64?
    let bookmarkableID: UInt64
    let bookmarkableType: String
    let title: String
    let initialName: String?
    let initialReminderAt: String?
    let allowsDelete: Bool

    var id: String {
        "\(bookmarkID ?? 0)-\(bookmarkableType)-\(bookmarkableID)"
    }
}

struct FireBookmarkEditorSheet: View {
    let context: FireBookmarkEditorContext
    let onSave: (String?, String?) async throws -> Void
    let onDelete: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var hasReminder: Bool
    @State private var reminderDate: Date
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var saveCompletionPulse: Int = 0

    init(
        context: FireBookmarkEditorContext,
        onSave: @escaping (String?, String?) async throws -> Void,
        onDelete: (() async throws -> Void)? = nil
    ) {
        self.context = context
        self.onSave = onSave
        self.onDelete = onDelete
        let parsedReminder = Self.parseReminder(context.initialReminderAt)
        _name = State(initialValue: context.initialName ?? "")
        _hasReminder = State(initialValue: parsedReminder != nil)
        _reminderDate = State(initialValue: parsedReminder ?? Date().addingTimeInterval(3600))
    }

    private var trimmedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var reminderAt: String? {
        guard hasReminder else {
            return nil
        }
        return Self.isoFormatter.string(from: reminderDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(context.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(FireTheme.ink)
                } header: {
                    Text("目标")
                }

                Section {
                    TextField("备注名称", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                } header: {
                    Text("名称")
                } footer: {
                    Text("名称为空时会清除备注。")
                }

                Section {
                    Toggle("设置提醒", isOn: $hasReminder.animation(.easeInOut(duration: 0.2)))
                    if hasReminder {
                        DatePicker(
                            "提醒时间",
                            selection: $reminderDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                } header: {
                    Text("提醒")
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

                if context.allowsDelete, let onDelete {
                    Section {
                        Button("删除书签", role: .destructive) {
                            Task {
                                await submitDelete(onDelete)
                            }
                        }
                        .disabled(isSubmitting)
                    }
                }
            }
            .navigationTitle(context.bookmarkID == nil ? "添加书签" : "编辑书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await submitSave()
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("保存")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmitting)
                    .fireCTAPress()
                    .fireSuccessFeedback(trigger: saveCompletionPulse)
                }
            }
        }
    }

    private func submitSave() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await onSave(trimmedName, reminderAt)
            saveCompletionPulse += 1
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitDelete(_ onDelete: @escaping () async throws -> Void) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await onDelete()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseReminder(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        return fractionalISOFormatter.date(from: rawValue) ?? isoFormatter.date(from: rawValue)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
