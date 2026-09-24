import Foundation

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
}
