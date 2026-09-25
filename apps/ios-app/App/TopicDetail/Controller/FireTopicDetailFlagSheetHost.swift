import SwiftUI

struct FireTopicDetailFlagSheetHost: View {
    @ObservedObject var store: FireTopicDetailStore

    let topicID: UInt64
    let context: FirePostManagementContext
    let onSubmitted: @MainActor (String) -> Void

    @State private var isLoadingOptions = false

    var body: some View {
        FirePostFlagSheet(
            context: context,
            options: FirePostFlagOption.options(from: store.snapshot(for: topicID)?.flagTypes ?? []),
            isLoadingOptions: isLoadingOptions
        ) { option, message in
            try await store.flagPost(
                topicId: topicID,
                postId: context.postID,
                flagTypeId: option.id,
                message: message
            )
            await MainActor.run {
                onSubmitted("举报已提交。")
            }
        }
        .task {
            guard (store.snapshot(for: topicID)?.flagTypes ?? []).isEmpty else {
                return
            }
            isLoadingOptions = true
            defer { isLoadingOptions = false }
            try? await store.ensureFlagTypes(topicId: topicID)
        }
    }
}
