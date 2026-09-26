import Foundation
import UIKit
import WebKit

extension FireAppViewModel {
    func startMessageBus() async {
        guard let sessionStore else { return }
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }

        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil

        let coordinator = FireMessageBusCoordinator { [weak self] event in
            self?.handleMessageBusEvent(event)
        }
        messageBusCoordinator = coordinator

        do {
            _ = try await FireAPMManager.shared.withSpan(.messageBusStart) {
                try await sessionStore.startMessageBus(handler: coordinator)
            }
            isMessageBusActive = true
            messageBusStartRetryCount = 0
            clearMessageBusError()
        } catch {
            messageBusCoordinator = nil
            if await handleRecoverableSessionErrorIfNeeded(error) {
                return
            }
            errorMessage = Self.messageBusErrorPrefix + error.localizedDescription
            scheduleMessageBusRetry()
        }
    }

    func stopMessageBus() {
        messageBusRetryTask?.cancel()
        messageBusRetryTask = nil
        messageBusStartRetryCount = 0
        notificationStore?.cancelScheduledRefresh()
        homeFeedStore?.handleMessageBusStopped()
        clearMessageBusError()
        guard isMessageBusActive else { return }
        messageBusCoordinator = nil
        isMessageBusActive = false
        guard let sessionStore else { return }
        Task { try? await sessionStore.stopMessageBus(clearSubscriptions: true) }
    }

    private func handleMessageBusEvent(_ event: MessageBusEventState) {
        switch event.kind {
        case .topicList:
            homeFeedStore?.handleTopicListMessageBusEvent(event)

        case .topicDetail, .topicReaction, .presence:
            break

        case .notification:
            notificationStore?.scheduleStateRefresh()

        case .notificationAlert:
            break

        case .chat:
            Task { await chatChannelsStore?.handleMessageBusEvent(event) }
            NotificationCenter.default.post(
                name: .fireChatMessageBusEvent,
                object: nil,
                userInfo: ["event": event]
            )

        case .sessionLogout:
            serverForcedLogout = true
            cancelMidSessionReauth(reason: "server_forced_logout")

        case .unknown:
            break
        }
    }

    func beginTopicReplyPresence(topicId: UInt64) {
        topicDetailStore?.beginReplyTyping(topicId: topicId)
    }

    func endTopicReplyPresence(topicId: UInt64) async {
        topicDetailStore?.endReplyTyping(topicId: topicId)
    }

    // MARK: - Private helpers

    private func scheduleMessageBusRetry() {
        guard session.readiness.canOpenMessageBus else { return }
        guard !isMessageBusActive else { return }
        guard messageBusStartRetryCount < 3 else { return }

        messageBusStartRetryCount += 1
        let retryDelay = Duration.seconds(Double(messageBusStartRetryCount * 2))
        messageBusRetryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: retryDelay)
            } catch {
                return
            }
            guard let self else { return }
            self.messageBusRetryTask = nil
            await self.startMessageBus()
        }
    }

    private func clearMessageBusError() {
        if errorMessage?.hasPrefix(Self.messageBusErrorPrefix) == true {
            errorMessage = nil
        }
    }

    /// Write-path CF wrapper. **Passthrough** — does not wait or present.
    ///
    /// Rust already fails writes quickly with `CloudflareChallengeInProgress`
    /// while a challenge is active. Host-side wait/retry would hang composer
    /// actions for up to minutes with no UI feedback; callers should surface
    /// the error and let the user retry after verification.
    func ensureMessageBusActiveIfPossible() async {
        guard !isMessageBusActive else { return }
        await startMessageBus()
    }

    func restartMessageBusAfterClearanceIfPossible() async {
        if isMessageBusActive {
            stopMessageBus()
        }
        await startMessageBus()
    }
}
