import SwiftUI
import UIKit
import UserNotifications

struct FireBookmarkEditorContext: Identifiable, Equatable {
    let bookmarkID: UInt64?
    let bookmarkableID: UInt64
    let bookmarkableType: String
    let topicID: UInt64?
    let postNumber: UInt32?
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
    @State private var deleteCompletionPulse: Int = 0
    @State private var errorFeedbackPulse: Int = 0

    init(
        context: FireBookmarkEditorContext,
        onSave: @escaping (String?, String?) async throws -> Void,
        onDelete: (() async throws -> Void)? = nil
    ) {
        self.context = context
        self.onSave = onSave
        self.onDelete = onDelete
        let parsedReminder = Self.parseReminder(context.initialReminderAt)
            .flatMap { $0 > Date() ? $0 : nil }
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
        return fireBookmarkReminderISOFormatter.string(from: reminderDate)
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
        .fireSuccessFeedback(trigger: deleteCompletionPulse)
        .fireErrorFeedback(trigger: errorFeedbackPulse)
    }

    private func submitSave() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await onSave(trimmedName, reminderAt)
            await FireBookmarkReminderScheduler.sync(context: context, reminderAt: reminderAt)
            saveCompletionPulse += 1
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func submitDelete(_ onDelete: @escaping () async throws -> Void) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await onDelete()
            await FireBookmarkReminderScheduler.cancel(context: context)
            deleteCompletionPulse += 1
            dismiss()
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        errorMessage = message
        errorFeedbackPulse += 1
    }

    private static func parseReminder(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }
        return fireBookmarkReminderFractionalISOFormatter.date(from: rawValue)
            ?? fireBookmarkReminderISOFormatter.date(from: rawValue)
    }
}

enum FireBookmarkReminderScheduler {
    private static let threadIdentifier = "linux.do.bookmark-reminder"

    static func sync(context: FireBookmarkEditorContext, reminderAt: String?) async {
        guard let reminderAt,
              let date = fireBookmarkReminderFractionalISOFormatter.date(from: reminderAt)
                ?? fireBookmarkReminderISOFormatter.date(from: reminderAt),
              date > Date() else {
            await cancel(context: context)
            return
        }

        do {
            guard try await canScheduleNotifications() else {
                return
            }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier(for: context)])

            let content = UNMutableNotificationContent()
            content.title = "书签提醒"
            content.body = context.title
            content.sound = .default
            content.threadIdentifier = threadIdentifier
            content.userInfo = userInfo(for: context)

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: date
            )
            let request = UNNotificationRequest(
                identifier: identifier(for: context),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try await center.add(request)
        } catch {
            return
        }
    }

    static func cancel(context: FireBookmarkEditorContext) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(for: context)]
        )
    }

    private static func canScheduleNotifications() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private static func identifier(for context: FireBookmarkEditorContext) -> String {
        "fire.bookmark-reminder.\(context.bookmarkableType.lowercased()).\(context.bookmarkableID)"
    }

    private static func userInfo(for context: FireBookmarkEditorContext) -> [String: Any] {
        var userInfo: [String: Any] = [
            "title": context.title,
            "bookmarkableId": context.bookmarkableID,
            "bookmarkableType": context.bookmarkableType,
        ]
        if let topicID = context.topicID ?? topicIDFromBookmarkableContext(context) {
            userInfo["topicId"] = topicID
        }
        if let postNumber = context.postNumber {
            userInfo["postNumber"] = postNumber
        }
        return userInfo
    }

    private static func topicIDFromBookmarkableContext(_ context: FireBookmarkEditorContext) -> UInt64? {
        context.bookmarkableType.caseInsensitiveCompare("Topic") == .orderedSame
            ? context.bookmarkableID
            : nil
    }
}

private let fireBookmarkReminderISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private let fireBookmarkReminderFractionalISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()
